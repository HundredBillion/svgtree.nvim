vim.opt.rtp:prepend(vim.fn.getcwd())
package.path=(vim.env.SVGTREE_API_CHECKOUT or '../native-explorer-api')..'/lua/?.lua;'..package.path
local Native=require('svgtree.native')
local View=require('svgtree.native_view')
local original_view_rows=View.rows
local view_projects=0
View.rows=function(...) view_projects=view_projects+1; return original_view_rows(...) end
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
local initial_projects=view_projects
local function complete_last() calls[#calls].args[#calls[#calls].args](nil) end
calls.opts.on_event({type='input',key='j',text='j'})
assert(calls[#calls].name=='state' and view_projects==initial_projects,'native selection must send state without row projection')
assert(calls[#calls].args[2].scroll==nil,'ordinary selection does not resend scroll')
complete_last()
calls.opts.on_event({type='list_scroll',revision=revision,top=root..'/two.lua',offset=2,visible_rows=10})
calls.opts.on_event({type='input',key='slash',text='/'})
assert(calls[#calls].name=='state' and view_projects==initial_projects,'native search must send state without row projection')
complete_last()
calls.opts.on_event({type='input',key='o',text='o'})
assert(calls[#calls].name=='state')
complete_last()
calls.opts.on_event({type='list_scroll',revision=revision,top=root..'/one.lua',offset=0,visible_rows=10})
calls.opts.on_event({type='input',key='escape'})
assert(calls[#calls].name=='state' and view_projects==initial_projects,'native search cancel must reuse rows')
assert(vim.deep_equal(calls[#calls].args[2].scroll,{id=root..'/two.lua',offset=2}), 'cancel restores original native scroll')
complete_last()
assert(revision>0)
i=#calls+1
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
calls.opts.on_event({type='input',key='slash',text='/'})
assert(calls[#calls].name=='state')
local search_state=calls[#calls]
local search_call_count=#calls
for _,letter in ipairs({'.','e','n','v'}) do calls.opts.on_event({type='input',key=letter,text=letter}) end
calls.opts.on_event({type='paste',text='Z'})
calls.opts.on_event({type='input',key='backspace'})
assert(calls.view:snapshot().search.query=='.env','search keeps every produced character while state ack waits')
assert(#calls==search_call_count,'search coalesces state at same revision')
search_state.args[#search_state.args](nil)
assert(calls[#calls].name=='state' and calls[#calls]~=search_state)
assert(calls[#calls].args[2].status:find('.env',1,true))
local pending_search=calls[#calls]
calls.opts.on_event({type='list_click',revision=calls.view.ack_revision,id=root..'/one.lua',count=1,button='left'})
assert(vim.api.nvim_buf_get_name(0)==root..'/one.lua','same-revision click works during state ack')
calls.opts.on_event({type='list_click',revision=calls.view.ack_revision,id=root..'/one.lua',count=2,button='left'})
assert(calls[#calls].name=='focus_editor','same-revision double click focuses during state ack')
pending_search.args[#pending_search.args](nil)
local original_notify=vim.notify
local notifications={}
vim.notify=function(message,level) notifications[#notifications+1]={message=message,level=level} end
calls.view.controller.watch:warning()
assert(vim.wait(1000,function() return #notifications>0 end))
assert(notifications[1].message=='native tree watches exhausted; use R to refresh unwatched directories'
  and notifications[1].level==vim.log.levels.WARN, 'native watch exhaustion reaches user')
notifications={}
vim.o.hidden=false
local modified_buf=vim.api.nvim_get_current_buf()
local original_disk=table.concat(vim.fn.readfile(root..'/one.lua'),'\n')
vim.api.nvim_buf_set_lines(modified_buf,0,1,false,{'unsaved native edit'})
local calls_before_refusal=#calls
calls.view.controller.snapshot.selected=root..'/two.lua'
calls.view.controller:action('open')
assert(vim.api.nvim_get_current_buf()==modified_buf and vim.bo[modified_buf].modified)
assert(vim.api.nvim_buf_get_lines(modified_buf,0,1,false)[1]=='unsaved native edit')
assert(table.concat(vim.fn.readfile(root..'/one.lua'),'\n')==original_disk)
assert(notifications[#notifications].message=='Save changes before opening another file', 'refusal notification stays concise: '..vim.inspect(notifications))
assert(#calls==calls_before_refusal and calls.view.focused, 'refusal keeps native focus and sends no editor focus request')
assert(calls.view.controller.suppressed==nil, 'refusal clears the open suppression')
vim.o.hidden=true
calls.view.controller:action('open')
assert(vim.api.nvim_buf_get_name(0)==root..'/two.lua', 'hidden option permits opening another file')
assert(vim.bo[modified_buf].modified and vim.api.nvim_buf_get_lines(modified_buf,0,1,false)[1]=='unsaved native edit')
assert(table.concat(vim.fn.readfile(root..'/one.lua'),'\n')==original_disk)
vim.notify=original_notify
vim.api.nvim_buf_set_option(modified_buf,'modified',false)
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
calls={}
local serial_root=vim.fn.tempname();vim.fn.mkdir(serial_root,'p');vim.fn.writefile({'x'},serial_root..'/file.lua')
local serial={}
Native.open(serial_root,nil,{ready=function(v) serial.view=v end,failed=function(e) error('serialized mutation refused: '..vim.inspect(e)) end})
calls.open(nil,new_handle())
finish_open(serial)
local revision_before=serial.view.ack_revision
calls.opts.on_event({type='input',key='slash',text='/'})
local inflight_state=calls[#calls]
assert(inflight_state.name=='state')
local count_before_toggle=#calls
calls.opts.on_event({type='list_action',revision=revision_before,action='root-toggle'})
assert(#calls==count_before_toggle,'root-toggle waits for current state acknowledgement')
complete(inflight_state,nil)
local update_call=calls[#calls]
assert(update_call.name=='update' and #calls==count_before_toggle+1)
complete(update_call,nil)
local next_rows=calls[#calls]
assert(next_rows.name=='rows' and #calls==count_before_toggle+2)
complete(next_rows,nil)
local next_state=calls[#calls]
assert(next_state.name=='state' and next_state.args[1]==serial.view.ack_revision)
assert(serial.view.ack_revision>revision_before)
complete(next_state,nil)
serial.view:close()
print('native serialized root toggle: ok')
View.rows=original_view_rows
