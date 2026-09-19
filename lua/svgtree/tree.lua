local config = require('svgtree.config')

local M = {}
local Tree = {}
Tree.__index = Tree

function M.normalize(path)
  local absolute = vim.fn.fnamemodify(path, ':p')
  local normalized = vim.fs.normalize(absolute)
  if normalized == '' then return '/' end
  return normalized
end

function M.contains(root, path)
  root, path = M.normalize(root), M.normalize(path)
  return path == root or path:sub(1, #root + (root == '/' and 0 or 1)) == root .. (root == '/' and '' or '/')
end

local function join(dir, name)
  return dir == '/' and '/' .. name or dir .. '/' .. name
end

local function sorted(entries, show_hidden)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    if show_hidden or entry.name:sub(1, 1) ~= '.' then
      out[#out + 1] = entry
    end
  end
  table.sort(out, function(a, b)
    if a.kind ~= b.kind then return a.kind == 'dir' end
    local af, bf = a.name:lower(), b.name:lower()
    if af ~= bf then return af < bf end
    return a.name < b.name
  end)
  return out
end

local function sync_scan(dir, done)
  local entries = {}
  local handle, err = vim.uv.fs_scandir(dir)
  if not handle then return done(err or 'unreadable directory') end
  while true do
    local name, kind = vim.uv.fs_scandir_next(handle)
    if not name then break end
    local path = join(dir, name)
    if kind == 'link' then
      local stat = vim.uv.fs_stat(path)
      kind = stat and stat.type or kind
    end
    entries[#entries + 1] = {name = name, kind = kind == 'directory' and 'dir' or 'file', realpath = kind == 'directory' and vim.uv.fs_realpath(path) or nil}
  end
  done(nil, entries)
end

local function async_scan(dir, done)
  local function finish(err, entries)
    vim.schedule(function() done(err, entries) end)
  end
  vim.uv.fs_scandir(dir, function(err, handle)
    if err or not handle then return finish(err or 'unreadable directory') end
    local entries = {}
    local drain
    drain = function()
      while true do
        local name, kind = vim.uv.fs_scandir_next(handle)
        if not name then return finish(nil, entries) end
        local entry = {name = name, kind = kind == 'directory' and 'dir' or 'file'}
        entries[#entries + 1] = entry
        local path = join(dir, name)
        local function resolve_dir()
          if entry.kind ~= 'dir' then return drain() end
          vim.uv.fs_realpath(path, function(_, real)
            entry.realpath = real
            drain()
          end)
        end
        if kind == 'link' then
          vim.uv.fs_stat(path, function(_, stat)
            entry.kind = stat and stat.type == 'directory' and 'dir' or 'file'
            resolve_dir()
          end)
          return
        elseif entry.kind == 'dir' then
          resolve_dir()
          return
        end
      end
    end
    drain()
  end)
end

function M.new(root, opts)
  opts = opts or {}
  return setmetatable({
    root = M.normalize(root), expanded = {},
    show_hidden = opts.show_hidden == nil and config.options.show_hidden or opts.show_hidden,
    async = opts.async == true, scan = opts.scan or (opts.async and async_scan or sync_scan),
    cache = {}, generation = 0, closed = false, inflight = 0,
    root_realpath = vim.uv.fs_realpath(M.normalize(root)) or M.normalize(root),
  }, Tree)
end

function Tree:is_expanded(path)
  return self.expanded[M.normalize(path)] == true
end

function Tree:toggle(path)
  path = M.normalize(path)
  self.expanded[path] = not self.expanded[path] or nil
end

function Tree:flatten()
  if self.closed then return {} end
  local out = {}
  local function walk(dir, depth, ancestors)
    local record = self.cache[dir]
    if not self.async then
      self.scan(dir, function(err, entries)
        record = {status = err and 'error' or 'loaded', error = err, entries = sorted(entries, self.show_hidden)}
      end)
    end
    if not record or record.status ~= 'loaded' then return end
    local own = vim.deepcopy(ancestors)
    own[dir == self.root and self.root_realpath or record.realpath or dir] = true
    for _, entry in ipairs(record.entries) do
      local path = join(dir, entry.name)
      local node = {name = entry.name, path = path, kind = entry.kind, depth = depth}
      if entry.kind == 'dir' then
        node.expanded = self:is_expanded(path)
        node.status = self.cache[path] and self.cache[path].status or 'unknown'
        node.error = self.cache[path] and self.cache[path].error or nil
        node.cycle = (entry.realpath and own[entry.realpath]) or false
        if node.cycle then node.status = 'cycle' end
      end
      out[#out + 1] = node
      if entry.kind == 'dir' and node.expanded and not node.cycle then walk(path, depth + 1, own) end
    end
  end
  walk(self.root, 0, {})
  return out
end

function Tree:refresh(callback, dirty_dirs)
  callback = callback or function() end
  if self.closed then return end
  self.generation = self.generation + 1
  local generation = self.generation
  local queue, inspect_queue, queued = {}, {}, {}
  local queue_head, inspect_head = 1, 1
  local active, completed, pumping = 0, false, false
  local full = dirty_dirs == nil
  local dirty = {}
  for key, value in pairs(dirty_dirs or {}) do
    if type(key) == 'number' then dirty[M.normalize(value)] = true
    elseif value then dirty[M.normalize(key)] = true end
  end
  local function valid() return not self.closed and self.generation == generation end
  local function enqueue(path, ancestors)
    if queued[path] then return end
    queued[path] = true
    queue[#queue + 1] = {path = path, ancestors = ancestors}
    self.cache[path] = {status = 'loading', entries = self.cache[path] and self.cache[path].entries or nil,
      realpath = self.cache[path] and self.cache[path].realpath or nil}
  end
  local function inspect(task)
    local path, ancestors = task.path, task.ancestors
    local record = self.cache[path]
    if not record or record.status ~= 'loaded' then return end
    local own = vim.deepcopy(ancestors)
    own[path == self.root and self.root_realpath or record.realpath or path] = true
    local sole = #record.entries == 1 and record.entries[1].kind == 'dir' and record.entries[1] or nil
    for _, entry in ipairs(record.entries) do
      if entry.kind == 'dir' and not (entry.realpath and own[entry.realpath]) then
        -- Only children of displayed expanded directories and sole-folder chains are displayed.
        if path == self.root or self.expanded[path] or entry == sole then
          local child = join(path, entry.name)
          local child_record = self.cache[child]
          if full or dirty[child] or not child_record or child_record.status == 'unknown' or child_record.status == 'loading' then
            enqueue(child, own)
            self.cache[child].realpath = entry.realpath
          else
            child_record.realpath = entry.realpath
            inspect_queue[#inspect_queue + 1] = {path = child, ancestors = own}
          end
        end
      end
    end
  end
  enqueue(self.root, {})
  local pump
  pump = function()
    if pumping or not valid() then return end
    pumping = true
    while valid() do
      while inspect_head <= #inspect_queue do
        inspect(inspect_queue[inspect_head])
        inspect_head = inspect_head + 1
      end
      if self.inflight >= 8 or queue_head > #queue then break end
      local task = queue[queue_head]
      queue_head = queue_head + 1
      active = active + 1
      self.inflight = self.inflight + 1
      self.scan(task.path, function(err, entries)
        self.inflight = self.inflight - 1
        if not valid() then
          if not self.closed and self.pump_current then self.pump_current() end
          return
        end
        active = active - 1
        self.cache[task.path] = {status = err and 'error' or 'loaded', error = err,
          entries = sorted(entries, self.show_hidden),
          realpath = task.path == self.root and self.root_realpath or self.cache[task.path].realpath}
        if not err then inspect_queue[#inspect_queue + 1] = task end
        pump()
      end)
    end
    pumping = false
    if valid() and active == 0 and queue_head > #queue and inspect_head > #inspect_queue and not completed then
      completed = true
      callback(nil, self)
    end
  end
  self.pump_current = pump
  pump()
end

function Tree:reveal(path, callback)
  callback = callback or function() end
  path = M.normalize(path)
  if not M.contains(self.root, path) or path == self.root then return callback(nil) end
  local relative = path:sub(#self.root + (self.root == '/' and 1 or 2))
  for part in relative:gmatch('[^/]+') do
    if not self.show_hidden and part:sub(1, 1) == '.' then return callback(nil) end
  end
  local parent = vim.fs.dirname(path)
  while parent and M.contains(self.root, parent) and parent ~= self.root do
    self.expanded[parent] = true
    parent = vim.fs.dirname(parent)
  end
  self:refresh(function()
    local found
    for _, row in ipairs(require('svgtree.state').rows(self, true)) do
      if row.id == path then found = row.id; break end
      for _, member in ipairs(row.chain) do
        if member == path then found = row.id; break end
      end
      if found then break end
    end
    callback(found)
  end)
end

function Tree:status(path)
  local record = self.cache[M.normalize(path)]
  return record and record.status or 'unknown', record and record.error or nil
end

function Tree:visible_dirs(compact)
  local dirs, seen = {self.root}, {[self.root] = true}
  for _, row in ipairs(require('svgtree.state').rows(self, compact)) do
    if row.kind == 'dir' then
      for _, path in ipairs(row.chain) do
        if not seen[path] and self.cache[path] and self.cache[path].status == 'loaded' then
          seen[path] = true
          dirs[#dirs + 1] = path
        end
      end
    end
  end
  return dirs
end

function Tree:close()
  self.closed = true
  self.generation = self.generation + 1
  self.cache = {}
end

return M
