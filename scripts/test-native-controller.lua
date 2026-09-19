vim.opt.rtp:prepend(vim.fn.getcwd())
package.path=(vim.env.SVGTREE_API_CHECKOUT or '../native-explorer-api')..'/lua/?.lua;'..package.path
local Native=require('svgtree.native')
local root=vim.fn.tempname();vim.fn.mkdir(root,'p');vim.fn.writefile({'one'},root..'/one.lua');vim.fn.writefile({'two'},root..'/two.lua')
local calls, handle={},{}
local sprite={register_tokens=function(_,cb) cb(nil) end,on_resume=function(cb) calls.resume=cb;return function() calls.unsub=true end end}
function sprite.open(opts,cb) calls.opts=opts;calls.open=cb;return function() end end
for _,name in ipairs({'assets','rows','state','focus','focus_editor','update'}) do
  handle[name]=function(_,...) calls[#calls+1]={name=name,args={...}} end
end
function handle:close() calls.closed=(calls.closed or 0)+1;calls.opts.on_close({kind='requested'}) end
package.loaded.sprite=sprite
local ready,failed,closed=0,0,0
local stop=Native.open(root,nil,{ready=function(v) ready=ready+1;calls.view=v end,failed=function() failed=failed+1 end,closed=function() closed=closed+1 end})
calls.open(nil,handle)
local i=1
assert(vim.wait(1000,function() return #calls>0 end))
while ready==0 do
  local c=calls[i];assert(c,'missing mutation '..i)
  assert(c.name=='assets' or c.name=='rows' or c.name=='state' or c.name=='focus')
  c.args[#c.args](nil);i=i+1
  assert(i<10)
end
local revision=calls.view.ack_revision
assert(revision>0)
calls.opts.on_event({type='list_scroll',revision=revision-1,top=root..'/one.lua',offset=3,visible_rows=10})
assert(calls.view:snapshot().scroll.id~=root..'/one.lua')
calls.opts.on_event({type='list_scroll',revision=revision,top=root..'/one.lua',offset=3,visible_rows=10})
assert(calls.view:snapshot().scroll.id==root..'/one.lua')
calls.opts.on_event({type='dock_size',width=350})
assert(calls.view:snapshot().widths.native==350)
calls.opts.on_event({type='list_click',revision=revision-1,id=root..'/one.lua',count=1,button='left'})
assert(#calls==i-1)
calls.opts.on_event({type='list_click',revision=revision,id=root..'/one.lua',count=1,button='left'})
assert(vim.wait(1000,function() return #calls>=i end))
assert(calls[i].name=='state')
assert(vim.api.nvim_buf_get_name(0)==root..'/one.lua')
assert(not calls[i+1])
calls[i].args[#calls[i].args](nil)
assert(calls.view:snapshot().scroll.id==root..'/one.lua' and calls.view:snapshot().widths.native==350)
local function ack_last() for _,value in pairs(calls[#calls].args) do if type(value)=='function' then value(nil);return end end error('no ack') end
local before=calls.view:snapshot().selected
calls.opts.on_event({type='list_action',revision=revision,action='root-toggle'})
assert(calls[#calls].name=='update')
ack_last()
assert(calls[#calls].name=='rows')
ack_last()
assert(calls[#calls].name=='state')
ack_last()
local collapsed_rev=calls.view.ack_revision
calls.opts.on_event({type='list_action',revision=collapsed_rev,action='root-toggle'})
assert(calls[#calls].name=='update')
ack_last()
assert(calls[#calls].name=='rows')
vim.cmd('enew')
calls.opts.on_event({type='input',key='enter',text='\n'})
calls.opts.on_event({type='input',key='j',text='j'})
assert(calls.view:snapshot().selected==before)
ack_last()
assert(calls[#calls].name=='state')
ack_last()
assert(vim.wait(1000,function() return calls.view:snapshot().selected==root..'/two.lua' end))
assert(vim.api.nvim_buf_get_name(0)=='', 'applied acknowledgement did not open a file')
stop()
assert(closed==1 and failed==0 and calls.closed==1)
print('native view events: ok')
local function new_handle()
  local h={}
  for _,name in ipairs({'assets','rows','state','focus','focus_editor','update'}) do
    h[name]=function(_,...) calls[#calls+1]={name=name,args={...}} end
  end
  function h:close() calls.closed=(calls.closed or 0)+1;calls.opts.on_close({kind='requested'}) end
  return h
end
calls={}
require('svgtree.config').options.native={width=290,side='right',compact_folders=false}
local err_count=0
local configroot=vim.fn.tempname();vim.fn.mkdir(configroot,'p')
Native.open(configroot,nil,{ready=function() error('unexpected ready') end,failed=function() err_count=err_count+1 end})
assert(calls.opts.side=='right' and calls.opts.width==290)
calls.open(nil,new_handle())
assert(vim.wait(1000,function() return #calls>0 end))
calls[1].args[#calls[1].args]({code='refused',message='bad asset'})
assert(err_count==1 and calls.closed==1)
calls.opts.on_close({kind='failure',error={code='unavailable'}})
assert(err_count==1)
calls={}
local resumed=0
Native.open(root,nil,{ready=function() resumed=resumed+1 end})
calls.open(nil,new_handle())
assert(vim.wait(1000,function() return #calls>0 end))
calls.opts.on_close({kind='suspend'})
assert(resumed==0 and calls.resume)
calls.resume()
assert(calls.open)
calls.open(nil,new_handle())
local n=1
assert(vim.wait(1000,function() return #calls>n end))
while resumed==0 do
  local c=calls[n+1];assert(c and n<12)
  c.args[#c.args](nil);n=n+1
end
assert(resumed==1)
print('native view failure and resume: ok')
local savedroot=vim.fn.tempname();vim.fn.mkdir(savedroot,'p')
require('svgtree.state').save(savedroot,{widths={native=280}})
local cancel_saved=Native.open(savedroot,nil,{})
assert(calls.opts.width==280,'explicitly saved width must win over configured width')
cancel_saved()
local function pending(name,start)
  for at=start or 1,#calls do if calls[at].name==name then return calls[at],at end end
end
local function complete(call,err)
  for _,value in pairs(call.args) do if type(value)=='function' then value(err);return end end
  error('missing callback')
end
local function finish_open(holder)
  local at=1
  assert(vim.wait(1000,function() return #calls>0 end))
  while not holder.view do
    local call=calls[at];assert(call and at<15,'opening stalled')
    complete(call,nil);at=at+1
  end
end
local collapsed={root=root,expanded={},selected=root..'/one.lua',scroll={id=root..'/one.lua',offset=3},widths={native=280},root_collapsed=true}
calls={}
local collapsed_holder={}
Native.open(root,collapsed,{ready=function(v) collapsed_holder.view=v end,failed=function(e) error('collapsed open refused: '..vim.inspect(e)) end})
assert(calls.opts.description.root.section.icon=='svgtree-chevron-right')
calls.open(nil,new_handle())
finish_open(collapsed_holder)
local rowcall=pending('rows')
assert(#rowcall.args[2]==0)
local statecall=pending('state')
assert(statecall.args[2].scroll==nil and statecall.args[2].selected==vim.NIL)
local assetcall=pending('assets')
assert(assetcall.args[1]['svgtree-chevron-right'])
local saved_view=collapsed_holder.view
local old_group=saved_view.target_group
assert(old_group)
calls.opts.on_close({kind='suspend'})
assert(saved_view.phase=='suspended' and saved_view.target_group==nil)
local resume_collapsed=calls.resume;calls={};resume_collapsed()
assert(calls.opts.description.root.section.icon=='svgtree-chevron-right')
calls.open(nil,new_handle())
collapsed_holder.view=nil
finish_open(collapsed_holder)
assert(collapsed_holder.view:snapshot().scroll.id==root..'/one.lua')
assert(collapsed_holder.view.target_group and collapsed_holder.view.target_group~=old_group)
collapsed_holder.view:close()
print('native collapsed reopen and resume: ok')

calls={}
local late_failed=0
local stale_holder={}
Native.open(root,nil,{ready=function(v) stale_holder.view=v end,failed=function() late_failed=late_failed+1 end})
calls.open(nil,new_handle())
assert(vim.wait(1000,function() return #calls>0 end))
local stale_asset=pending('assets')
local old_opts=calls.opts
old_opts.on_close({kind='suspend'})
complete(stale_asset,{code='closed'})
assert(late_failed==0 and not stale_holder.view)
local resume_late=calls.resume;calls={};resume_late()
local next_opts=calls.opts
calls.open(nil,new_handle())
complete(stale_asset,nil)
old_opts.on_close({kind='failure',error={code='unavailable'}})
assert(late_failed==0 and calls.opts==next_opts)
finish_open(stale_holder)
assert(stale_holder.view and late_failed==0)
stale_holder.view:close()
print('native late callback isolation: ok')
calls={}
local closed_late=0
local cancel_mutation=Native.open(root,nil,{failed=function() closed_late=closed_late+1 end})
calls.open(nil,new_handle())
assert(vim.wait(1000,function() return #calls>0 end))
local late_closed_asset=pending('assets')
cancel_mutation()
complete(late_closed_asset,{code='closed'})
complete(late_closed_asset,nil)
assert(closed_late==0 and calls.closed==1)
local function superseded_open(change_at)
  local dir=vim.fn.tempname();vim.fn.mkdir(dir..'/nested','p')
  local target=dir..'/nested/target.lua';vim.fn.writefile({'x'},target)
  calls={}
  local result={ready=0,failed=0}
  Native.open(dir,nil,{ready=function(v) result.ready=result.ready+1;result.view=v end,failed=function() result.failed=result.failed+1 end})
  calls.open(nil,new_handle())
  assert(vim.wait(1000,function() return pending('assets')~=nil end))
  complete(pending('assets'),nil)
  complete(pending('rows'),nil)
  local first_state=pending('state')
  if change_at=='state' then
    vim.cmd('edit '..vim.fn.fnameescape(target))
    assert(vim.wait(1000,function() return require('svgtree.state').get(dir).selected==target end))
  end
  complete(first_state,nil)
  local cursor=4
  if change_at=='focus' then
    local first_focus=pending('focus')
    assert(first_focus)
    vim.cmd('edit '..vim.fn.fnameescape(target))
    assert(vim.wait(1000,function() return require('svgtree.state').get(dir).selected==target end))
    complete(first_focus,nil)
    cursor=5
  end
  assert(result.ready==0,'superseded initial model must not be ready')
  while not result.view do
    assert(vim.wait(1000,function() return calls[cursor]~=nil end),'replacement model did not settle')
    complete(calls[cursor],nil)
    cursor=cursor+1
    assert(cursor<20,'replacement model did not settle')
  end
  assert(result.failed==0 and result.view.ack_revision>=2)
  result.view:close()
end
superseded_open('state')
superseded_open('focus')
print('native initial freshness: ok')
