-- Headless checks for svgtree.adapters.bufferline (get_element_icon contract).
-- Run via scripts/test.sh (nvim 0.13+). Forces a known graphics terminal via
-- env (like test-capability) so support resolves true deterministically.
vim.env.TERM_PROGRAM = nil
vim.env.TERM = 'xterm-ghostty'
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require('svgtree.config').setup({})
local cap = require('svgtree.capability')
local raster = require('svgtree.raster')
local icon_cfg = require('svgtree.config').options.icon
local A = require('svgtree.adapters.bufferline')

local fails = 0
local function check(c, m)
  if c then print('  ok  ' .. m) else print('  FAIL ' .. m); fails = fails + 1 end
end

A.setup()
check(cap.supported_cached() == true, 'precondition: graphics supported in this env')

-- No image for things that aren't a named file -> nil, so bufferline draws its
-- glyph fallback. (Directory tabs and scratch/no-name buffers.)
check(A.get_element_icon({ path = '/tmp', directory = true }) == nil, 'directory element -> nil')
check(A.get_element_icon({ path = '', directory = false }) == nil, 'nameless buffer -> nil')

-- The image build path needs a rasterizer + pack SVGs; skip those assertions
-- (don't fail the suite) where unavailable, mirroring smoke.lua.
if raster.has_converter() then
  local el = { path = '/proj/main.py', filetype = 'python', directory = false }

  -- A cache MISS returns nil this frame (glyph shows) and schedules an off-loop
  -- build: get_element_icon must never block the tabline on rasterization.
  check(A.get_element_icon(el) == nil, 'first call (cache miss) -> nil, build scheduled')

  vim.wait(3000, function()
    return A.get_element_icon({ path = el.path, filetype = el.filetype, directory = false }) ~= nil
  end)

  -- Once built, the same element yields the placeholder text + an fg-encoded
  -- highlight, and the icon measures exactly icon.width cells.
  local text, hl = A.get_element_icon(el)
  check(text ~= nil, 'after build -> non-nil icon text')
  check(text and vim.fn.strdisplaywidth(text) == icon_cfg.width, 'icon width == config icon.width')
  check(type(hl) == 'string' and hl:match('^SvgtreeImgFg%d+$') ~= nil, 'returns an SvgtreeImgFg<id> highlight')

  -- Cache is stable: the same file resolves to the same highlight group (one
  -- transmit per icon, reused across tabs).
  local _, hl2 = A.get_element_icon(el)
  check(hl2 == hl, 'same file -> same cached highlight group')

  -- A different filetype is a different icon -> a different image id/group.
  vim.wait(3000, function()
    return A.get_element_icon({ path = '/proj/app.ts', filetype = 'typescript', directory = false }) ~= nil
  end)
  local _, hl_ts = A.get_element_icon({ path = '/proj/app.ts', filetype = 'typescript', directory = false })
  check(hl_ts ~= nil and hl_ts ~= hl, 'distinct filetype -> distinct highlight group')
else
  print('  skip (no rasterizer): build-path assertions')
end

if fails > 0 then print('FAILED: ' .. fails); os.exit(1) else print('test-bufferline-adapter: ALL PASS') end
