#!/usr/bin/env python3
"""Import a pinned Material Icon Theme VSIX into the maintained bundle."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import tempfile
import zipfile
from datetime import datetime, timezone

DEST = Path(__file__).resolve().parents[1] / 'assets' / 'material'
SOURCE = 'material-extensions/vscode-material-icon-theme'


def safe_path(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or '\\' in name:
        raise ValueError(f'unsafe archive path: {name}')
    return path


def import_artifact(artifact, version, checksum, dest=DEST):
    artifact = Path(artifact)
    actual = hashlib.sha256(artifact.read_bytes()).hexdigest()
    if actual != checksum.lower():
        raise ValueError('artifact SHA256 mismatch')
    with zipfile.ZipFile(artifact) as archive:
        names = {str(safe_path(n)) for n in archive.namelist()}
        package = json.loads(archive.read('extension/package.json'))
        if package.get('version') != version:
            raise ValueError('artifact version mismatch')
        themes = package.get('contributes', {}).get('iconThemes', [])
        matches = [t for t in themes if t.get('id') == 'material-icon-theme']
        if len(matches) != 1:
            raise ValueError('generated Material theme missing or ambiguous')
        theme_path = safe_path(str(PurePosixPath('extension') / matches[0]['path']))
        if str(theme_path) not in names:
            raise ValueError('generated theme missing')
        theme = json.loads(archive.read(str(theme_path)))
        defs = theme.get('iconDefinitions')
        if not isinstance(defs, dict) or not defs:
            raise ValueError('theme has no icon definitions')
        paths = set()
        for definition in defs.values():
            icon_path = definition.get('iconPath')
            if not isinstance(icon_path, str) or PurePosixPath(icon_path).is_absolute() or PurePosixPath(icon_path).suffix.lower() != '.svg':
                raise ValueError('non-SVG or missing iconPath')
            parts = list(theme_path.parent.parts)
            for part in PurePosixPath(icon_path).parts:
                if part in ('', '.'):
                    continue
                if part == '..':
                    if len(parts) <= 1:
                        raise ValueError('iconPath escapes extension')
                    parts.pop()
                else:
                    parts.append(part)
            source_path = PurePosixPath(*parts)
            if str(source_path) not in names:
                raise ValueError(f'mapped SVG missing: {source_path}')
            paths.add(source_path)
        license_path = 'extension/LICENSE.txt'
        if license_path not in names:
            raise ValueError('upstream license missing')
        dest = Path(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.material-stage-', dir=dest.parent) as tmp:
            stage = Path(tmp) / 'bundle'
            stage.mkdir()
            for path in paths | {theme_path, PurePosixPath(license_path)}:
                target = stage.joinpath(*path.parts[1:])
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(str(path)))
            # Keep only the theme declaration required by pack.load().
            (stage / 'package.json').write_text(json.dumps({
                'version': version,
                'contributes': {'iconThemes': [{'id': 'material-icon-theme',
                                               'path': str(PurePosixPath(*theme_path.parts[1:]))}]}
            }, indent=2) + '\n')
            (stage / 'provenance.json').write_text(json.dumps({
                'source': SOURCE,
                'version': version,
                'tag': 'v' + version,
                'commit': '448ab3977ef83b817c2c722ce7cd5034d195b39f' if version == '5.38.1' else None,
                'artifact_url': f'https://github.com/{SOURCE}/releases/download/v{version}/material-icon-theme-{version}.vsix',
                'artifact_sha256': actual,
                'imported_at': datetime.now(timezone.utc).date().isoformat(),
                'license': 'LICENSE.txt',
            }, indent=2) + '\n')
            for definition in defs.values():
                resolved = (stage / 'dist' / definition['iconPath']).resolve()
                if not resolved.is_file() or not resolved.is_relative_to(stage.resolve()):
                    raise ValueError('staged theme mapping is invalid')
            backup = Path(tmp) / 'previous'
            if dest.exists():
                os.replace(dest, backup)
            try:
                os.replace(stage, dest)
            except Exception:
                if backup.exists():
                    os.replace(backup, dest)
                raise
    return len(paths)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', required=True, type=Path)
    parser.add_argument('--version', required=True)
    parser.add_argument('--sha256', required=True)
    args = parser.parse_args()
    print(f'Imported {import_artifact(args.artifact, args.version, args.sha256)} SVGs')
