-- Headless checks for the retained tree model in svgtree.state: a reopened
-- tree reuses retained records instead of copying them, and nothing a live
-- tree does afterwards can change what was retained.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require('svgtree.config').setup({})
local Tree, State = require('svgtree.tree'), require('svgtree.state')

local fails = 0
local function check(c, m)
  if c then print('  ok  ' .. m) else print('  FAIL ' .. m); fails = fails + 1 end
end

-- Scans answer from `listing[dir]`, or wait in `pending` when `hold` is set.
local listing, pending, hold = {}, {}, false
local function scan(dir, done)
  if hold then pending[#pending + 1] = {dir = dir, done = done}; return end
  done(nil, vim.deepcopy(listing[dir] or {}))
end
local function new_tree(root, opts)
  return Tree.new(root, vim.tbl_extend('force', {async = true, scan = scan}, opts or {}))
end
local function names(tree)
  return table.concat(vim.tbl_map(function(row) return row.text end, State.rows(tree, false)), ',')
end
local made = {}
local function fixture()
  local root = vim.fn.tempname(); vim.fn.mkdir(root, 'p')
  made[#made + 1] = root
  return assert(vim.uv.fs_realpath(root))
end

-- ---- restore hands over the retained records instead of copying them ----
local root = fixture()
listing[root] = {{name = 'a.lua', kind = 'file'}}
local live = new_tree(root)
live:refresh()
State.retain_tree(live)
local reopened = new_tree(root)
check(State.restore_tree(reopened), 'matching tree restores')
check(names(reopened) == 'a.lua', 'restored rows match retained rows: ' .. names(reopened))
check(rawequal(reopened.cache[root], live.cache[root]), 'restore reuses the retained record, not a copy')

-- ---- refreshing a live tree cannot change what was retained ----
listing[root] = {{name = 'b.lua', kind = 'file'}}
reopened:refresh()
check(names(reopened) == 'b.lua', 'restored tree still refreshes: ' .. names(reopened))
live:refresh()
local again = new_tree(root)
State.restore_tree(again)
check(names(again) == 'a.lua', 'refresh after restore leaves the retained model intact: ' .. names(again))

-- ---- a partial refresh that re-resolves a folder target keeps retained records intact ----
local linked = fixture()
listing[linked] = {{name = 'd', kind = 'dir', realpath = '/real/one'}}
listing[linked .. '/d'] = {{name = 'x.lua', kind = 'file'}}
local source = new_tree(linked)
source.expanded[linked .. '/d'] = true
source:refresh()
State.retain_tree(source)
local first = new_tree(linked)
first.expanded[linked .. '/d'] = true
State.restore_tree(first)
listing[linked][1].realpath = '/real/two'
first:refresh(nil, {linked})
check(first.cache[linked .. '/d'].realpath == '/real/two', 'partial refresh updates the folder target')
local second = new_tree(linked)
State.restore_tree(second)
check(second.cache[linked .. '/d'].realpath == '/real/one',
  'partial refresh does not rewrite the retained record: ' .. tostring(second.cache[linked .. '/d'].realpath))

-- ---- scans from a superseded or closed refresh cannot reach the retained model ----
local raced = fixture()
listing[raced] = {{name = 'kept.lua', kind = 'file'}}
local seed = new_tree(raced)
seed:refresh()
State.retain_tree(seed)
local racing = new_tree(raced)
State.restore_tree(racing)
hold = true
racing:refresh()
local superseded = table.remove(pending)
hold = false
listing[raced] = {{name = 'current.lua', kind = 'file'}}
racing:refresh()
superseded.done(nil, {{name = 'stale.lua', kind = 'file'}})
check(names(racing) == 'current.lua', 'superseded scan is ignored: ' .. names(racing))
hold = true
racing:refresh()
local orphaned = table.remove(pending)
hold = false
racing:close()
orphaned.done(nil, {{name = 'stale.lua', kind = 'file'}})
local intact = new_tree(raced)
State.restore_tree(intact)
check(names(intact) == 'kept.lua', 'superseded and closed scans leave the retained model intact: ' .. names(intact))

-- ---- restore is refused when the hidden-file setting or root target differs ----
local hidden = new_tree(raced, {show_hidden = not intact.show_hidden})
check(not State.restore_tree(hidden) and next(hidden.cache) == nil, 'show_hidden mismatch rejects restore')
local target_one, target_two = fixture(), fixture()
local link = vim.fn.tempname()
assert(vim.uv.fs_symlink(target_one, link))
listing[link] = {{name = 'one.lua', kind = 'file'}}
local before = new_tree(link)
before:refresh()
State.retain_tree(before)
assert(os.remove(link) and vim.uv.fs_symlink(target_two, link))
local moved = new_tree(link)
check(not State.restore_tree(moved) and next(moved.cache) == nil, 'root_realpath mismatch rejects restore')

-- ---- a root over the record budget drops its retained model ----
local big = fixture()
listing[big] = {{name = 'small.lua', kind = 'file'}}
local sized = new_tree(big)
sized:refresh()
State.retain_tree(sized)
check(State.restore_tree(new_tree(big)), 'small root is retained')
listing[big] = {}
for index = 1, 20001 do listing[big][index] = {name = index .. '.lua', kind = 'file'} end
sized:refresh()
State.retain_tree(sized)
check(not State.restore_tree(new_tree(big)), 'oversized root drops the retained model')

vim.fn.delete(link)
for _, path in ipairs(made) do vim.fn.delete(path, 'rf') end

if fails > 0 then print('test-tree-retain: ' .. fails .. ' FAIL'); os.exit(1) end
print('test-tree-retain: ALL PASS')
