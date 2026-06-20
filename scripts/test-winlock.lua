-- Headless checks for svgtree.winlock. Run via scripts/test.sh.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local winlock = require('svgtree.winlock')

local fails = 0
local function check(c, m)
  if c then print('  ok  ' .. m) else print('  FAIL ' .. m); fails = fails + 1 end
end

-- A buffer + window with a line wider than the window and wrap off, so leftcol
-- can actually be set non-zero (otherwise there is nothing to snap back).
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { string.rep('x', 400), 'short' })
vim.api.nvim_win_set_buf(0, buf)
local win = vim.api.nvim_get_current_win()
vim.wo[win].wrap = false

winlock.lock_horizontal(win, buf)

-- 1. The 8 horizontal-scroll keys are mapped buffer-locally (to <Nop>).
local keys = {
  'zh', 'zl', 'zH', 'zL',
  '<ScrollWheelLeft>', '<ScrollWheelRight>',
  '<S-ScrollWheelLeft>', '<S-ScrollWheelRight>',
}
for _, lhs in ipairs(keys) do
  local m = vim.fn.maparg(lhs, 'n', false, true)
  check(m and next(m) ~= nil and m.buffer == 1, 'buffer-local mapping for ' .. lhs)
end

-- 2. WinScrolled snaps leftcol back to 0.
vim.api.nvim_win_call(win, function() vim.fn.winrestview({ leftcol = 20 }) end)
vim.api.nvim_exec_autocmds('WinScrolled', { buffer = buf })
local leftcol = vim.api.nvim_win_call(win, function() return vim.fn.winsaveview().leftcol end)
check(leftcol == 0, 'leftcol snapped to 0 (got ' .. tostring(leftcol) .. ')')

if fails > 0 then print('FAILED: ' .. fails); os.exit(1) else print('test-winlock: ALL PASS') end
