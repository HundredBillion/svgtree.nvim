if vim.g.loaded_svgtree then
  return
end
vim.g.loaded_svgtree = true

vim.api.nvim_create_user_command('SvgTree', function(opts)
  require('svgtree').open(opts.args ~= '' and opts.args or nil)
end, { nargs = '?', complete = 'dir', desc = 'Open svgtree file explorer' })

vim.api.nvim_create_user_command('SvgTreeToggle', function(opts)
  require('svgtree').toggle(opts.args ~= '' and opts.args or nil)
end, { nargs = '?', complete = 'dir', desc = 'Toggle svgtree file explorer' })
