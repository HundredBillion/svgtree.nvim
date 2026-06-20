#!/usr/bin/env bash
# Install a VSCode file-icon theme as an svgtree pack by fetching its .vsix from
# Open VSX and unpacking it. No node/npm/nvim required.
#
# Usage: scripts/install-theme.sh <publisher>.<name> [pack-name]
#   scripts/install-theme.sh PKief.material-icon-theme material
#   scripts/install-theme.sh vscode-icons-team.vscode-icons vscode-icons
set -euo pipefail

ID="${1:-}"
PACKNAME="${2:-}"
if [ -z "$ID" ] || [[ ! "$ID" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9._-]+$ ]]; then
  echo "usage: $0 <publisher>.<name> [pack-name]" >&2
  echo "  <publisher>.<name> must be alphanumeric/dot/hyphen (e.g. PKief.material-icon-theme)" >&2
  exit 2
fi
PUB="${ID%%.*}"
NAME="${ID#*.}"
PACKNAME="${PACKNAME:-$NAME}"

for bin in curl unzip; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' not found on PATH" >&2; exit 2; }
done

DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
DEST="$DATA/svgtree/packs/$PACKNAME"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Resolving $PUB.$NAME on Open VSX…"
META="$(curl -fsSL "https://open-vsx.org/api/$PUB/$NAME/latest")"
VSIX_URL="$(printf '%s' "$META" | grep -o '"download"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"(https[^"]*)".*/\1/')"
if [ -z "$VSIX_URL" ]; then
  echo "error: no .vsix download URL for $PUB.$NAME on Open VSX" >&2
  exit 1
fi
# Guard against the broad grep picking up a non-.vsix "download" field if the
# Open VSX response shape changes (else we'd fetch the wrong file and fail later
# with a confusing "no extension/ directory" error).
if [[ "$VSIX_URL" != *.vsix ]]; then
  echo "error: resolved download URL does not look like a .vsix: $VSIX_URL" >&2
  exit 1
fi

echo "==> Downloading $VSIX_URL"
curl -fsSL -o "$TMP/ext.vsix" "$VSIX_URL"

echo "==> Unzipping…"
unzip -q "$TMP/ext.vsix" -d "$TMP/x"
if [ ! -d "$TMP/x/extension" ]; then
  echo "error: .vsix has no extension/ directory" >&2
  exit 1
fi

echo "==> Installing -> $DEST"
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
mv "$TMP/x/extension" "$DEST"

echo "==> Done. Select it:"
echo "    require('svgtree').setup({ pack = '$PACKNAME' })"
