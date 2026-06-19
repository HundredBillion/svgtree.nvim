-- Launch svgtree against this repo: nvim-nightly --clean -u scripts/demo.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require('svgtree').setup({ show_hidden = true })
vim.schedule(function() require('svgtree').open(vim.fn.getcwd()) end)
