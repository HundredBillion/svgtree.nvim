vim.opt.rtp:prepend(vim.fn.getcwd())
local View = require('svgtree.native_view')
local Native = require('svgtree.native')
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
vim.fn.writefile({'hello'}, root .. '/a.lua')
local callbacks, handle = {}, {}
local sprite = {register_tokens=function(_, cb) cb(nil) end, on_resume=function() return function() end end}
function sprite.open(opts, cb)
  callbacks.opts=opts; callbacks.open=cb
  return function() callbacks.cancelled=true end
end
for _, method in ipairs({'assets','rows','state','focus','focus_editor','update'}) do
  handle[method]=function(_, ...) callbacks[method]={...} end
end
function handle:close() callbacks.closed=true; callbacks.opts.on_close({kind='requested'}) end
package.loaded.sprite=sprite
local ready, failed, closed = 0,0,0
local cancel=Native.open(root,nil,{ready=function(v) ready=ready+1; callbacks.view=v end,failed=function() failed=failed+1 end,closed=function() closed=closed+1 end})
assert(type(cancel)=='function')
callbacks.open(nil,handle)
assert(vim.wait(1000,function() return callbacks.assets~=nil end))
assert(ready==0 and callbacks.assets)
callbacks.assets[#callbacks.assets](nil)
assert(callbacks.rows and ready==0)
callbacks.rows[#callbacks.rows](nil)
assert(callbacks.state and ready==0)
callbacks.state[#callbacks.state](nil)
assert(callbacks.focus and ready==0)
callbacks.focus[#callbacks.focus](nil)
assert(ready==1 and failed==0)
assert(callbacks.view:root()==vim.fs.normalize(root))
callbacks.view:close()
assert(closed==1 and callbacks.closed)
local d=View.description(nil,root)
assert(d.root.kind=='virtual_list' and d.root.row_height==22 and d.root.heading.height==35)
assert(d.root.section.icon=='svgtree-chevron-down' and d.root.section.left_padding+d.root.icon_size+d.root.section.icon_gap==20)
for _,key in ipairs({'background','foreground','hover','selected','inactive_selected','selected_foreground','focus','guide','border','scrollbar'}) do assert(d.root.colors[key],key) end
print('native view: ok')
local fake={}
function fake.open(opts, cb) fake.opts=opts;fake.open_cb=cb;return function() fake.cancelled=true end end
function fake.register_tokens(_,cb) cb(nil) end
function fake.on_resume(cb) fake.resume=cb;return function() fake.unsubscribed=true end end
package.loaded.sprite=fake
local cancelled_ready=0
local stop=Native.open(root,nil,{ready=function() cancelled_ready=cancelled_ready+1 end})
stop()
fake.open_cb(nil,handle)
assert(cancelled_ready==0)
local model={{id=root..'/a.lua',path=root..'/a.lua',text='a.lua',depth=0,kind='file'}}
local pack=require('svgtree.icons').resolve_pack('native')
local rows,ids=View.rows(model,pack)
assert(#rows==1 and rows[1].indent==0 and rows[1].leading=='svgtree-transparent')
local assets=View.assets(pack,ids)
assert(assets['svgtree-transparent'])
local many={}
for i=1,10000 do many[i]={id=root..'/entry-'..i..'.lua',path=root..'/entry-'..i..'.lua',text='entry-'..i..'.lua',depth=0,kind='file'} end
local large=View.rows(many,pack)
assert(#vim.json.encode({type='list_rows',revision=1,rows=large})<16*1024*1024)
local customdir=vim.fn.tempname();vim.fn.mkdir(customdir,'p')
vim.fn.writefile({'<?xml version="1.0"?>','<!-- icon -->','<svg xmlns="http://www.w3.org/2000/svg"></svg>'},customdir..'/good.svg')
vim.fn.writefile({'not svg'},customdir..'/bad.svg')
vim.fn.writefile({'<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"/>'},customdir..'/self.svg')
local custom={theme={iconDefinitions={good={iconPath='good.svg'},bad={iconPath='bad.svg'},missing={iconPath='missing.svg'},self={iconPath='self.svg'}}},dir=customdir}
local icons=View.assets(custom,{good=true,bad=true,missing=true,self=true})
assert(icons.good and icons.good:match('^<svg') and icons.self and not icons.bad and not icons.missing)
print('native view assets and cancel: ok')
