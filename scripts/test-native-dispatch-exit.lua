vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path=(vim.env.SVGTREE_API_CHECKOUT or '../native-explorer-api')..'/lua/?.lua;'..package.path
local root=vim.fn.tempname();vim.fn.mkdir(root,'p');vim.fn.writefile({'x'},root..'/a.lua')
local features={['owned-dock-v1']=true,['virtual-list-v1']=true,['svg-assets-v1']=true,['dock-resize-v1']=true}
local last,opens=nil,0
local sprite={available=function(cb) cb(nil,{features=features});return function() end end,
  register_tokens=function(_,cb) cb(nil) end,
  on_resume=function() return function() end end}
local handle={}
for _,method in ipairs({'assets','rows','state','focus','update','focus_editor'}) do
  handle[method]=function(_,...) local args={...};args[#args](nil) end
end
function handle:close() if last then last.on_close({kind='requested'}) end end
function sprite.open(opts,cb) last=opts;opens=opens+1;cb(nil,handle) end
package.loaded.sprite=sprite
local tree=require('svgtree')
tree.setup({renderer='auto'})
tree.open(root)
assert(vim.wait(1000,function() return last and tree.root()==root and opens==1 end),'native opens')
last.on_close({kind='exit'})
assert(tree.root()==nil,'exit clears public root')
tree.toggle(root)
assert(opens==2,'toggle after exit opens a new view')
last.on_close({kind='suspend'})
assert(tree.root()==root,'suspend preserves wanted root for resume')
tree.close()
vim.fn.delete(root,'rf')
print('native dispatch exit ok')
