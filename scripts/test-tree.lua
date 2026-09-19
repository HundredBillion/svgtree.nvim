-- Headless checks for svgtree.tree (directory model: sort, flatten, toggle).
-- Builds a temp fixture dir, so it touches the filesystem but stays
-- deterministic. Run via scripts/test.sh.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require('svgtree.config').setup({})
local Tree = require('svgtree.tree')

local fails = 0
local function check(c, m)
  if c then print('  ok  ' .. m) else print('  FAIL ' .. m); fails = fails + 1 end
end

-- ---- fixture: dirs + files + hidden entries, mixed case ----
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/alpha', 'p')
vim.fn.mkdir(root .. '/Beta', 'p') -- capital B: exercises case-insensitive sort
vim.fn.mkdir(root .. '/.hidden_dir', 'p')
vim.fn.writefile({}, root .. '/alpha/nested.txt')
vim.fn.writefile({}, root .. '/apple.txt')
vim.fn.writefile({}, root .. '/zebra.txt')
vim.fn.writefile({}, root .. '/.secret')

local t = Tree.new(root)

-- ---- flatten at root: dirs first, case-insensitive alpha; hidden included ----
local nodes = t:flatten()
local names = vim.tbl_map(function(n)
  return n.name
end, nodes)
check(#nodes == 6, 'root has 6 visible entries, got ' .. #nodes)
check(
  table.concat(names, ',') == '.hidden_dir,alpha,Beta,.secret,apple.txt,zebra.txt',
  'dirs-first then case-insensitive alpha: ' .. table.concat(names, ',')
)
check(nodes[1].kind == 'dir' and nodes[3].kind == 'dir', 'first three entries are dirs')
check(nodes[4].kind == 'file' and nodes[6].kind == 'file', 'last three entries are files')
check(nodes[1].depth == 0, 'top-level depth is 0')

local leaked_hidden = false
for _, n in ipairs(nodes) do
  if n.name:sub(1, 1) == '.' then
    leaked_hidden = true
  end
end
check(leaked_hidden, 'dotfiles/dirs included by default')

-- ---- toggle expand: child appears at depth+1 immediately after its dir ----
local alpha = nodes[2].path
check(t:is_expanded(alpha) == false, 'alpha starts collapsed')
t:toggle(alpha)
check(t:is_expanded(alpha) == true, 'alpha expanded after toggle')

local exp = t:flatten()
local en = vim.tbl_map(function(n)
  return n.name
end, exp)
check(
  table.concat(en, ',') == '.hidden_dir,alpha,nested.txt,Beta,.secret,apple.txt,zebra.txt',
  'expanded child nests under alpha at depth 1: ' .. table.concat(en, ',')
)
check(exp[3].name == 'nested.txt' and exp[3].depth == 1, 'nested.txt is depth 1')

-- ---- toggle again collapses back ----
t:toggle(alpha)
check(t:is_expanded(alpha) == false, 'alpha collapsed after second toggle')
check(#t:flatten() == 6, 'collapsed back to 6 entries')


-- Explicit filtering and deterministic ties share the same terminal scan.
vim.fn.writefile({}, root .. '/Case.txt')
vim.fn.writefile({}, root .. '/case.txt')
vim.fn.writefile({}, root .. '/雪.txt')
local hidden_off = Tree.new(root .. '/', {show_hidden = false})
local filtered = hidden_off:flatten()
local filtered_names = vim.tbl_map(function(n) return n.name end, filtered)
check(table.concat(filtered_names, ',') == 'alpha,Beta,apple.txt,Case.txt,case.txt,zebra.txt,雪.txt',
  'explicit false filters hidden and resolves folded ties')
check(Tree.new(root, {show_hidden = true}):flatten()[1].name == '.hidden_dir', 'explicit true includes hidden')
check(Tree.new('/').root == '/', 'filesystem root survives normalization')
check(Tree.new(root .. '/alpha/../').root == root, 'trailing separator and dot segments normalize')
check(filtered[#filtered].name == '雪.txt', 'Unicode basename stays intact')
local uv = vim.uv
uv.fs_symlink(root, root .. '/alpha/cycle')
uv.fs_symlink(root .. '/alpha', root .. '/alias')
local links = Tree.new(root, {show_hidden = false})
local link_nodes = links:flatten()
local alias, alpha_path
for _, node in ipairs(link_nodes) do
  if node.name == 'alias' then alias = node end
  if node.name == 'alpha' then alpha_path = node.path end
end
check(alias and alias.kind == 'dir', 'symlink to directory is directory')
links:toggle(alias.path)
local alias_rows = links:flatten()
local cycle_node
for _, node in ipairs(alias_rows) do
  if node.name == 'cycle' then cycle_node = node end
end
check(cycle_node and cycle_node.cycle and cycle_node.status == 'cycle', 'ancestor symlink cycle is bounded')
links:toggle(cycle_node.path)
check(#links:flatten() == #alias_rows, 'cycle expansion cannot recurse')
local root_link = root .. '-root-link'
uv.fs_symlink(root, root_link)
local linked_root = Tree.new(root_link, {show_hidden = false})
check(linked_root.root == root_link and linked_root:flatten()[1].path:sub(1, #root_link) == root_link,
  'symlink root keeps display identity')
vim.fn.delete(root_link)

vim.fn.delete(root, 'rf')

if fails > 0 then print('FAILED: ' .. fails); os.exit(1) else print('test-tree: ALL PASS') end
