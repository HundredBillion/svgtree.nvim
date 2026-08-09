vim.opt.runtimepath:prepend(vim.fn.getcwd())

local svgtree = require('svgtree')
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')

assert(svgtree.root() == nil, 'closed tree must have no root')
svgtree.open(root)
assert(svgtree.root() == root, 'open tree must expose its root')
svgtree.close()
assert(svgtree.root() == nil, 'closed tree must clear its root')

vim.fn.delete(root, 'rf')
print('test-root: ALL PASS')
