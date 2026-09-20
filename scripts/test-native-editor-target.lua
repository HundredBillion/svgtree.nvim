vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.env.SVGTREE_API_CHECKOUT or (vim.fn.getcwd() .. '/../native-explorer-api')
package.path = api .. '/lua/?.lua;' .. api .. '/lua/?/init.lua;' .. package.path

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
  available = function(callback)
    callback(nil, { features = {
      ['owned-dock-v1'] = true, ['virtual-list-v1'] = true,
      ['svg-assets-v1'] = true, ['dock-resize-v1'] = true,
    } })
    return function() end
  end,
  register_tokens = function(_, callback) callback(nil) end,
  on_resume = function() return function() end end,
  open = function(opts, callback) calls.opts = opts; calls.open = callback end,
}
for _, name in ipairs({ 'assets', 'rows', 'state', 'focus', 'focus_editor', 'update' }) do
  handle[name] = function(_, ...) calls[#calls + 1] = { name = name, args = { ... } } end
end
function handle:close() calls.opts.on_close({ kind = 'requested' }) end

local ready
local Native = require('svgtree.native')
package.loaded['svgtree.native'] = { open = function(path, saved, callbacks)
  local on_ready = callbacks.ready
  callbacks.ready = function(view) ready = view; on_ready(view) end
  return Native.open(path, saved, callbacks)
end }
local tree = require('svgtree')
tree.setup({ renderer = 'sprite' })
tree.open(root)
calls.open(nil, handle)
local index = 1
while not ready do
  assert(vim.wait(1000, function() return calls[index] ~= nil end), 'native view stalled')
  local callback = calls[index].args[#calls[index].args]
  callback(nil)
  index = index + 1
end

local function count(name)
  local n = 0
  for _, call in ipairs(calls) do if call.name == name then n = n + 1 end end
  return n
end
local initial_focus = count('focus')
calls.opts.on_event({ type = 'input', key = 'ctrl-l' })
assert(count('focus_editor') == 1, 'Ctrl-L must leave the initial left Sprite tree for the editor')
calls.opts.on_event({ type = 'blur' })
vim.keymap.set('n', '<C-h>', function()
  if not tree.focus('left') then vim.cmd.wincmd('h') end
end)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-h>', true, false, true), 'x', false)
assert(count('focus') == initial_focus + 1, 'Ctrl-H must re-enter the initial Sprite tree')
calls.opts.on_event({ type = 'focus' })

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
tree.open(root)
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
