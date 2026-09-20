vim.opt.runtimepath:prepend(vim.fn.getcwd())

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
root = assert(vim.uv.fs_realpath(root))
local file = root .. '/one.lua'
vim.fn.writefile({ 'one' }, file)

local dashboard_win = vim.api.nvim_get_current_win()
local dashboard_buf = vim.api.nvim_get_current_buf()
vim.bo[dashboard_buf].buftype = 'nofile'
vim.bo[dashboard_buf].bufhidden = 'wipe'
vim.bo[dashboard_buf].buflisted = false
vim.bo[dashboard_buf].filetype = 'dashboard'

local picker_buf = vim.api.nvim_create_buf(false, true)
local picker_win = vim.api.nvim_open_win(picker_buf, true, {
  relative = 'editor', width = 20, height = 3, row = 1, col = 1, style = 'minimal',
})

local notifications = {}
local original_notify = vim.notify
vim.notify = function(message) notifications[#notifications + 1] = message end

local calls, handle = {}, {}
package.loaded.sprite = {
  register_tokens = function(_, callback) callback(nil) end,
  on_resume = function() return function() end end,
  open = function(opts, callback) calls.opts = opts; calls.open = callback end,
}
for _, name in ipairs({ 'assets', 'rows', 'state', 'focus', 'focus_editor', 'update' }) do
  handle[name] = function(_, ...) calls[#calls + 1] = { name = name, args = { ... } } end
end
function handle:close() calls.opts.on_close({ kind = 'requested' }) end

local Native = require('svgtree.native')
local ready
Native.open(root, { selected = file, expanded = {}, widths = { native = 280 } }, {
  ready = function(view) ready = view end,
})
calls.open(nil, handle)
local index = 1
while not ready do
  assert(vim.wait(1000, function() return calls[index] ~= nil end), 'native view stalled')
  local callback = calls[index].args[#calls[index].args]
  callback(nil)
  index = index + 1
end

calls.opts.on_event({ type = 'list_click', revision = ready.ack_revision, id = file, count = 1, button = 'left' })
assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(dashboard_win)) == file,
  'selecting a file from a dashboard must open it in the main window')
assert(vim.api.nvim_win_get_buf(picker_win) == picker_buf, 'floating picker must be preserved')
assert(vim.api.nvim_get_current_win() == picker_win, 'single click must keep editor focus unchanged')
calls.opts.on_event({ type = 'list_click', revision = ready.ack_revision, id = file, count = 2, button = 'left' })
assert(vim.api.nvim_get_current_win() == dashboard_win, 'double click must focus the opened file window')
assert(#notifications == 0, 'selection must not report an error: ' .. vim.inspect(notifications))

ready:close()
local special_buf = vim.api.nvim_create_buf(false, true)
vim.bo[special_buf].bufhidden = 'hide'
vim.api.nvim_win_set_buf(dashboard_win, special_buf)
vim.api.nvim_set_current_win(picker_win)
calls = {}
ready = nil
Native.open(root, { selected = file, expanded = {}, widths = { native = 280 } }, {
  ready = function(view) ready = view end,
})
calls.open(nil, handle)
index = 1
while not ready do
  assert(vim.wait(1000, function() return calls[index] ~= nil end), 'native view stalled')
  calls[index].args[#calls[index].args](nil)
  index = index + 1
end

ready.controller:action('open')
local file_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == file then file_win = win end
end
assert(file_win and file_win ~= dashboard_win, 'selection must create an editor window when no existing one is usable')
assert(vim.api.nvim_win_get_buf(dashboard_win) == special_buf, 'special buffer must be preserved')
assert(vim.api.nvim_get_current_win() == file_win, 'Enter must focus the created editor window')
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  assert(not (vim.bo[buf].buflisted and vim.api.nvim_buf_get_name(buf) == ''),
    'creating an editor window must not leave an empty listed buffer')
end
assert(#notifications == 0, 'selection must not report an error: ' .. vim.inspect(notifications))

ready:close()
vim.notify = original_notify
vim.api.nvim_win_close(picker_win, true)
vim.fn.delete(root, 'rf')
print('native editor target ok')
