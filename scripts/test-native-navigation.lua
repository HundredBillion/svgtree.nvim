vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.env.SVGTREE_API_CHECKOUT or (vim.fn.getcwd() .. '/../native-explorer-api')
if vim.fn.filereadable(api .. '/lua/sprite/input.lua') == 0 then print('native navigation skipped (Sprite input unavailable)'); return end
package.path = api .. '/lua/?.lua;' .. package.path
local Tree = require('svgtree.tree')
local Controller = require('svgtree.native_controller')
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/dir/sub', 'p')
vim.fn.writefile({'x'}, root .. '/alpha.txt')
vim.fn.writefile({'x'}, root .. '/dir/sub/Bravo.txt')
vim.fn.writefile({'x'}, root .. '/dir/sub/.hidden')
local changes, opens, focuses = {}, {}, 0
local active = true
local c = Controller.new({root=root, tree=Tree.new(root,{async=false,show_hidden=false}), autocmd=false,
  watch={set=function() end,close=function() end},
  on_change=function(rows,snapshot) changes[#changes+1]={rows=rows,snapshot=snapshot} end,
  on_open=function(path) opens[#opens+1]=path end, on_editor_focus=function() focuses=focuses+1 end,
  is_active=function() return active end})
local function key(k,t,now) return c:handle({type='input',key=k,text=t},now or 0) end
c:refresh()
assert(#c.rows==2)
assert(c.snapshot.selected==root..'/dir/sub')
active=false; key('j','j'); assert(c.snapshot.selected==root..'/dir/sub')
active=true; key('j','j'); assert(c.snapshot.selected==root..'/alpha.txt')
key('enter','\n'); assert(opens[1]==root..'/alpha.txt')
key('k','k'); key('l','l'); assert(c.tree:is_expanded(root..'/dir/sub'))
assert(c.snapshot.expanded[root..'/dir/sub'])
assert(#c.rows==3 and c.rows[2].id==root..'/dir/sub/Bravo.txt')
key('j','j'); key('h','h'); assert(c.snapshot.selected==root..'/dir/sub')
key('h','h'); assert(not c.tree:is_expanded(root..'/dir/sub'))
key('ctrl-w',nil); key('l','l'); assert(focuses==1)
key('slash','/'); assert(c.search.active and c.snapshot.search.query=='')
key('b','B'); assert(c.snapshot.search.query=='B' and c.snapshot.search.count==1, vim.inspect(c.snapshot.search))
key('backspace',nil); assert(c.snapshot.search.query=='')
c:handle({type='paste',text='Bra\nvo'},1)
assert(c.snapshot.search.query=='Bra vo')
key('escape',nil); assert(not c.search.active and not c.closed)
key('slash','/'); key('b','B'); key('r','r'); key('enter','\n')
assert(not c.search.active and c.snapshot.search.query=='Br' and #opens==1)
key('l','l'); key('n','n'); assert(c.snapshot.selected==root..'/dir/sub/Bravo.txt')
key('N','N'); assert(c.snapshot.selected==root..'/dir/sub/Bravo.txt')
key('slash','/'); key('enter','\n'); assert(c.snapshot.search.query=='Br')
key('slash','/'); c:handle({type='paste',text='é漢'},2); key('backspace',nil)
assert(c.snapshot.search.query=='é'); key('escape',nil)
c:refresh(); assert(c.snapshot.search.query=='Br' and c.snapshot.search.count==1)
key('q','q'); assert(c.closed)
vim.fn.delete(root,'rf')
print('native navigation ok')
