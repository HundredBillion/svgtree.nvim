local Tree = require('svgtree.tree')
local M = {}
local Watch = {}
Watch.__index = Watch

function M.new(opts)
  opts = opts or {}
  return setmetatable({invalidate = assert(opts.invalidate), warn = opts.warn or function() end,
    new_event = opts.new_event or vim.uv.new_fs_event, new_timer = opts.new_timer or vim.uv.new_timer,
    schedule = opts.schedule or vim.schedule, now = opts.now or function() return vim.uv.now() end,
    handles = {}, dirty = {}, count = 0, generation = 0, next_handle = 0, timer_generation = 0, closed = false, warned = false}, Watch)
end

function Watch:warning()
  if self.warned then return end
  self.warned = true
  self.schedule(function() if not self.closed then self.warn('native tree watches exhausted; use R to refresh unwatched directories') end end)
end

function Watch:flush()
  if self.closed or not next(self.dirty) then return end
  local dirs = {}
  for path in pairs(self.dirty) do dirs[#dirs + 1] = path end
  table.sort(dirs)
  self.dirty = {}
  self.first = nil
  local generation = self.generation
  self.schedule(function() if not self.closed and self.generation == generation then self.invalidate(dirs) end end)
end

function Watch:arm()
  if self.closed then return end
  if not self.timer then self.timer = self.new_timer() end
  local remaining = math.max(0, 250 - (self.now() - self.first))
  self.timer:stop()
  self.timer_generation = self.timer_generation + 1
  local generation = self.timer_generation
  self.timer:start(math.min(50, remaining), 0, function()
    if not self.closed and self.timer_generation == generation then self:flush() end
  end)
end

function Watch:mark(path, generation)
  local slot = self.handles[path]
  if self.closed or not slot or slot.generation ~= generation then return end
  self.dirty[path] = true
  self.first = self.first or self.now()
  self:arm()
end

function Watch:set(paths)
  if self.closed then return end
  local wanted = {}
  for _, path in ipairs(paths or {}) do wanted[Tree.normalize(path)] = true end
  for path, slot in pairs(self.handles) do
    if not wanted[path] then
      slot.handle:stop(); slot.handle:close()
      self.handles[path] = nil; self.count = self.count - 1
      self.dirty[path] = nil
    end
  end
  if not next(self.dirty) then self.first = nil end
  local missing = {}
  for path in pairs(wanted) do if not self.handles[path] then missing[#missing + 1] = path end end
  table.sort(missing)
  for _, path in ipairs(missing) do
    if self.count >= 1024 then self:warning(); break end
    local handle = self.new_event()
    if not handle then self:warning(); break end
    self.next_handle = self.next_handle + 1
    local generation = self.next_handle
    local ok = handle:start(path, {}, function(err)
      if err then self:warning() end
      self:mark(path, generation)
    end)
    if ok then
      self.handles[path] = {handle = handle, generation = generation}
      self.count = self.count + 1
    else
      handle:close(); self:warning()
    end
  end
end

function Watch:close()
  if self.closed then return end
  self.closed = true
  self.generation = self.generation + 1
  self.timer_generation = self.timer_generation + 1
  if self.timer then self.timer:stop(); self.timer:close() end
  for _, slot in pairs(self.handles) do slot.handle:stop(); slot.handle:close() end
  self.handles, self.dirty = {}, {}
  self.count = 0
end

return M
