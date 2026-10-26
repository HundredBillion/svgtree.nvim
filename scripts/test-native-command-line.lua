vim.opt.runtimepath:prepend(vim.fn.getcwd())
local sprite_root = vim.fn.fnamemodify(vim.env.SVGTREE_API_CHECKOUT or '../sprite.nvim', ':p')
package.path = sprite_root .. '/lua/?.lua;' .. package.path
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local received, focused = {}, false
local event_handler
local function done(callback)
  if callback then vim.schedule(function() callback(nil) end) end
end
package.loaded.sprite = {
  available = function(callback)
    vim.schedule(function() callback(nil, {features={'owned-dock-v1','virtual-list-v1','svg-assets-v1','dock-resize-v1'}}) end)
    return function() end
  end,
  register_tokens = function(_, callback) done(callback) end,
  on_resume = function() return function() end end,
  open = function(opts, callback)
    event_handler = opts.on_event
    local handle = {}
    for _, method in ipairs({'assets','rows','state','update','focus'}) do
      handle[method] = function(_, ...) done(select(select('#', ...), ...)) end
    end
    function handle:focus_editor(callback) focused = true; done(callback) end
    function handle:close() opts.on_close({kind='requested'}) end
    vim.schedule(function() callback(nil, handle) end)
    return function() end
  end,
}
local original_input = vim.api.nvim_input
vim.api.nvim_input = function(text) received[#received+1] = text end
local tree = require('svgtree')
tree.setup({renderer='sprite'})
tree.open(root)
assert(vim.wait(3000, function() return event_handler ~= nil end), 'native dock opens')
vim.wait(100, function() return false end)
event_handler({type='input', key=':', text=':'})
event_handler({type='input', key='q', text='q'})
event_handler({type='input', key='a', text='a'})
event_handler({type='input', key='enter', text='\n'})
assert(vim.wait(1000, function() return focused end), 'colon focuses the editor')
assert(vim.wait(1000, function() return received[1] == ':qa<CR>' end),
  'command keys reach Neovim after the focus handoff')
tree.close()
vim.api.nvim_input = original_input
vim.fn.delete(root, 'rf')
print('Native command line passed')
