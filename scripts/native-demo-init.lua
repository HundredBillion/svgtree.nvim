local tree_checkout = assert(vim.env.SVGTREE_CHECKOUT, 'set SVGTREE_CHECKOUT to the svgtree.nvim checkout')
local api_checkout = assert(vim.env.SVGTREE_API_CHECKOUT, 'set SVGTREE_API_CHECKOUT to the sprite.nvim checkout')
local fixture = assert(vim.env.SVGTREE_FIXTURE, 'set SVGTREE_FIXTURE to the materialized visual project')

for _, path in ipairs({ tree_checkout, api_checkout }) do
  assert(vim.fn.isdirectory(path) == 1, 'checkout does not exist: ' .. path)
  vim.opt.runtimepath:prepend(path)
end
assert(vim.fn.isdirectory(fixture) == 1, 'fixture does not exist: ' .. fixture)

local tree = require('svgtree')
tree.setup({ renderer = 'sprite', native = { width = tonumber(vim.env.SVGTREE_NATIVE_WIDTH) or 290 } })
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.api.nvim_set_current_dir(fixture)
    tree.open(fixture)
  end,
})
