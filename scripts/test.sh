#!/usr/bin/env bash
# Headless smoke suite for svgtree's non-visual layers. Needs Neovim 0.13+
# (vim.ui.img). Override the binary with SVGTREE_NVIM.
#   bash scripts/test.sh
set -u

NVIM="${SVGTREE_NVIM:-nvim-nightly}"
if ! command -v "$NVIM" >/dev/null 2>&1; then
  echo "error: '$NVIM' not found. Set SVGTREE_NVIM to your Neovim 0.13+ binary." >&2
  exit 2
fi

# Needs Neovim 0.13+ (vim.ui.img). Bail clearly otherwise.
if ! "$NVIM" --headless --clean \
     -c 'lua if not (vim.ui and vim.ui.img) then vim.cmd("cq") end' \
     -c 'qa!' >/dev/null 2>&1; then
  echo "error: '$NVIM' lacks vim.ui.img — needs Neovim 0.13+. Set SVGTREE_NVIM." >&2
  exit 2
fi

cd "$(dirname "$0")/.." || exit 2

SVGTREE_NVIM="$NVIM" bash scripts/test-core.sh || exit 1
scripts=(scripts/test-capability.lua scripts/test-winlock.lua scripts/test-raster.lua scripts/test-ghostty-initial-launch.lua scripts/test-truncate.lua scripts/test-kitty.lua scripts/test-bufferline-adapter.lua)
fail=0
for s in "${scripts[@]}"; do
  [ -f "$s" ] || continue        # a script is added by the Task that introduces it
  echo "=== $s ==="
  if "$NVIM" --clean -l "$s"; then
    echo "PASS: $s"
  else
    echo "FAIL: $s"
    fail=1
  fi
  echo
done

echo '=== Sprite terminal icon relayout ==='
if "$NVIM" --clean -l scripts/test-ghostty-initial-launch.lua sprite; then
  echo 'PASS: Sprite terminal icon relayout'
else
  echo 'FAIL: Sprite terminal icon relayout'
  fail=1
fi

if [ "$fail" -ne 0 ]; then echo "SUITE FAILED"; exit 1; fi
echo "SUITE PASSED"
