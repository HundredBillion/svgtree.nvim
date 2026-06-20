-- Headless checks for svgtree.raster after the byte-cache removal. Run via scripts/test.sh.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require('svgtree.config').setup({})
local raster = require('svgtree.raster')

local fails = 0
local function check(c, m)
  if c then print('  ok  ' .. m) else print('  FAIL ' .. m); fails = fails + 1 end
end

-- The byte path is gone.
check(raster.png_bytes == nil, 'png_bytes removed')

-- png_path rasterizes a real bundled icon to a readable PNG.
if raster.has_converter() then
  local png = raster.png_path('python')
  check(png ~= nil and vim.fn.filereadable(png) == 1, 'png_path("python") -> readable PNG')
  if png then
    local bytes = vim.fn.readblob(png)
    check(bytes:sub(2, 4) == 'PNG', 'file has PNG magic bytes')
  end
else
  print('  SKIP raster body (no converter)')
end

-- Missing stem -> nil.
check(raster.png_path('this_stem_does_not_exist_xyz') == nil, 'missing stem -> nil')

-- warm() runs without error.
check(pcall(raster.warm), 'warm() runs without error')

if fails > 0 then print('FAILED: ' .. fails); os.exit(1) else print('test-raster: ALL PASS') end
