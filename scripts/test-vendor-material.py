#!/usr/bin/env python3
"""Public importer behavior against small synthetic VSIX archives."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('import_material', Path(__file__).with_name('vendor-material.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ImportMaterialTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.dest = self.base / 'material'
        self.dest.mkdir()
        (self.dest / 'sentinel').write_text('keep')

    def artifact(self, *, traversal=False, missing=False, nonsvg=False,
                 theme_dir='dist', orphan=None):
        path = self.base / 'fixture.vsix'
        icon_path = ('../../' if '/' in theme_dir else '../') + ('icons/file.png' if nonsvg else 'icons/file.svg')
        theme = {'iconDefinitions': {'file': {'iconPath': icon_path}}, 'file': 'file'}
        if orphan:
            section, key = orphan
            if section in module.DEFAULT_KEYS:
                theme[section] = 'missing-id'
            else:
                target = theme.setdefault(section, {}) if section not in ('light', 'highContrast') else theme.setdefault(section, {}).setdefault('fileNames', {})
                target[key] = 'missing-id'
        package = {'version': '1.0.0', 'contributes': {'iconThemes': [
            {'id': 'material-icon-theme', 'path': './' + theme_dir + '/material-icons.json'}]}}
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('extension/package.json', json.dumps(package))
            archive.writestr('extension/' + theme_dir + '/material-icons.json', json.dumps(theme))
            archive.writestr('extension/LICENSE.txt', 'MIT fixture')
            if not missing:
                archive.writestr('extension/icons/file.svg', '<svg/>')
            if traversal:
                archive.writestr('extension/../escape.svg', '<svg/>')
        return path, hashlib.sha256(path.read_bytes()).hexdigest()

    def assert_untouched(self):
        self.assertEqual([p.name for p in self.dest.iterdir()], ['sentinel'])
        self.assertEqual((self.dest / 'sentinel').read_text(), 'keep')

    def test_valid_import_replaces_bundle(self):
        path, digest = self.artifact()
        self.assertEqual(module.import_artifact(path, '1.0.0', digest, self.dest), 1)
        self.assertFalse((self.dest / 'sentinel').exists())
        self.assertEqual((self.dest / 'icons/file.svg').read_text(), '<svg/>')
        self.assertEqual((self.dest / 'LICENSE.txt').read_text(), 'MIT fixture')
        provenance = json.loads((self.dest / 'provenance.json').read_text())
        self.assertTrue(provenance['requires_release_provenance_review'])
        self.assertNotIn('commit', provenance)
        self.assertNotIn('artifact_url', provenance)

    def test_theme_outside_dist_imports(self):
        path, digest = self.artifact(theme_dir='themes/generated')
        self.assertEqual(module.import_artifact(path, '1.0.0', digest, self.dest), 1)
        self.assertTrue((self.dest / 'themes/generated/material-icons.json').is_file())

    def test_orphaned_mappings_preserve_destination(self):
        for section, key in [(name, None) for name in module.DEFAULT_KEYS] + [
            (name, 'entry') for name in module.MAP_KEYS] + [
            ('light', 'readme'), ('highContrast', 'readme')]:
            with self.subTest(section=section):
                path, digest = self.artifact(orphan=(section, key))
                with self.assertRaisesRegex(ValueError, 'unknown icon ID'):
                    module.import_artifact(path, '1.0.0', digest, self.dest)
                self.assert_untouched()

    def test_traversal_preserves_destination(self):
        path, digest = self.artifact(traversal=True)
        with self.assertRaisesRegex(ValueError, 'unsafe archive path'):
            module.import_artifact(path, '1.0.0', digest, self.dest)
        self.assert_untouched()

    def test_wrong_checksum_preserves_destination(self):
        path, _ = self.artifact()
        with self.assertRaisesRegex(ValueError, 'SHA256 mismatch'):
            module.import_artifact(path, '1.0.0', '0' * 64, self.dest)
        self.assert_untouched()

    def test_wrong_version_preserves_destination(self):
        path, digest = self.artifact()
        with self.assertRaisesRegex(ValueError, 'version mismatch'):
            module.import_artifact(path, '2.0.0', digest, self.dest)
        self.assert_untouched()

    def test_missing_svg_preserves_destination(self):
        path, digest = self.artifact(missing=True)
        with self.assertRaisesRegex(ValueError, 'mapped SVG missing'):
            module.import_artifact(path, '1.0.0', digest, self.dest)
        self.assert_untouched()

    def test_non_svg_preserves_destination(self):
        path, digest = self.artifact(nonsvg=True)
        with self.assertRaisesRegex(ValueError, 'non-SVG'):
            module.import_artifact(path, '1.0.0', digest, self.dest)
        self.assert_untouched()


if __name__ == '__main__':
    unittest.main()
