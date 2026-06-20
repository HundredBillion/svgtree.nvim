-- Headless checks for svgtree.capability. Run via scripts/test.sh (nvim 0.13+).
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require('svgtree.config').setup({})
local cap = require('svgtree.capability')

local fails = 0
local function check(c, m)
  if c then print('  ok  ' .. m) else print('  FAIL ' .. m); fails = fails + 1 end
end

-- parse_apc_reply (pure) — the core, terminal-free assertions.
local QID = 42
check(cap.parse_apc_reply('\027_Gi=42;OK\027\\', QID) == true, 'positive reply, matching id -> true')
check(cap.parse_apc_reply('\027_Ga=q,i=42;OK\027\\', QID) == true, 'positive reply w/ extra keys -> true')
check(cap.parse_apc_reply('\027_Gi=99;OK\027\\', QID) == false, 'mismatched id -> false')
check(cap.parse_apc_reply('garbage', QID) == false, 'garbage -> false')
check(cap.parse_apc_reply('\027_Gi=42\027\\', QID) == false, 'no status field -> false')

-- capable() / terminal_supported() (assumes a converter is installed).
check(cap.capable() == true, 'capable() true (vim.ui.img + converter present)')
check(type(cap.terminal_supported({ timeout = 50 })) == 'boolean', 'terminal_supported() returns a boolean, no error')

-- detect() fast path via env. Deterministic: clear TERM_PROGRAM, force TERM.
check(cap.probed() == false, 'probed() false before detect')
vim.env.TERM_PROGRAM = nil
vim.env.TERM = 'xterm-ghostty'
cap.detect()
check(cap.probed() == true, 'probed() true after detect (known terminal)')
check(cap.supported_cached() == true, 'supported_cached() true for ghostty + converter')

if fails > 0 then print('FAILED: ' .. fails); os.exit(1) else print('test-capability: ALL PASS') end
