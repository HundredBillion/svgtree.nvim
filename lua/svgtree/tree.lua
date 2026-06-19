-- Directory model: scan a root, track which dirs are expanded, and flatten
-- the expanded subtree into an ordered list of visible nodes.

local config = require('svgtree.config')

local M = {}

---@class svgtree.Node
---@field name string basename
---@field path string absolute path
---@field kind 'dir'|'file'
---@field depth integer 0-based indent level

---@class svgtree.Tree
---@field root string
---@field expanded table<string, boolean>
local Tree = {}
Tree.__index = Tree

---@param root string
---@return svgtree.Tree
function M.new(root)
  return setmetatable({
    root = vim.fn.fnamemodify(root, ':p'):gsub('/$', ''),
    expanded = {},
  }, Tree)
end

-- Read one directory level, sorted: directories first, then files, alpha.
local function scandir(dir)
  local entries = {}
  local fs = vim.uv.fs_scandir(dir)
  if not fs then
    return entries
  end
  while true do
    local name, t = vim.uv.fs_scandir_next(fs)
    if not name then
      break
    end
    if config.options.show_hidden or name:sub(1, 1) ~= '.' then
      local kind = (t == 'directory') and 'dir' or 'file'
      -- Resolve symlinks-to-dirs as dirs.
      if t == 'link' then
        local st = vim.uv.fs_stat(dir .. '/' .. name)
        kind = (st and st.type == 'directory') and 'dir' or 'file'
      end
      entries[#entries + 1] = { name = name, kind = kind }
    end
  end
  table.sort(entries, function(a, b)
    if (a.kind == 'dir') ~= (b.kind == 'dir') then
      return a.kind == 'dir'
    end
    return a.name:lower() < b.name:lower()
  end)
  return entries
end

function Tree:is_expanded(path)
  return self.expanded[path] == true
end

function Tree:toggle(path)
  self.expanded[path] = not self.expanded[path] or nil
end

-- Produce the flat, ordered list of currently-visible nodes.
---@return svgtree.Node[]
function Tree:flatten()
  local out = {}
  local function walk(dir, depth)
    for _, e in ipairs(scandir(dir)) do
      local path = dir .. '/' .. e.name
      out[#out + 1] = { name = e.name, path = path, kind = e.kind, depth = depth }
      if e.kind == 'dir' and self.expanded[path] then
        walk(path, depth + 1)
      end
    end
  end
  walk(self.root, 0)
  return out
end

return M
