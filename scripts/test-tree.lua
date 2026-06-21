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

-- ---- flatten at root: dirs first, case-insensitive alpha; hidden excluded ----
local nodes = t:flatten()
local names = vim.tbl_map(function(n)
  return n.name
end, nodes)
check(#nodes == 4, 'root has 4 visible entries (hidden excluded), got ' .. #nodes)
check(
  table.concat(names, ',') == 'alpha,Beta,apple.txt,zebra.txt',
  'dirs-first then case-insensitive alpha: ' .. table.concat(names, ',')
)
check(nodes[1].kind == 'dir' and nodes[2].kind == 'dir', 'first two entries are dirs')
check(nodes[3].kind == 'file' and nodes[4].kind == 'file', 'last two entries are files')
check(nodes[1].depth == 0, 'top-level depth is 0')

local leaked_hidden = false
for _, n in ipairs(nodes) do
  if n.name:sub(1, 1) == '.' then
    leaked_hidden = true
  end
end
check(not leaked_hidden, 'dotfiles/dirs excluded by default')

-- ---- toggle expand: child appears at depth+1 immediately after its dir ----
local alpha = nodes[1].path
check(t:is_expanded(alpha) == false, 'alpha starts collapsed')
t:toggle(alpha)
check(t:is_expanded(alpha) == true, 'alpha expanded after toggle')

local exp = t:flatten()
local en = vim.tbl_map(function(n)
  return n.name
end, exp)
check(
  table.concat(en, ',') == 'alpha,nested.txt,Beta,apple.txt,zebra.txt',
  'expanded child nests under alpha at depth 1: ' .. table.concat(en, ',')
)
check(exp[2].name == 'nested.txt' and exp[2].depth == 1, 'nested.txt is depth 1')

-- ---- toggle again collapses back ----
t:toggle(alpha)
check(t:is_expanded(alpha) == false, 'alpha collapsed after second toggle')
check(#t:flatten() == 4, 'collapsed back to 4 entries')

vim.fn.delete(root, 'rf')

if fails > 0 then print('FAILED: ' .. fails); os.exit(1) else print('test-tree: ALL PASS') end
