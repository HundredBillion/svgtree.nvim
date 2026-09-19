local Tree = require('svgtree.tree')
local State = require('svgtree.state')
local Watch = require('svgtree.watch')
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
  local root = Tree.normalize(assert(opts.root))
  local self = setmetatable({root=root, tree=opts.tree or Tree.new(root, {async=true}),
    snapshot=State.get(root), rows={}, on_change=opts.on_change or function() end,
    on_search=opts.on_search, compact=opts.compact ~= false,
    generation=0, closed=false}, Controller)
  self.snapshot.root = root
  self.watch = opts.watch or Watch.new({invalidate=function(dirs) self:refresh(dirs) end, warn=opts.warn})
  if opts.autocmd ~= false then
    self.group = vim.api.nvim_create_augroup('SVGTreeNative' .. tostring(self):gsub('%W', ''), {clear=true})
    vim.api.nvim_create_autocmd('BufEnter', {group=self.group, callback=function(event) self:on_buf_enter(event.buf) end})
  end
  return self
end

function Controller:publish(reveal)
  local old = self.rows
  local rows = State.rows(self.tree, self.compact)
  self.snapshot.selected = State.reconcile(rows, self.snapshot.selected)
  self.snapshot.scroll.id = anchor(old, rows, self.snapshot.scroll.id)
  self.rows = rows
  self.watch:set(self.tree:visible_dirs(self.compact))
  if self.on_search then self.on_search(rows) end
  State.save(self.root, self.snapshot)
  self.on_change(rows, vim.deepcopy(self.snapshot), reveal)
end

function Controller:refresh(dirty)
  if self.closed then return end
  self.generation = self.generation + 1
  local generation = self.generation
  self.tree:refresh(function(err)
    if self.closed or generation ~= self.generation then return end
    if not err then
      self:publish()
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
    self:publish(id)
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

function Controller:close()
  if self.closed then return end
  self.closed = true
  self.pending_reveal = nil
  self.generation = self.generation + 1
  if self.group then vim.api.nvim_del_augroup_by_id(self.group) end
  self.watch:close()
  self.tree:close()
end

return M
