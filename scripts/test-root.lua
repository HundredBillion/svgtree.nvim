vim.opt.runtimepath:prepend(vim.fn.getcwd())

local svgtree = require('svgtree')
local first_root = vim.fn.tempname()
local second_root = vim.fn.tempname()
vim.fn.mkdir(first_root, 'p')
vim.fn.mkdir(second_root, 'p')

assert(svgtree.root() == nil, 'closed tree must have no root')
svgtree.open(first_root)
assert(svgtree.root() == first_root, 'open tree must expose its root')
svgtree.open(second_root)
assert(svgtree.root() == second_root, 'reopened tree must expose its new root')
svgtree.close()
assert(svgtree.root() == nil, 'closed tree must clear its root')

vim.fn.delete(first_root, 'rf')
vim.fn.delete(second_root, 'rf')
print('test-root: ALL PASS')
