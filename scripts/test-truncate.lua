-- Headless checks for svgtree.text.truncate (width-aware end-truncation).
-- Run via scripts/test.sh.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local t = require('svgtree.text').truncate

local fails = 0
local function check(c, m)
  if c then print('  ok  ' .. m) else print('  FAIL ' .. m); fails = fails + 1 end
end

-- ---- degenerate budgets ----
check(t('hello', 0) == '', 'budget 0 -> empty')
check(t('hello', -3) == '', 'negative budget -> empty')
check(t('', 5) == '', 'empty string -> empty')

-- ---- no truncation needed ----
check(t('hello', 5) == 'hello', 'exact fit -> unchanged')
check(t('hi', 5) == 'hi', 'shorter than budget -> unchanged')

-- ---- budget 1 is ellipsis-only when it overflows ----
check(t('hello', 1) == '…', 'budget 1 + overflow -> ellipsis only')

-- ---- ascii overflow: head + ellipsis, fits the budget ----
local r = t('hello', 3)
check(r == 'he…', 'ascii overflow -> he…')
check(vim.fn.strdisplaywidth(r) <= 3, 'ascii result fits budget')

-- ---- width-aware: single-width multibyte (é) ----
check(t('café', 4) == 'café', 'multibyte exact fit unchanged')
local r2 = t('café', 3)
check(vim.fn.strdisplaywidth(r2) <= 3, 'multibyte overflow fits budget')
check(r2:sub(-3) == '…', 'multibyte overflow ends with ellipsis')

-- ---- width-aware: double-width (CJK, 2 cells each) ----
check(t('世界', 4) == '世界', 'double-width exact fit unchanged')
local r3 = t('世界', 3)
check(r3 == '世…', 'double-width overflow -> 世…')
check(vim.fn.strdisplaywidth(r3) <= 3, 'double-width result fits budget')

if fails > 0 then print('FAILED: ' .. fails); os.exit(1) else print('test-truncate: ALL PASS') end
