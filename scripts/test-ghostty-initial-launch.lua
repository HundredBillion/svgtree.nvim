vim.opt.runtimepath:prepend(vim.fn.getcwd())

local terminal = arg[1] or 'ghostty'
assert(terminal == 'ghostty' or terminal == 'sprite', 'unsupported terminal fixture')
vim.env.TERM = 'xterm-ghostty'
vim.env.TERM_PROGRAM = terminal

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
root = assert(vim.uv.fs_realpath(root))
local file = root .. '/one.lua'
vim.fn.writefile({ 'one' }, file)
local second_file = root .. '/two.lua'
vim.fn.writefile({ 'two' }, second_file)

local editor = vim.api.nvim_get_current_win()
local dashboard = vim.api.nvim_get_current_buf()
vim.bo[dashboard].buftype = 'nofile'
vim.bo[dashboard].bufhidden = 'wipe'
vim.bo[dashboard].buflisted = false

local kitty = require('svgtree.kitty')
local original_transmit, original_place, original_delete = kitty.transmit, kitty.place, kitty.delete
local transmitted = {}
kitty.transmit = function(png)
  transmitted[#transmitted + 1] = png
  return 1000 + #transmitted
end
kitty.place = function() return 1 end
kitty.delete = function() end

local tree = require('svgtree')
tree.setup({ renderer = 'terminal' })
local capability = require('svgtree.capability')
vim.api.nvim_exec_autocmds('UIEnter', {})
assert(capability.supported_cached(), terminal .. ' must enable terminal image rendering')
tree.open(root)
local sidebar = vim.api.nvim_get_current_win()
local sidebar_buf = vim.api.nvim_get_current_buf()
assert(sidebar ~= editor, 'terminal tree must open beside the dashboard')
assert(vim.wait(1000, function() return #transmitted > 0 end), 'tree must transmit a rasterized icon')
assert(vim.fn.readblob(transmitted[1]):sub(2, 4) == 'PNG', 'tree must send a PNG made from its SVG pack')
assert(not vim.api.nvim_buf_get_lines(sidebar_buf, 0, 1, false)[1]:find('%['),
  terminal .. ' tree must show image slots instead of fallback text tags')
local ns = vim.api.nvim_get_namespaces().svgtree_view_engine
assert(ns and #vim.api.nvim_buf_get_extmarks(sidebar_buf, ns, 0, -1, {}) > 0,
  terminal .. ' tree must anchor the icon to its buffer line')

local function assert_icon_rows(event)
  local function anchored()
    local marks = vim.api.nvim_buf_get_extmarks(sidebar_buf, ns, 0, -1, {})
    return #marks == 2 and marks[1][2] == 0 and marks[2][2] == 1
  end
  assert(vim.wait(1000, anchored), event .. ': icons must remain on their file rows')
end
assert_icon_rows('initial tree')
local uploads = #transmitted

vim.keymap.set('n', '<C-h>', '<C-w>h')
vim.keymap.set('n', '<C-l>', '<C-w>l')
local function key(lhs)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), 'x', false)
end
key('<C-l>')
assert(vim.api.nvim_get_current_win() == editor, 'Ctrl-L must move from terminal tree to editor')
key('<C-h>')
assert(vim.api.nvim_get_current_win() == sidebar, 'Ctrl-H must return from editor to terminal tree')
key('<CR>')
assert(vim.api.nvim_get_current_win() == editor, 'initial file selection must focus the editor')
assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)) == file,
  'initial file selection must replace the dashboard with the chosen file')
vim.api.nvim_exec_autocmds('WinResized', {})
assert_icon_rows('resize after first file selection')
vim.cmd('edit ' .. vim.fn.fnameescape(second_file))
vim.o.showtabline = 2
vim.api.nvim_exec_autocmds('WinResized', {})
assert_icon_rows('tabline after second file')
vim.api.nvim_win_set_width(sidebar, vim.api.nvim_win_get_width(sidebar) - 1)
vim.api.nvim_exec_autocmds('VimResized', {})
assert_icon_rows('editor resize')
assert(#transmitted == uploads, 'relayout must reuse the uploaded images')
key('<C-h>')
assert(vim.api.nvim_get_current_win() == sidebar, 'Ctrl-H must still enter the tree after opening a file')
key('<C-l>')
assert(vim.api.nvim_get_current_win() == editor, 'Ctrl-L must still reach the opened file')

tree.close()
kitty.transmit, kitty.place, kitty.delete = original_transmit, original_place, original_delete
vim.fn.delete(root, 'rf')
print(terminal .. ' initial launch, icon relayout, file selection, and Ctrl navigation ok')
