#!/usr/bin/env bash
set -u
NVIM="${SVGTREE_NVIM:-nvim}"
if ! command -v "$NVIM" >/dev/null 2>&1; then echo "error: '$NVIM' not found" >&2; exit 2; fi
cd "$(dirname "$0")/.." || exit 2
API="${SVGTREE_API_CHECKOUT:-../native-explorer-api}"
if [ ! -f "$API/lua/sprite/input.lua" ]; then
  echo "error: Sprite input test fixture is required at $API" >&2
  exit 2
fi
export SVGTREE_API_CHECKOUT="$API"
scripts=(scripts/test-pack.lua scripts/test-tree.lua scripts/test-root.lua scripts/test-terminal-session.lua scripts/test-native-model.lua scripts/test-native-keys.lua scripts/test-native-navigation.lua scripts/test-native-watch.lua scripts/test-native-view.lua scripts/test-native-controller.lua scripts/test-native-dispatch.lua scripts/test-native-dispatch-exit.lua scripts/test-neotree-detection.lua)
fail=0
for s in "${scripts[@]}"; do
  echo "=== $s ==="
  if "$NVIM" --headless -l "$s"; then echo "PASS: $s"; else echo "FAIL: $s"; fail=1; fi
done
if [ "$fail" -ne 0 ]; then echo 'CORE SUITE FAILED'; exit 1; fi
echo 'CORE SUITE PASSED'
