local Tree = require('svgtree.tree')
local M = {}
local saved = {}

local function initial(root)
  return {root = root, expanded = {}, selected = nil,
    scroll = {id = nil, offset = 0}, terminal_topline = 1,
    widths = {terminal = 36, native = 280}, root_collapsed = false}
end

function M.get(root)
  root = Tree.normalize(root)
  return vim.deepcopy(saved[root] or initial(root)), saved[root] ~= nil
end

function M.save(root, snapshot)
  root = Tree.normalize(root)
  local state = vim.tbl_deep_extend('force', initial(root), vim.deepcopy(snapshot or {}))
  state.root = root
  saved[root] = vim.deepcopy(state)
  return vim.deepcopy(state)
end

function M.reconcile(rows, selected)
  if not selected then return rows[1] and rows[1].id or nil end
  selected = Tree.normalize(selected)
  local candidate = selected
  while candidate do
    for _, row in ipairs(rows) do
      if row.id == candidate then return row.id end
      for _, member in ipairs(row.chain) do
        if member == candidate then return row.id end
      end
    end
    local parent = vim.fs.dirname(candidate)
    if not parent or parent == candidate then break end
    candidate = parent
  end
  return rows[1] and rows[1].id or nil
end

function M.rows(tree, compact)
  if tree.closed then return {} end
  if not compact then
    local rows = {}
    for _, node in ipairs(tree:flatten()) do
      rows[#rows + 1] = {id = node.path, path = node.path, text = node.name,
        depth = node.depth, kind = node.kind, chain = {node.path},
        expanded = node.expanded == true, status = node.status, error = node.error}
    end
    return rows
  end
  local rows = {}
  local root_real = tree.root_realpath or tree.root
  local function walk(dir, depth, ancestors)
    local record = tree.cache[dir]
    if not record or record.status ~= 'loaded' then return end
    local own = vim.deepcopy(ancestors)
    own[dir == tree.root and root_real or record.realpath or dir] = true
    for _, entry in ipairs(record.entries) do
      local path = dir == '/' and '/' .. entry.name or dir .. '/' .. entry.name
      local chain, names = {path}, {entry.name}
      local deepest = path
      local cycle = entry.realpath and own[entry.realpath] or false
      local tail_real = entry.realpath
      local tail_ancestors = vim.deepcopy(own)
      while entry.kind == 'dir' and not cycle do
        local child_record = tree.cache[deepest]
        if not child_record or child_record.status ~= 'loaded' or #child_record.entries ~= 1 then break end
        local child = child_record.entries[1]
        if child.kind ~= 'dir' then break end
        local child_path = deepest == '/' and '/' .. child.name or deepest .. '/' .. child.name
        if not tree.cache[child_path] or tree.cache[child_path].status ~= 'loaded' then break end
        tail_ancestors[tail_real or deepest] = true
        if child.realpath and tail_ancestors[child.realpath] then break end
        deepest = child_path
        chain[#chain + 1], names[#names + 1] = deepest, child.name
        tail_real = child.realpath
      end
      local leaf = tree.cache[deepest]
      rows[#rows + 1] = {id = deepest, path = deepest, text = table.concat(names, '/'),
        depth = depth, kind = entry.kind, chain = chain,
        expanded = tree:is_expanded(deepest),
        status = cycle and 'cycle' or (leaf and leaf.status or 'unknown'),
        error = leaf and leaf.error or nil}
      if entry.kind == 'dir' and tree:is_expanded(deepest) and not cycle then
        walk(deepest, depth + 1, tail_ancestors)
      end
    end
  end
  walk(tree.root, 0, {})
  return rows
end

return M
