-- Headless smoke test of the non-visual layers.
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local svgtree = require('svgtree')
svgtree.setup({})

local config = require('svgtree.config')
local icons = require('svgtree.icons')
local raster = require('svgtree.raster')
local Tree = require('svgtree.tree')

print('pack: ' .. config.options.pack)
assert(vim.fn.isdirectory(config.options.pack) == 1, 'pack dir missing')

-- Resolver checks.
local cases = {
  { 'main.py', 'file', 'python' },
  { 'app.ts', 'file', 'typescript' },
  { 'Cargo.toml', 'file', 'rust' },
  { '.gitignore', 'file', 'git' },
  { 'README', 'file', 'file' },
  { 'src', 'dir', 'directory' },
}
for _, c in ipairs(cases) do
  local got = icons.stem(c[1], c[2])
  assert(got == c[3], string.format('resolve %s: got %s want %s', c[1], got, c[3]))
end
print('resolver: OK (' .. #cases .. ' cases)')

-- Rasterization (requires rsvg-convert or magick).
if raster.has_converter() then
  local bytes = raster.png_bytes('python')
  assert(bytes and #bytes > 0, 'python.png rasterization failed')
  assert(bytes:sub(2, 4) == 'PNG', 'output is not PNG')
  print('raster: OK (python -> ' .. #bytes .. ' bytes PNG)')
else
  print('raster: SKIP (no ImageMagick)')
end

-- Tree flatten on this repo.
local t = Tree.new(vim.fn.getcwd())
local nodes = t:flatten()
assert(#nodes > 0, 'flatten returned no nodes')
print('tree: OK (' .. #nodes .. ' top-level nodes)')
for i = 1, math.min(5, #nodes) do
  print(string.format('  [%s] %s', nodes[i].kind, nodes[i].name))
end

print('ALL OK')
