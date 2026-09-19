local Controller=require('svgtree.native_controller')
local State=require('svgtree.state')
local Tree=require('svgtree.tree')
local Icons=require('svgtree.icons')
local View=require('svgtree.native_view')
local Config=require('svgtree.config')
local M={}
local function normal(win)
  if not vim.api.nvim_win_is_valid(win) then return false end
  local buf=vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype==''
end
function M.open(root,saved,callbacks)
  callbacks=callbacks or {}
  root=Tree.normalize(root)
  local existing=false
  if saved==nil then saved,existing=State.get(root) else existing=true end
  saved=vim.deepcopy(saved)
  saved.widths=saved.widths or {native=280}
  local native_options=Config.options.native or {}
  if native_options.width and not existing then saved.widths.native=native_options.width end
  local side=native_options.side or (Config.options.window and Config.options.window.side) or 'left'
  local sprite=require('sprite')
  local pack=Icons.resolve_pack('native')
  local self={wanted=true,phase='opening',root_path=root,snapshot_value=saved,
    revision=0,sent_revision=0,ack_revision=0,generation=0,registered={},target=vim.api.nvim_get_current_win()}
  local finished=false
  local function current(g) return self.generation==g and self.wanted and self.phase~='closed' and self.phase~='suspended' end
  local function remove_target_group()
    if self.target_group then vim.api.nvim_del_augroup_by_id(self.target_group); self.target_group=nil end
  end
  local function create_target_group()
    remove_target_group()
    self.target_group=vim.api.nvim_create_augroup('SVGTreeNativeTarget'..tostring(self):gsub('%W',''),{clear=true})
    vim.api.nvim_create_autocmd({'WinEnter','BufEnter'},{group=self.target_group,callback=function()
      local win=vim.api.nvim_get_current_win()
      if normal(win) then self.target=win end
    end})
  end
  local function failure(err)
    if finished or not self.wanted then return end
    State.save(root,self.snapshot_value)
    finished=true; self.phase='closed'; self.generation=self.generation+1
    if self.controller then self.controller:close(); self.controller=nil end
    if self.handle then local h=self.handle; self.handle=nil; h:close() end
    remove_target_group()
    if self.resume_unsub then self.resume_unsub(); self.resume_unsub=nil end
    if callbacks.failed then callbacks.failed(err) end
  end
  local function save()
    State.save(root,self.snapshot_value)
  end
  local function close(reason)
    if self.phase=='closed' then return end
    self.phase='closed';self.generation=self.generation+1
    if self.controller then self.controller:close(); self.controller=nil end
    if reason~='suspend' then self.wanted=false end
    remove_target_group()
    if reason~='suspend' and self.resume_unsub then self.resume_unsub(); self.resume_unsub=nil end
    save()
    if reason~='suspend' and callbacks.closed and not finished then finished=true; callbacks.closed() end
  end
  local function active() return self.phase=='ready' and self.focused end
  local function open_file(path,focus)
    if not vim.uv.fs_stat(path) or vim.uv.fs_stat(path).type~='file' then
      vim.notify('File is no longer available: '..path,vim.log.levels.ERROR)
      self.controller.suppressed=nil; return false
    end
    if not normal(self.target) then
      vim.notify('No normal editing window is available',vim.log.levels.ERROR)
      self.controller.suppressed=nil; return false
    end
    local ok,err=pcall(vim.api.nvim_win_call,self.target,function()
      vim.api.nvim_cmd({cmd='edit',args={path}}, {})
    end)
    if not ok then vim.notify(tostring(err),vim.log.levels.ERROR); self.controller.suppressed=nil; return false end
    if focus and self.handle then
      local g=self.generation
      self.handle:focus_editor(function(e) if current(g) and e then failure(e) end end)
    end
    return true
  end
  local function status(snapshot)
    local search=snapshot.search
    if search and search.active then return '/'..search.query..' — '..search.count..' matches' end
    return vim.NIL
  end
  local send
  local function send_state(reveal,initial)
    if not self.handle then return end
    local s=self.snapshot_value
    local selected=s.selected
    if self.sent_rows and not vim.tbl_contains(vim.tbl_map(function(row) return row.id end,self.sent_rows),selected) then selected=nil end
    local patch={selected=selected or vim.NIL,status=status(s)}
    if reveal and selected then patch.reveal=reveal
    elseif initial and selected and s.scroll and s.scroll.id and not s.root_collapsed then patch.scroll={id=s.scroll.id,offset=s.scroll.offset or 0} end
    self.pending_state=false; self.reveal=nil; self.busy=true; self.busy_kind='state'
    local g=self.generation
    self.handle:state(self.ack_revision,patch,function(err)
      if not current(g) then return end
      if err then failure(err); return end
      self.busy=false; self.busy_kind=nil
      if initial and self.phase=='opening' then
        if self.desired_rows~=self.sent_rows or self.pending_state then send();return end
        self.handle:focus(function(e)
          if not current(g) then return end
          if e then failure(e); return end
          if not self.wanted or self.phase~='opening' then return end
          if self.desired_rows~=self.sent_rows or self.pending_state then send();return end
          self.phase='ready'; self.focused=true; if callbacks.ready then callbacks.ready(self) end; send()
        end)
      else
        send()
        if not self.busy and self.ack_revision>0 and self.desired_rows==self.sent_rows and self.queued_action then
          local action=self.queued_action;self.queued_action=nil
          if self.focused then self.controller:action(action) end
        end
      end
    end)
  end
  send=function()
    if not self.handle or self.phase=='closed' or self.phase=='suspended' or self.busy then return end
    if self.pending_description then
      self.busy=true;self.busy_kind='structure'
      local description=self.pending_description
      self.pending_description=nil
      local g=self.generation
      self.handle:update(description,function(err)
        if not current(g) then return end
        if err then failure(err);return end
        self.busy=false;self.busy_kind=nil;send()
      end)
      return
    end
    if self.desired_rows and (self.ack_revision==0 or not vim.deep_equal(self.desired_rows,self.sent_rows)) then
      self.busy=true; self.busy_kind='structure'
      local rows=self.desired_rows
      local ids=self.desired_ids
      local missing={}
      for id in pairs(ids) do if not self.asset_attempted[id] then missing[id]=true end end
      local assets=View.assets(pack,missing)
      for id in pairs(missing) do self.asset_attempted[id]=true end
      local batches,batch,size={}, {}, 0
      for id,svg in pairs(assets) do
        local encoded=#vim.json.encode({[id]=svg})
        if size+encoded>8*1024*1024 and next(batch) then batches[#batches+1]=batch; batch={};size=0 end
        if encoded<=8*1024*1024 then batch[id]=svg; size=size+encoded end
      end
      if next(batch) then batches[#batches+1]=batch end
      local g=self.generation
      local function assets_next(index)
        if not current(g) then return end
        if index<=#batches then
          local entries=batches[index]
          self.handle:assets(entries,function(err)
            if not current(g) then return end
            if err then failure(err); return end
            for id in pairs(entries) do self.registered[id]=true end
            assets_next(index+1)
          end)
          return
        end
        self.revision=self.revision+1
        local rev=self.revision
        self.sent_revision=rev;self.sent_rows=rows
        local selected=nil
        for _,row in ipairs(rows) do if row.id==self.snapshot_value.selected then selected=row.id;break end end
        self.handle:rows(rev,rows,selected,function(err)
          if not current(g) then return end
          if err then failure(err); return end
          self.ack_revision=rev; self.busy=false; self.busy_kind=nil
          if self.desired_rows~=rows then send() else send_state(self.reveal,self.phase=='opening') end
        end)
      end
      assets_next(1)
    elseif self.ack_revision>0 and (self.phase=='ready' or self.phase=='opening') then
      if self.pending_state then
        send_state(self.reveal,self.phase=='opening')
      end
    end
  end
  local function change(rows,snapshot,reveal)
    self.snapshot_value=snapshot
    local rendered,ids=View.rows(rows,pack)
    if snapshot.root_collapsed then rendered={}; ids={['svgtree-chevron-right']=true} end
    if not vim.deep_equal(rendered,self.desired_rows) then self.desired_rows=rendered;self.desired_ids=ids end
    self.reveal=reveal
    self.pending_state=true
    save();send()
  end
  local function event(ev)
    if self.phase~='ready' or not self.controller then return end
    if ev.type=='focus' then self.focused=true;self.controller.keys:reset()
    elseif ev.type=='blur' then self.focused=false; self.controller:handle(ev)
    elseif ev.type=='dock_size' then
      self.snapshot_value.widths.native=ev.width
      self.controller.snapshot.widths.native=ev.width;save()
    elseif ev.type=='list_scroll' then
      if ev.revision~=self.ack_revision or self.busy_kind=='structure' or self.pending_description or self.desired_rows~=self.sent_rows then return end
      self.snapshot_value.scroll={id=ev.top,offset=ev.offset,visible_rows=ev.visible_rows}
      self.controller.snapshot.scroll=vim.deepcopy(self.snapshot_value.scroll);save()
    elseif ev.type=='list_click' or ev.type=='list_action' then
      if ev.revision~=self.ack_revision or self.busy_kind=='structure' or self.pending_description or self.desired_rows~=self.sent_rows then return end
      if ev.type=='list_action' then
        if ev.action=='root-toggle' then
          self.snapshot_value.root_collapsed=not self.snapshot_value.root_collapsed
          self.controller.snapshot.root_collapsed=self.snapshot_value.root_collapsed
          self.pending_description=View.description(nil,root,self.snapshot_value.root_collapsed)
          change(self.controller.rows,self.controller.snapshot,nil)
        end
        return
      end
      if ev.button~='left' then return end
      local row
      for _,r in ipairs(self.controller.rows) do if r.id==ev.id then row=r;break end end
      if not row then return end
      self.controller.snapshot.selected=row.id
      if row.kind=='dir' then
        if ev.count==1 then self.controller:action('open') end
      elseif ev.count==1 then
        self.controller:publish(row.id); self.click_open=true; self.controller:action('open'); self.click_open=false
      elseif ev.count==2 then
        if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(self.target))==row.path then
          local g=self.generation
          self.handle:focus_editor(function(e) if current(g) and e then failure(e) end end)
        else open_file(row.path,true) end
      end
    else
      if self.busy_kind=='structure' or self.pending_description or self.desired_rows~=self.sent_rows then
        if ev.type=='input' then
          local action=self.controller.keys:feed(ev,vim.uv.now())
          local navigation={next=true,previous=true,first=true,last=true,half_down=true,half_up=true,search_next=true,search_previous=true}
          if navigation[action] then self.queued_action=action end
        end
      else self.controller:handle(ev,vim.uv.now()) end
    end
  end
  local function start()
    self.generation=self.generation+1
    local g=self.generation
    create_target_group()
    self.phase='opening';self.registered={};self.asset_attempted={};self.sent_rows=nil;self.ack_revision=0;self.busy=false;self.busy_kind=nil;self.pending_description=nil
    self.controller=Controller.new({root=root,snapshot=self.snapshot_value,side=side,keys=native_options.mappings,compact=native_options.compact_folders,
      is_active=active,on_change=change,on_open=function(path) open_file(path,not self.click_open) end,
      on_close=function() self:close() end,
      on_editor_focus=function() if self.handle then self.handle:focus_editor(function(e) if current(g) and e then failure(e) end end) end end})
    sprite.open({side=side,width=self.snapshot_value.widths.native or 280,
      description=View.description(nil,root,self.snapshot_value.root_collapsed),
      on_event=function(ev) if current(g) then event(ev) end end,on_close=function(reason)
        if not current(g) then return end
        if reason.kind=='failure' then failure(reason.error)
        elseif reason.kind=='suspend' then
          self.handle=nil;close('suspend');self.phase='suspended'
        elseif reason.kind=='requested' then close('requested')
        else close('exit') end
      end},function(err,handle)
        if not current(g) or self.phase~='opening' then if handle then handle:close() end; return end
        if err then failure(err);return end
        self.handle=handle
        self.controller:refresh()
      end)
  end
  function self:root() return self.phase=='closed' and nil or self.root_path end
  function self:snapshot() return vim.deepcopy(self.snapshot_value) end
  function self:focus() if self.phase=='ready' then
    local g=self.generation
    self.handle:focus(function(e) if current(g) and e then failure(e) end end)
  end end
  function self:close()
    if self.phase=='closed' then return end
    local handle=self.handle
    close('requested')
    if handle then handle:close() end
  end
  self.resume_unsub=sprite.on_resume(function()
    if self.wanted and self.phase=='suspended' then start() end
  end)
  sprite.register_tokens(View.tokens(),function(err) if err then failure(err) elseif self.wanted then start() end end)
  return function() self:close() end
end
return M
