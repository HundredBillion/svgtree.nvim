vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.env.SVGTREE_API_CHECKOUT or (vim.fn.getcwd() .. '/../native-explorer-api')
if vim.fn.filereadable(api .. '/lua/sprite/input.lua') == 0 then print('native navigation skipped (Sprite input unavailable)'); return end
package.path = api .. '/lua/?.lua;' .. package.path
local Tree = require('svgtree.tree')
local Controller = require('svgtree.native_controller')
local State = require('svgtree.state')
local original_rows=State.rows
local row_projects,watch_sets=0,0
State.rows=function(...) row_projects=row_projects+1; return original_rows(...) end
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/dir/sub', 'p')
vim.fn.writefile({'x'}, root .. '/alpha.txt')
vim.fn.writefile({'x'}, root .. '/dir/sub/Bravo.txt')
vim.fn.writefile({'x'}, root .. '/dir/sub/.hidden')
local changes, opens, focuses, roots = {}, {}, 0, {}
local active = true
local c = Controller.new({root=root, tree=Tree.new(root,{async=false,show_hidden=false}), autocmd=false,
  watch={set=function() watch_sets=watch_sets+1 end,close=function() end},
  on_change=function(rows,snapshot,reveal) changes[#changes+1]={rows=rows,snapshot=snapshot,reveal=reveal} end,
  on_open=function(path) opens[#opens+1]=path end, on_editor_focus=function() focuses=focuses+1 end,
  on_root=function(path) roots[#roots+1]=path end,
  is_active=function() return active end})
local function key(k,t,now) return c:handle({type='input',key=k,text=t},now or 0) end
c:refresh()
local first_projects,first_watches=row_projects,watch_sets
key('j','j')
assert(row_projects==first_projects and watch_sets==first_watches,'selection must reuse structural projection and watchers')
key('slash','/')
key('a','a')
assert(row_projects==first_projects and watch_sets==first_watches,'search must reuse structural projection and watchers')
key('escape',nil)
assert(row_projects==first_projects and watch_sets==first_watches,'search cancel must reuse structure')
key('R','R')
assert(row_projects>first_projects and watch_sets>first_watches,'refresh must rebuild structure and watchers')
c.snapshot.selected=root..'/dir/sub'; c:publish()
assert(#c.rows==2)
assert(c.snapshot.selected==root..'/dir/sub')
active=false; key('j','j'); assert(c.snapshot.selected==root..'/dir/sub')
active=true; key('j','j'); assert(c.snapshot.selected==root..'/alpha.txt')
assert(changes[#changes].reveal==root..'/alpha.txt', 'movement requests reveal')
key('enter','\n'); assert(opens[1]==root..'/alpha.txt')
key('k','k'); key('l','l'); assert(c.tree:is_expanded(root..'/dir/sub'))
assert(c.snapshot.expanded[root..'/dir/sub'])
assert(#c.rows==3 and c.rows[2].id==root..'/dir/sub/Bravo.txt')
key('j','j'); key('h','h'); assert(c.snapshot.selected==root..'/dir/sub')
assert(changes[#changes].reveal==root..'/dir/sub', 'parent requests reveal')
key('.','.'); assert(roots[#roots]==root..'/dir/sub', 'dot focuses the selected directory')
c.snapshot.selected=root..'/alpha.txt'; key('.','.'); assert(roots[#roots]==root, 'dot focuses a selected file parent')
key('backspace',nil); assert(roots[#roots]==vim.fs.dirname(root), 'backspace moves the root upward')
c.snapshot.selected=root..'/dir/sub'
key('h','h'); assert(not c.tree:is_expanded(root..'/dir/sub'))
key('ctrl-w',nil); key('l','l'); assert(focuses==1)
key('ctrl-w',nil); key('ctrl-l',nil); assert(focuses==2, 'supports Neovim <C-l> window mapping')
key('ctrl-l',nil); assert(focuses==3, 'supports direct <C-l> native input')
key('slash','/'); assert(c.search.active and c.snapshot.search.query=='')
local before_search=c.snapshot.selected
key('enter','x'); assert(c.search.active and c.snapshot.search.query=='x')
key('escape','y'); assert(c.search.active and c.snapshot.search.query=='xy')
key('backspace','z'); assert(c.search.active and c.snapshot.search.query=='xyz')
key('backspace',nil); key('backspace',nil); key('backspace',nil)
assert(c.snapshot.search.query=='')
c:handle({type='input',key='a'},1); assert(c.snapshot.search.query=='a')
key('backspace',nil)
key('b','B'); assert(c.snapshot.search.query=='B' and c.snapshot.search.count==1, vim.inspect(c.snapshot.search))
key('backspace',nil); assert(c.snapshot.search.query=='')
c:handle({type='paste',text='Bra\nvo'},1)
assert(c.snapshot.search.query=='Bra vo')
key('escape',nil); assert(not c.search.active and not c.closed)
key('slash','/'); key('b','B'); key('r','r'); key('enter','\n')
assert(not c.search.active and c.snapshot.search.query=='Br' and #opens==1)
key('l','l')
local anchor=c.snapshot.selected
key('slash','/'); key('b','B'); key('r','r')
assert(c.snapshot.selected==root..'/dir/sub/Bravo.txt' and changes[#changes].reveal==root..'/dir/sub/Bravo.txt', 'typing reaches later visible match')
key('escape',nil); assert(c.snapshot.selected==anchor and changes[#changes].reveal==nil, 'cancel restores selection without scrolling')
key('n','n'); assert(c.snapshot.selected==root..'/dir/sub/Bravo.txt')
assert(changes[#changes].reveal==root..'/dir/sub/Bravo.txt')
key('N','N'); assert(c.snapshot.selected==root..'/dir/sub/Bravo.txt')
key('slash','/'); key('enter','\n'); assert(c.snapshot.search.query=='Br')
key('slash','/'); c:handle({type='paste',text='é漢'},2); key('backspace',nil)
assert(c.snapshot.search.query=='é'); key('escape',nil)
c:refresh(); assert(c.snapshot.search.query=='Br' and c.snapshot.search.count==1)
local collapsed_selected=c.snapshot.selected
local collapsed_opens=#opens
c.snapshot.root_collapsed=true
c:action('last'); c:action('enter'); c:action('parent')
assert(c.snapshot.selected==collapsed_selected and #opens==collapsed_opens, 'collapsed root ignores invisible row actions')
c.snapshot.root_collapsed=false
key('slash','/'); key('b','B'); key('r','r')
assert(c.snapshot.selected==root..'/dir/sub/Bravo.txt' and changes[#changes].reveal==root..'/dir/sub/Bravo.txt', 'typing selects and reveals match')
key('z','z'); assert(c.snapshot.search.count==0 and c.snapshot.selected==root..'/dir/sub/Bravo.txt', 'no matches keep selection')
key('escape',nil)
key('G','G'); assert(changes[#changes].reveal==c.snapshot.selected, 'last requests reveal')
key('q','q'); assert(c.closed)
vim.fn.delete(root,'rf')
State.rows=original_rows
print('native navigation ok')
