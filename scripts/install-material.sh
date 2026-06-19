#!/usr/bin/env bash
# Install the Material Icon Theme SVG pack for svgtree, and regenerate the Lua
# resolver from the theme's manifest. Requires node + npm.
#
# Usage: scripts/install-material.sh
set -euo pipefail

PACKDIR="${SVGTREE_MATERIAL_DIR:-$HOME/.local/share/svgtree/material}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading material-icon-theme via npm…"
( cd "$TMP" && npm pack material-icon-theme >/dev/null 2>&1 )
TARBALL="$(ls "$TMP"/*.tgz | head -1)"
tar xzf "$TARBALL" -C "$TMP"
PKG="$TMP/package"

echo "==> Installing SVGs -> $PACKDIR"
mkdir -p "$PACKDIR"
cp "$PKG"/icons/*.svg "$PACKDIR"/
echo "    $(ls "$PACKDIR"/*.svg | wc -l | tr -d ' ') icons installed"

echo "==> Regenerating resolver -> lua/svgtree/packs/material_map.lua"
MANIFEST="$PKG/dist/material-icons.json"
node - "$MANIFEST" "$PACKDIR" "$REPO_ROOT/lua/svgtree/packs/material_map.lua" "$PKG/package.json" <<'NODE'
const fs = require('fs'), path = require('path');
const [, , manifestPath, packDir, outPath, pkgPath] = process.argv;
const m = require(manifestPath), pkg = require(pkgPath);
const exists = new Set(fs.readdirSync(packDir).filter(f => f.endsWith('.svg')).map(f => f.slice(0, -4)));
const stemOf = (n) => { const d = m.iconDefinitions[n]; if (!d || !d.iconPath) return null;
  const s = path.basename(d.iconPath).replace(/\.svg$/, ''); return exists.has(s) ? s : null; };
const build = (src) => { const o = {}; for (const [k, v] of Object.entries(src || {})) {
  if (typeof v !== 'string') continue; const s = stemOf(v); if (s) o[k.toLowerCase()] = s; } return o; };
const luaKey = (k) => '["' + String(k).replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"]';
const luaTable = (n, o) => '  ' + n + ' = {\n' + Object.keys(o).sort()
  .map(k => '    ' + luaKey(k) + ' = "' + o[k] + '",\n').join('') + '  },\n';
let out = '-- AUTO-GENERATED from material-icon-theme v' + pkg.version + '. Do not edit by hand.\n'
  + 'return {\n  version = "' + pkg.version + '",\n'
  + '  dir = "' + (stemOf(m.folder) || 'folder') + '",\n'
  + '  dir_open = "' + (stemOf(m.folderExpanded) || 'folder-open') + '",\n'
  + '  file = "' + (stemOf(m.file) || 'file') + '",\n'
  + luaTable('by_ext', build(m.fileExtensions)) + luaTable('by_name', build(m.fileNames))
  + luaTable('by_folder', build(m.folderNames)) + luaTable('by_folder_open', build(m.folderNamesExpanded))
  + '}\n';
fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, out);
console.log('    resolver written');
NODE

echo "==> Done. Point svgtree at it:"
echo '    local mat = require("svgtree.packs.material")'
echo '    require("svgtree").setup({ pack = mat.pack, icon_map = mat })'
