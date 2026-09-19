local Tree = require('svgtree.tree')
local State = require('svgtree.state')
local Watch = require('svgtree.watch')
local Keys = require('svgtree.keys')
local M = {}
local Controller = {}
Controller.__index = Controller

local function anchor(old_rows, rows, id)
  if not id then return nil end
  local present = {}
  for _, row in ipairs(rows) do present[row.id] = true end
  if present[id] then return id end
  local index
  for i, row in ipairs(old_rows) do if row.id == id then index = i; break end end
  if index then
    for i = index + 1, #old_rows do if present[old_rows[i].id] then return old_rows[i].id end end
    for i = index - 1, 1, -1 do if present[old_rows[i].id] then return old_rows[i].id end end
  end
  return rows[1] and rows[1].id or nil
end

function M.new(opts)
  Keys.validate(opts.keys)
  local root = Tree.normalize(assert(opts.root))
  local self = setmetatable({root=root, tree=opts.tree or Tree.new(root, {async=true}),
    snapshot=opts.snapshot or State.get(root), rows={}, on_change=opts.on_change or function() end,
    on_open=opts.on_open or function() end, on_editor_focus=opts.on_editor_focus or function() end,
    on_close=opts.on_close or function() end, on_root=opts.on_root or function() end,
    keys=Keys.new(opts.keys, opts.key_timeout_ms, opts.side), is_active=opts.is_active or function() return true end, search={active=false,query='',last='',matches={}},
    on_search=opts.on_search, compact=opts.compact ~= false,
    generation=0, closed=false}, Controller)
  self.snapshot.root = root
  self.snapshot.scroll = self.snapshot.scroll or {id=nil,offset=0}
  for path, value in pairs(self.snapshot.expanded or {}) do if value then self.tree.expanded[path]=true end end
  self.watch = opts.watch or Watch.new({invalidate=function(dirs) self:refresh(dirs) end, warn=opts.warn})
  if opts.autocmd ~= false then
    self.group = vim.api.nvim_create_augroup('SVGTreeNative' .. tostring(self):gsub('%W', ''), {clear=true})
    vim.api.nvim_create_autocmd('BufEnter', {group=self.group, callback=function(event) self:on_buf_enter(event.buf) end})
  end
  return self
end

function Controller:publish(reveal, structure_changed)
  if structure_changed then
    local old = self.rows
    local rows = State.rows(self.tree, self.compact)
    self.snapshot.selected = State.reconcile(rows, self.snapshot.selected)
    self.snapshot.scroll.id = anchor(old, rows, self.snapshot.scroll.id)
    self.rows = rows
    self.snapshot.expanded = vim.deepcopy(self.tree.expanded)
    self:update_search()
    self.watch:set(self.tree:visible_dirs(self.compact))
    if self.on_search then self.on_search(rows) end
  end
  State.save(self.root, self.snapshot)
  self.on_change(self.rows, vim.deepcopy(self.snapshot), reveal)
end

function Controller:refresh(dirty)
  if self.closed then return end
  self.generation = self.generation + 1
  local generation = self.generation
  self.tree:refresh(function(err)
    if self.closed or generation ~= self.generation then return end
    if not err then
      self:publish(nil, true)
      if self.pending_reveal then self:reveal_pending(self.pending_reveal) end
    end
  end, dirty)
end

function Controller:reveal_pending(path)
  local generation = self.generation
  self.tree:reveal(path, function(id)
    if self.closed or generation ~= self.generation or self.pending_reveal ~= path then return end
    self.pending_reveal = nil
    if not id then return end
    self.snapshot.selected = path
    self:publish(id, true)
  end)
end

function Controller:suppress_open(path)
  self.suppressed = Tree.normalize(path)
end

function Controller:on_buf_enter(buf)
  if self.closed or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= '' then return end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then return end
  local path = Tree.normalize(name)
  if path == self.suppressed then
    self.suppressed = nil
    self.active = path
    self.pending_reveal = nil
    return
  end
  self.suppressed = nil
  if path == self.active then return end
  self.active = path
  self.pending_reveal = nil
  if path == self.root or not Tree.contains(self.root, path) then return end
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= 'file' then return end
  if not self.tree.show_hidden then
    local relative = path:sub(#self.root + (self.root == '/' and 1 or 2))
    for part in relative:gmatch('[^/]+') do if part:sub(1, 1) == '.' then return end end
  end
  self.generation = self.generation + 1
  self.pending_reveal = path
  self:reveal_pending(path)
end

local function row_index(rows, id)
  for i, row in ipairs(rows) do if row.id == id then return i end end
  return nil
end

function Controller:update_search()
  local query = self.search.query
  local matches = query ~= '' and Keys.search(self.rows, query) or {}
  self.search.matches = matches
  self.snapshot.search = {active=self.search.active, query=query, count=#matches}
end

function Controller:select(index)
  if #self.rows == 0 then return end
  index = math.max(1, math.min(#self.rows, index))
  self.snapshot.selected = self.rows[index].id
  self:publish(self.snapshot.selected)
end

function Controller:move_match(direction)
  local matches = self.search.matches
  if #matches == 0 then return end
  local current = row_index(self.rows, self.snapshot.selected) or 0
  local target
  if direction > 0 then
    for _, id in ipairs(matches) do if (row_index(self.rows,id) or 0)>current then target=id; break end end
    target = target or matches[1]
  else
    for i=#matches,1,-1 do if (row_index(self.rows,matches[i]) or 0)<current then target=matches[i]; break end end
    target = target or matches[#matches]
  end
  self.snapshot.selected=target
  self:publish(target)
end

function Controller:search_event(event)
  local call = require('sprite.input').call(event)
  local key, value
  if event.type=='paste' then
    value=event.text
  elseif event.type=='input' and call and call.method=='nvim_input' then
    key=call.args[1]
    if event.text ~= nil and not event.text:find('%c') then
      value=event.text
    elseif key=='<lt>' then value='<'
    elseif key=='<Space>' then value=' '
    elseif vim.fn.strchars(key)==1 then value=key end
  end
  if not value and key=='<Esc>' then
    self.search.active=false; self.search.query=self.search.last
    self.snapshot.selected=self.search.initial_selected
    self.snapshot.scroll=self.search.initial_scroll
    self.keys:reset(); self:update_search(); self:publish(); return 'search_cancel'
  end
  if not value and key=='<CR>' then
    if self.search.query ~= '' then self.search.last=self.search.query else self.search.query=self.search.last end
    self.search.active=false; self.keys:reset(); self:update_search(); self:publish(); return 'search_accept'
  end
  if not value and key=='<BS>' then
    local count=vim.fn.strchars(self.search.query)
    self.search.query=vim.fn.strcharpart(self.search.query,0,math.max(0,count-1))
  elseif value then
    self.search.query=self.search.query .. value:gsub('[\r\n]+',' ')
  else return nil end
  self:update_search()
  local matches=self.search.matches
  local reveal
  if #matches>0 then
    local current=row_index(self.rows,self.snapshot.selected) or 0
    if not vim.tbl_contains(matches,self.snapshot.selected) then
      for _, id in ipairs(matches) do
        if (row_index(self.rows,id) or 0)>current then reveal=id; break end
      end
      reveal=reveal or matches[1]
      self.snapshot.selected=reveal
    else reveal=self.snapshot.selected end
  end
  self:publish(reveal); return 'search_edit'
end

function Controller:action(action)
  if self.snapshot.root_collapsed and action ~= 'refresh' and action ~= 'close' and action ~= 'focus_editor'
    and action ~= 'parent_root' then return end
  local index = row_index(self.rows,self.snapshot.selected) or 1
  local row = self.rows[index]
  if action=='next' then self:select(index+1)
  elseif action=='previous' then self:select(index-1)
  elseif action=='first' then self:select(1)
  elseif action=='last' then self:select(#self.rows)
  elseif action=='half_down' or action=='half_up' then
    local page=math.max(1,math.floor((self.snapshot.scroll.visible_rows or 1)/2))
    self:select(index+(action=='half_down' and page or -page))
  elseif action=='search_next' then self:move_match(1)
  elseif action=='search_previous' then self:move_match(-1)
  elseif action=='search' then
    self.search.active=true; self.search.query=''
    self.search.initial_selected=self.snapshot.selected
    self.search.initial_scroll=vim.deepcopy(self.snapshot.scroll)
    self.keys:reset(); self:update_search(); self:publish()
  elseif action=='refresh' then self:refresh()
  elseif action=='close' then self:close(); self.on_close()
  elseif action=='focus_editor' then self.on_editor_focus()
  elseif action=='focus_root' and row then
    self.on_root(row.kind=='dir' and row.path or vim.fs.dirname(row.path))
  elseif action=='parent_root' then
    local parent=vim.fs.dirname(self.root)
    if parent and parent~=self.root then self.on_root(parent) end
  elseif row and (action=='open' or action=='enter') then
    if row.kind=='file' then
      self:suppress_open(row.path); self.on_open(row.path)
    elseif action=='open' or not self.tree:is_expanded(row.path) then
      self.tree:toggle(row.path); self:refresh()
    elseif self.rows[index+1] and self.rows[index+1].depth > row.depth then
      self:select(index+1)
    end
  elseif row and action=='parent' then
    if row.kind=='dir' and self.tree:is_expanded(row.path) then
      self.tree:toggle(row.path); self:refresh()
    else
      local parent=vim.fs.dirname(row.path)
      while parent and Tree.contains(self.root,parent) and parent~=self.root do
        local found=State.reconcile(self.rows,parent)
        if found and found~=row.id then self.snapshot.selected=found; self:publish(found); break end
        parent=vim.fs.dirname(parent)
      end
    end
  end
end

function Controller:handle(event, now_ms)
  if self.closed then return nil end
  if not self.is_active() then self.keys:reset(); return nil end
  if event.type=='blur' then self.keys:reset(); return nil end
  if self.search.active then return self:search_event(event) end
  local action=self.keys:feed(event,now_ms or 0)
  if action then self:action(action) end
  return action
end

function Controller:close()
  if self.closed then return end
  self.closed = true
  self.keys:reset()
  self.pending_reveal = nil
  self.generation = self.generation + 1
  if self.group then vim.api.nvim_del_augroup_by_id(self.group) end
  self.watch:close()
  self.tree:close()
end

return M
