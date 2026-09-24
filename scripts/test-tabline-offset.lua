-- Headless checks for svgtree.tabline: the terminal tree is an ordinary window
-- at the editor's left edge, so bufferline.nvim must be told to offset its tabs
-- past it (Sprite's native Explorer sits outside Neovim's grid and never needs
-- this). Uses a stub bufferline.config, the module bufferline's offset.lua reads.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.env.TERM = 'xterm-ghostty'
vim.env.TERM_PROGRAM = 'ghostty'

local fails = 0
local function check(c, m)
  if c then print('  ok  ' .. m) else print('  FAIL ' .. m); fails = fails + 1 end
end

local function svgtree_offsets()
  local n = 0
  for _, o in ipairs(package.loaded['bufferline.config'].options.offsets or {}) do
    if o.filetype == 'svgtree' then n = n + 1 end
  end
  return n
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
vim.fn.writefile({ 'x' }, root .. '/one.lua')

local tree = require('svgtree')
tree.setup({ renderer = 'terminal' })

-- Tree opened while bufferline is not loaded: nothing is required or created.
tree.open(root)
check(package.loaded['bufferline.config'] == nil, 'does not load bufferline when it is absent')
tree.close()

-- Bufferline loaded (as LazyVim configures it) before the tree opens.
package.loaded['bufferline.config'] = { options = { offsets = { { filetype = 'neo-tree' } } } }
tree.open(root)
check(svgtree_offsets() == 1, 'opening the terminal tree registers a svgtree tab offset')
check(package.loaded['bufferline.config'].options.offsets[1].filetype == 'neo-tree',
  'keeps the offsets the user already had')
tree.close()
tree.open(root)
check(svgtree_offsets() == 1, 'reopening the tree does not duplicate the offset')

-- bufferline.setup() builds a fresh config and then sets 'tabline', e.g. when
-- lazy.nvim loads it after `nvim <dir>` already opened the tree.
package.loaded['bufferline.config'].options = { offsets = {} }
vim.o.tabline = '%!v:lua.nvim_bufferline()'
check(svgtree_offsets() == 1, 'restores the offset after bufferline re-runs its setup')

-- A user's own svgtree offset (custom text/highlight) wins over the default.
package.loaded['bufferline.config'].options = { offsets = { { filetype = 'svgtree', text = 'Files' } } }
vim.o.tabline = '%!v:lua.nvim_bufferline()'
check(svgtree_offsets() == 1, 'leaves a user-defined svgtree offset alone')

-- Offsets absent altogether (hand-built config): the list is created.
package.loaded['bufferline.config'].options = {}
vim.o.tabline = '%!v:lua.nvim_bufferline()'
check(svgtree_offsets() == 1, 'creates the offsets list when bufferline has none')

if fails > 0 then print(fails .. ' failure(s)'); os.exit(1) end
print('all tabline offset checks passed')
