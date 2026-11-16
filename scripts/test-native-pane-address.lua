vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.fn.fnamemodify(assert(vim.env.SVGTREE_API_CHECKOUT, 'set SVGTREE_API_CHECKOUT'), ':p')
vim.opt.runtimepath:prepend(api)
local host = dofile(api .. '/tests/dock_host.lua').start()
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
vim.fn.writefile({'return true'}, root .. '/example.lua')
local tree = require('svgtree')
tree.setup({window={side='right'}})
local function terminal()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'svgtree' then return true end
  end
  return false
end
local function open()
  local count = #host:messages('list_rows')
  tree.open(root)
  assert(vim.wait(3000, function() return #host:messages('list_rows') > count end),
    'native tree sends rows through real Sprite API')
  assert(not terminal(), 'native tree does not fall back to a terminal buffer')
end
open()
local request = host:messages('open')[1]
assert(request.pane == host.pane and request.side == 'right', 'full pane address opens right dock')
local assets = {}
for _, message in ipairs(host:messages('assets')) do
  for id, svg in pairs(message.entries) do assets[id] = svg end
end
local found = false
for _, row in ipairs(host:messages('list_rows')[1].rows) do
  if row.text == 'example.lua' then
    assert(row.icon and assets[row.icon]:match('<svg'), 'file row has a transmitted SVG icon')
    found = true
  end
end
assert(found, 'fixture file is present')
assert(vim.wait(3000, function() return tree.focus('right') end), 'right dock accepts focus')
assert(vim.wait(3000, function() return #host:messages('focus') > 0 end), 'focus reaches host')
tree.close()
open()
tree.close()
host.refuse = true
tree.open(root)
assert(vim.wait(3000, terminal), 'refused native tree falls back to terminal')
tree.close()
host.refuse = false
open()
tree.close()
host:close()
vim.fn.delete(root, 'rf')
print('Native pane address and SVG delivery passed')
