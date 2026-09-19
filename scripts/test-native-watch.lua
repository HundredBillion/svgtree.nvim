vim.opt.runtimepath:prepend(vim.fn.getcwd())
local Tree = require('svgtree.tree')
local Watch = require('svgtree.watch')
local root = Tree.normalize(vim.fn.tempname())
vim.fn.mkdir(root .. '/a/b', 'p')
local now, timers, handles, invalidations, warnings = 0, {}, {}, {}, {}
local function timer()
  local t = {}
  function t:start(ms, _, cb) self.at = now + ms; self.cb = cb end
  function t:stop() self.at = nil end
  function t:close() self.at = nil end
  timers[#timers + 1] = t
  return t
end
local function advance(ms)
  local target = now + ms
  while true do
    local next_at, next_timer
    for _, t in ipairs(timers) do if t.at and t.at <= target and (not next_at or t.at < next_at) then next_at, next_timer = t.at, t end end
    if not next_timer then break end
    now = next_at; next_timer.at = nil; next_timer.cb()
  end
  now = target
end
local function source()
  local h = {}
  function h:start(path, _, cb) self.path = path; self.cb = cb; handles[path] = self; return true end
  function h:stop() self.stopped = true end
  function h:close() self.stopped = true end
  return h
end
local watch = Watch.new({invalidate = function(dirs) invalidations[#invalidations + 1] = dirs end,
  warn = function(message) warnings[#warnings + 1] = message end,
  new_event = source, new_timer = timer, schedule = function(cb) cb() end, now = function() return now end})
watch:set({root, root .. '/', root .. '/a', root .. '/a/b'})
assert(vim.tbl_count(handles) == 3)
handles[root].cb(nil, nil); handles[root .. '/a'].cb(nil, 'x')
advance(49); assert(#invalidations == 0)
advance(1); assert(#invalidations == 1 and #invalidations[1] == 2)
for _ = 1, 7 do handles[root].cb(nil, nil); advance(40) end
assert(#invalidations == 2, 'continuous events flush within 250ms')
handles[root].cb(nil, nil); advance(50); assert(#invalidations == 3, 'watches survive prior flush')
watch:set({root})
assert(handles[root .. '/a'].stopped)
local stale = handles[root .. '/a'].cb
stale(nil, nil); advance(300); assert(#invalidations == 3)
watch:close()
handles[root].cb(nil, nil); advance(300); assert(#invalidations == 3)
local failure = Watch.new({invalidate = function() end, warn = function(m) warnings[#warnings + 1] = m end,
  new_event = function() return {start = function() return nil, 'resource exhausted' end, close = function() end} end,
  new_timer = timer, schedule = function(cb) cb() end, now = function() return now end})
failure:set({root, root .. '/a'}); assert(#warnings == 1); failure:close()

local many = {}
for i=1,1025 do many[i] = root .. '/many' .. i end
local capped_count = 0
local cap = Watch.new({invalidate=function() end, warn=function(m) warnings[#warnings+1]=m end,
  new_event=function() return {start=function() capped_count=capped_count+1; return true end, stop=function() end, close=function() end} end,
  new_timer=timer, schedule=function(cb) cb() end, now=function() return now end})
cap:set(many); assert(capped_count == 1024 and #warnings == 2)
cap:set(many); assert(#warnings == 2, 'resource warning emits once')
cap:close()

local found
local scan = function(path, cb)
  if path == root then cb(nil, {{name='a', kind='dir'}})
  elseif path == root .. '/a' then cb(nil, {{name='b', kind='dir'}})
  else cb(nil, {{name='leaf', kind='file'}}) end
end
local tree = Tree.new(root, {async=true, scan=scan, show_hidden=false})
tree:refresh(function()
  tree:reveal(root .. '/a/b/leaf', function(id) found=id end)
end)
assert(found == root .. '/a/b/leaf')
tree:reveal(root .. '/a', function(id) assert(id == root .. '/a/b', 'compact chain member reveals visible row') end)
tree:reveal(root .. '/.hidden', function(id) assert(id == nil) end)
tree:close()
vim.fn.delete(root, 'rf')
print('native watch ok')

local Controller = require('svgtree.native_controller')
local root2 = Tree.normalize(vim.fn.tempname())
vim.fn.mkdir(root2 .. '/folder', 'p')
vim.fn.writefile({'one'}, root2 .. '/folder/one.txt')
vim.fn.writefile({'two'}, root2 .. '/folder/two.txt')
local changes, search_runs, watched = {}, 0, {}
local controller = Controller.new({root=root2, tree=Tree.new(root2, {async=true, show_hidden=false}),
  watch={set=function(_, dirs) watched = dirs end, close=function() end},
  on_search=function() search_runs=search_runs+1 end,
  on_change=function(rows, snapshot) changes[#changes+1]={rows=rows,snapshot=snapshot} end})
controller:refresh()
assert(vim.wait(3000, function() return #changes == 1 end, 10))
assert(#watched == 2 and watched[1] == root2)
controller.snapshot.scroll = {id=root2 .. '/folder', offset=3}
vim.fn.writefile({'three'}, root2 .. '/folder/three.txt')
controller:refresh({root2 .. '/folder'})
assert(vim.wait(3000, function() return #changes == 2 end, 10))
assert(changes[#changes].snapshot.scroll.id == root2 .. '/folder' and changes[#changes].snapshot.scroll.offset == 3)
assert(search_runs == #changes)
local b1 = vim.fn.bufadd(root2 .. '/folder/one.txt'); vim.fn.bufload(b1)
controller:on_buf_enter(b1)
assert(vim.wait(3000, function() return changes[#changes].snapshot.selected == root2 .. '/folder/one.txt' end, 10))
assert(changes[#changes].snapshot.selected == root2 .. '/folder/one.txt')
local before = #changes
controller:on_buf_enter(b1)
assert(#changes == before, 'reopen does not force reveal')
controller:suppress_open(root2 .. '/folder/two.txt')
local b2 = vim.fn.bufadd(root2 .. '/folder/two.txt'); vim.fn.bufload(b2)
controller:on_buf_enter(b2)
assert(#changes == before, 'own open is suppressed')
controller:on_buf_enter(b1)
controller:on_buf_enter(b2)
assert(vim.wait(3000, function() return changes[#changes].snapshot.selected == root2 .. '/folder/two.txt' end, 10))
assert(changes[#changes].snapshot.selected == root2 .. '/folder/two.txt')
local hiddenbuf = vim.fn.bufadd(root2 .. '/.hidden'); vim.fn.bufload(hiddenbuf)
before = #changes; controller:on_buf_enter(hiddenbuf); assert(#changes == before)
local outside = vim.fn.bufadd(vim.fn.tempname()); vim.fn.bufload(outside)
controller:on_buf_enter(outside); assert(#changes == before)
controller:close()
vim.fn.delete(root2, 'rf')
print('native controller ok')

local real_root = Tree.normalize(vim.fn.tempname())
vim.fn.mkdir(real_root, 'p')
local seen = 0
local real = Watch.new({invalidate=function(dirs)
  if vim.in_fast_event() then error('invalidate ran in libuv callback') end
  if dirs[1] == real_root then seen = seen + 1 end
end})
real:set({real_root})
vim.fn.writefile({'event'}, real_root .. '/created')
assert(vim.wait(3000, function() return seen > 0 end, 10), 'real fs_event delivered bounded refresh')
real:close()
vim.fn.delete(real_root, 'rf')
print('real fs_event ok')

local race_root = Tree.normalize(vim.fn.tempname())
vim.fn.mkdir(race_root .. '/dir', 'p')
vim.fn.writefile({'a'}, race_root .. '/dir/a')
vim.fn.writefile({'b'}, race_root .. '/dir/b')
local queued, race_changes = {}, {}
local function race_scan(path, done)
  queued[#queued + 1] = {path=path, done=done}
end
local function drain()
  local count = 0
  while #queued > 0 do
    count = count + 1; assert(count < 30, 'scan loop')
    local item = table.remove(queued, 1)
    if item.path == race_root then item.done(nil, {{name='dir',kind='dir'}})
    else item.done(nil, {{name='a',kind='file'}, {name='b',kind='file'}}) end
  end
end
local race_tree = Tree.new(race_root, {async=true, scan=race_scan})
local race = Controller.new({root=race_root, tree=race_tree, autocmd=false,
  watch={set=function() end,close=function() end},
  on_change=function(_, snapshot) race_changes[#race_changes+1]=snapshot.selected end})
race:refresh(); drain()
local abuf = vim.fn.bufadd(race_root .. '/dir/a')
local bbuf = vim.fn.bufadd(race_root .. '/dir/b')
race:on_buf_enter(abuf)
race:refresh({race_root})
drain()
assert(race_changes[#race_changes] == race_root .. '/dir/a', 'watch refresh preserves in-flight reveal')
assert(#queued == 0)
race:on_buf_enter(bbuf)
race:refresh({race_root})
race:on_buf_enter(abuf)
drain()
assert(race_changes[#race_changes] == race_root .. '/dir/a', 'newer file wins over stale reveal')
race:on_buf_enter(bbuf)
race:refresh({race_root})
local outside_file = vim.fn.tempname()
vim.fn.writefile({'outside'}, outside_file)
local outside_buf = vim.fn.bufadd(outside_file)
local before_outside = #race_changes
race:on_buf_enter(outside_buf); drain()
assert(race_changes[#race_changes] == race_root .. '/dir/a', 'outside file cancels pending reveal without changing selection')
assert(#race_changes >= before_outside, 'structural refresh may still publish')
race:on_buf_enter(bbuf)
race:refresh({race_root})
local before_close = #race_changes
race:close(); drain()
assert(#race_changes == before_close, 'close prevents late reveal')
vim.fn.delete(race_root, 'rf')
vim.fn.delete(outside_file)
print('controlled reveal race ok')
