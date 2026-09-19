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
assert(d.root.border_side=='right')
assert(View.description(nil,root,false,'left').root.border_side=='right')
assert(View.description(nil,root,false,'right').root.border_side=='left')
local border_token
for _,token in ipairs(View.tokens()) do if token.name=='svgtree.border' then border_token=token.default end end
assert(border_token=='#2b2b2b')
assert(d.root.section.icon=='svgtree-chevron-down' and d.root.section.left_padding+d.root.icon_size+d.root.section.icon_gap==20)
assert(d.root.colors.inactive_guide==d.root.colors.guide and d.root.inactive_guide_opacity==0.4,
  'inactive guide uses the reference RGB and alpha over every row background')
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
local nested=View.rows({
  {id='folder',path=root..'/folder',text='folder',depth=0,kind='dir',expanded=true},
  {id='child',path=root..'/folder/child',text='child',depth=1,kind='dir',expanded=true},
  {id='file',path=root..'/folder/child/a.lua',text='a.lua',depth=2,kind='file'},
},pack)
assert(nested[3].guides[1].id=='folder' and nested[3].guides[2].id=='child')
local context_pack={theme={folder='folder',folderExpanded='folder-open',file='file',
  folderNames={workflows='generic-workflows',['.github/workflows']='github-workflows'},
  folderNamesExpanded={['.github/workflows']='github-workflows-open'},
  fileNames={['.config/graphqlrc']='graphql-config'}},dir=''}
local context_rows=View.rows({
  {id='a',path=root..'/.github/workflows',depth=0,kind='dir',expanded=false,text='workflows'},
  {id='b',path=root..'/.github/workflows',depth=0,kind='dir',expanded=true,text='workflows'},
  {id='c',path=root..'/unrelated/workflows',depth=0,kind='dir',expanded=false,text='workflows'},
  {id='d',path=root..'/.config/graphqlrc',depth=0,kind='file',text='graphqlrc'},
},context_pack)
assert(context_rows[1].icon=='github-workflows' and context_rows[2].icon=='github-workflows-open')
assert(context_rows[3].icon=='generic-workflows' and context_rows[4].icon=='graphql-config')
assert(vim.deep_equal(View.active_guides(nested,'file'),{'folder','child'}))
assert(vim.deep_equal(View.active_guides(nested,'folder'),{'folder'}))
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
local read_count=0
local original_readfile=vim.fn.readfile
vim.fn.readfile=function(path,...)
  if path==customdir..'/good.svg' or path==customdir..'/missing.svg' then read_count=read_count+1 end
  return original_readfile(path,...)
end
View.clear_cache()
View.assets(custom,{good=true,missing=true})
View.assets(custom,{good=true,missing=true})
assert(read_count==1,'SVG and missing icon results are cached across handles')
local second_dir=vim.fn.tempname();vim.fn.mkdir(second_dir,'p')
vim.fn.writefile({'<svg xmlns="http://www.w3.org/2000/svg"/>'},second_dir..'/good.svg')
assert(View.assets({theme=custom.theme,dir=second_dir},{good=true}).good,'pack change uses new SVG')
vim.fn.readfile=original_readfile
local chevrons=View.assets(custom,{['svgtree-chevron-down']=true,['svgtree-chevron-right']=true})
assert(chevrons['svgtree-chevron-down']:match('fill="#cccccc"') and chevrons['svgtree-chevron-down']:match('translate%(3 0%)'))
assert(chevrons['svgtree-chevron-right']:match('fill="#cccccc"') and chevrons['svgtree-chevron-right']:match('translate%(2 0%)'))
print('native view cache and disclosure: ok')
