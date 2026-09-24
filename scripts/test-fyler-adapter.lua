-- Headless checks for svgtree.adapters.fyler (overlay placement contract).
-- Run via scripts/test.sh (nvim 0.13+). Forces a known graphics terminal via
-- env (like test-capability) so support resolves true deterministically.
--
-- The engine overlays icon.width cells at the column resolve() returns. Those
-- cells must be the blank slot the adapter's icon provider reserved; anywhere
-- else the overlay paints over the start of the file name.
vim.env.TERM_PROGRAM = nil
vim.env.TERM = 'xterm-ghostty'
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require('svgtree.config').setup({})
local cap = require('svgtree.capability')
local engine = require('svgtree.engine')
local width = require('svgtree.config').options.icon.width

-- Capture the resolver the adapter hands the engine instead of drawing.
local captured
engine.attach = function(opts)
  captured = opts.resolve
  return { reconcile = function() end, detach = function() end }
end

local A = require('svgtree.adapters.fyler')

local fails = 0
local function check(c, m)
  if c then print('  ok  ' .. m) else print('  FAIL ' .. m); fails = fails + 1 end
end

cap.detect()
check(cap.supported_cached() == true, 'precondition: graphics supported in this env')

-- Mirror Fyler's line layout: indent .. icon .. ' ' .. '/<id> ' .. name.
local function fyler_line(depth, icon, id, name)
  local slot = icon and (icon .. ' ') or ''
  return string.rep('  ', depth) .. slot .. '/' .. id .. ' ' .. name
end

local function resolve_all(lines, visible)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_buf(0, buf)
  captured = nil
  A.on_refresh({ win_id = vim.api.nvim_get_current_win(), buf_id = buf }, visible)
  local specs = {}
  for i = 1, #lines do specs[i] = captured and captured(i) or false end -- false = no overlay
  return specs
end

local visible = {
  { path = '/p/sales-copilot-ui', type = 'directory', depth = 0 },
  { path = '/p/sales-copilot-ui/main.lua', type = 'file', depth = 1 },
}

-- Reserved slot (integrations.icon = adapter.icon): overlay the blank cells.
local slot = A.icon()
check(slot and #slot == width, 'provider reserves icon.width blank cells')
local specs = resolve_all({
  fyler_line(0, slot, 2, 'sales-copilot-ui'),
  fyler_line(1, slot, 3, 'main.lua'),
}, visible)
check(specs[1] and specs[1].col == 1, 'depth 0 with slot -> overlay at col 1')
check(specs[2] and specs[2].col == 3, 'depth 1 with slot -> overlay after indent')

-- No slot (adapter registered, Fyler not using adapter.icon): the concealed
-- id puts the name at the overlay column, so drawing would hide "sa".
specs = resolve_all({
  fyler_line(0, nil, 2, 'sales-copilot-ui'),
  fyler_line(1, nil, 3, 'main.lua'),
}, visible)
check(specs[1] == false, 'depth 0 without slot -> no overlay')
check(specs[2] == false, 'depth 1 without slot -> no overlay')

-- A different provider's glyph occupies the slot: leave it alone.
specs = resolve_all({ fyler_line(0, '\u{f07b}', 2, 'sales-copilot-ui') }, { visible[1] })
check(specs[1] == false, 'foreign glyph in slot -> no overlay')

-- icon_or: svgtree's blank slot when it can draw, the fallback otherwise.
local fallback_args
local provider = A.icon_or(function(...) fallback_args = { ... }; return 'G', 'GlyphHl' end)
check(provider('file', '/p/a.lua', {}) == string.rep(' ', width), 'icon_or reserves the slot when graphics work')
check(fallback_args == nil, 'icon_or skips the fallback when svgtree draws')
local real_supported = cap.supported_cached
cap.supported_cached = function() return false end
local glyph, glyph_hl = provider('directory', '/p/src', { open = true })
check(glyph == 'G' and glyph_hl == 'GlyphHl', 'icon_or returns the fallback without graphics')
check(fallback_args and fallback_args[1] == 'directory' and fallback_args[2] == '/p/src'
  and fallback_args[3].open == true, 'icon_or passes Fyler\'s arguments through')
check(A.icon_or()('file', '/p/a.lua', {}) == nil, 'icon_or without a fallback returns nil')
cap.supported_cached = real_supported

if fails > 0 then print(fails .. ' failure(s)'); os.exit(1) end
print('fyler adapter: all checks passed')
