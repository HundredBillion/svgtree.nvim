vim.opt.runtimepath:prepend(vim.fn.getcwd())
require('svgtree.config').setup({})
local Tree = require('svgtree.tree')
local State = require('svgtree.state')

local function names(rows)
  local out = {}
  for _, row in ipairs(rows) do out[#out + 1] = row.text end
  return table.concat(out, ',')
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/parent/child/deep', 'p')
vim.fn.writefile({}, root .. '/parent/child/deep/leaf.txt')
vim.fn.writefile({}, root .. '/.secret')
local pending = {}
local calls = 0
local function scan(path, done)
  calls = calls + 1
  pending[path] = done
end
local tree = Tree.new(root .. '/', {async = true, scan = scan})
assert(tree.root == root)
assert(#tree:flatten() == 0)
assert(tree:status(root) == 'unknown')
local done = 0
tree:refresh(function() done = done + 1 end)
assert(pending[root])
pending[root](nil, {{name = 'parent', kind = 'dir'}, {name = '.secret', kind = 'file'}})
assert(pending[root .. '/parent'], 'compact discovery scans sole child')
pending[root .. '/parent'](nil, {{name = 'child', kind = 'dir'}})
assert(pending[root .. '/parent/child'])
pending[root .. '/parent/child'](nil, {{name = 'deep', kind = 'dir'}})
assert(pending[root .. '/parent/child/deep'])
pending[root .. '/parent/child/deep'](nil, {{name = 'leaf.txt', kind = 'file'}})
assert(done == 1)
local rows = State.rows(tree, true)
assert(names(rows) == 'parent/child/deep,.secret', names(rows))
assert(rows[1].id == root .. '/parent/child/deep')
assert(#rows[1].chain == 3)
assert(#tree:visible_dirs(true) == 4)
assert(State.reconcile(rows, root .. '/parent') == rows[1].id)
assert(State.reconcile(rows, root .. '/parent/child/deep/missing') == rows[1].id)
local prior_calls = calls
State.rows(tree, true)
tree:flatten()
assert(calls == prior_calls, 'cached projections must not scan')
tree:toggle(rows[1].id)
rows = State.rows(tree, true)
assert(rows[1].expanded)
assert(rows[2].text == 'leaf.txt' and rows[2].depth == 1)
assert(State.reconcile(rows, '/elsewhere') == rows[1].id)

local hidden = Tree.new(root, {async = true, show_hidden = false, scan = scan})
hidden:refresh()
pending[root](nil, {{name = 'parent', kind = 'dir'}, {name = '.secret', kind = 'file'}})
pending[root .. '/parent'](nil, {{name = 'child', kind = 'dir'}})
pending[root .. '/parent/child'](nil, {{name = 'deep', kind = 'dir'}})
pending[root .. '/parent/child/deep'](nil, {{name = 'leaf.txt', kind = 'file'}})
assert(names(State.rows(hidden, true)) == 'parent/child/deep')
local revealed
hidden:reveal(root .. '/.secret', function(ok) revealed = ok end)
assert(revealed == false)

local closed = Tree.new(root, {async = true, scan = scan})
closed:refresh(function() error('closed generation published') end)
local late = pending[root]
closed:close()
late(nil, {{name = 'late', kind = 'file'}})
assert(#closed:flatten() == 0)
local stale = Tree.new(root, {async = true, scan = scan})
stale:refresh(function() error('stale generation published') end)
local older = pending[root]
stale:refresh(function() end)
local newer = pending[root]
newer(nil, {{name = 'new', kind = 'file'}})
older(nil, {{name = 'old', kind = 'file'}})
assert(stale:flatten()[1].name == 'new')

local cycle = Tree.new(root, {async = true, scan = scan})
cycle:refresh()
pending[root](nil, {{name = 'back', kind = 'dir', realpath = cycle.root_realpath}})
assert(State.rows(cycle, true)[1].status == 'cycle')
assert(not pending[root .. '/back'])

local unreadable = Tree.new(root, {async = true, scan = scan})
unreadable:refresh()
pending[root](nil, {{name = 'parent', kind = 'dir'}})
pending[root .. '/parent'](nil, {{name = 'private', kind = 'dir'}})
pending[root .. '/parent/private']('EACCES')
assert(State.rows(unreadable, true)[1].text == 'parent', 'unreadable child cannot be compacted')

local errored = Tree.new(root, {async = true, scan = scan})
errored:refresh()
pending[root]('EACCES', nil)
local status, error_message = errored:status(root)
assert(status == 'error' and error_message == 'EACCES')

local snapshot = State.get(root)
snapshot.expanded[root .. '/parent'] = true
State.save(root, snapshot)
snapshot.expanded[root .. '/parent'] = false
assert(State.get(root).expanded[root .. '/parent'])
local copied = State.get(root)
copied.expanded[root .. '/parent'] = nil
assert(State.get(root).expanded[root .. '/parent'])
assert(State.get(root .. '/').root == root)

assert(Tree.normalize('/') == '/' and Tree.contains('/', '/tmp'))
assert(not Tree.contains(root, root .. '-other/file'))
assert(Tree.normalize(root .. '/x/../') == root)

local inflight, peak, callbacks = 0, 0, {}
local bounded = Tree.new(root, {async = true, scan = function(path, done)
  inflight = inflight + 1
  peak = math.max(peak, inflight)
  callbacks[path] = function(err, entries)
    inflight = inflight - 1
    done(err, entries)
  end
end})
local bounded_done = false
bounded:refresh(function() bounded_done = true end)
local many = {}
for index = 1, 20 do many[#many + 1] = {name = ('d%02d'):format(index), kind = 'dir'} end
callbacks[root](nil, many)
assert(peak == 8, 'at most eight directory scans are active')
for index = 1, 20 do callbacks[root .. ('/d%02d'):format(index)](nil, {}) end
assert(bounded_done and inflight == 0)

local refresh_calls = {}
local refresh_pending = {}
local refresh_tree = Tree.new(root, {async = true, scan = function(path, done)
  refresh_calls[#refresh_calls + 1] = path
  refresh_pending[path] = done
end})
refresh_tree:refresh()
refresh_pending[root](nil, {{name = 'a', kind = 'dir'}, {name = 'b', kind = 'dir'}})
refresh_pending[root .. '/a'](nil, {{name = 'old.txt', kind = 'file'}})
refresh_pending[root .. '/b'](nil, {})
refresh_tree:toggle(root .. '/a')
refresh_calls = {}
refresh_tree:refresh()
refresh_pending[root](nil, {{name = 'a', kind = 'dir'}, {name = 'b', kind = 'dir'}})
assert(#refresh_calls == 3, 'manual refresh rescans root and visible directories')
refresh_pending[root .. '/a'](nil, {{name = 'new.txt', kind = 'file'}})
refresh_pending[root .. '/b'](nil, {})
assert(State.rows(refresh_tree, false)[2].text == 'new.txt')
refresh_calls = {}
refresh_tree:refresh(nil, {root .. '/a'})
refresh_pending[root](nil, {{name = 'a', kind = 'dir'}, {name = 'b', kind = 'dir'}})
assert(#refresh_calls == 2, 'dirty list rescans only root and affected directory')
refresh_pending[root .. '/a'](nil, {{name = 'changed.txt', kind = 'file'}})
assert(State.rows(refresh_tree, false)[2].text == 'changed.txt')

local old_pending, old_active = {}, 0
local overlap = Tree.new(root, {async = true, scan = function(path, done)
  old_active = old_active + 1
  old_pending[#old_pending + 1] = function(err, entries)
    old_active = old_active - 1
    done(err, entries)
  end
end})
overlap:refresh()
local old_many = {}
for index = 1, 20 do old_many[#old_many + 1] = {name = ('x%02d'):format(index), kind = 'dir'} end
old_pending[1](nil, old_many)
assert(old_active == 8)
overlap:refresh()
assert(old_active == 8, 'superseding a generation preserves global scan bound')
old_pending[2](nil, {})
assert(old_active == 8, 'new generation takes released slot')
old_pending[10](nil, {})
overlap:close()

local real = Tree.new(root, {async = true})
local real_done = false
real:refresh(function() real_done = true end)
assert(vim.wait(5000, function() return real_done end, 10), 'production async scanner completes')
assert(real:status(root) == 'loaded')
assert(#real:flatten() > 0)
assert(not vim.in_fast_event(), 'refresh completion is in normal editor context')
local large = vim.fn.tempname()
vim.fn.mkdir(large, 'p')
for index = 1, 10000 do vim.fn.writefile({}, large .. ('/f%05d'):format(index)) end
local many_real = Tree.new(large, {async = true})
local many_done = false
many_real:refresh(function()
  assert(not vim.in_fast_event(), 'production callback is scheduled out of uv event')
  many_done = true
end)
assert(vim.wait(10000, function() return many_done end, 10), '10000-file scan completes')
assert(#many_real:flatten() == 10000)
vim.fn.delete(large, 'rf')

vim.fn.delete(root, 'rf')
print('test-native-model: ALL PASS')
