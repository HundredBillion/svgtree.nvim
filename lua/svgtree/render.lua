-- The view: owns the tree window/buffer, renders node lines, and welds an SVG
-- image icon to each line via the shared placement engine (svgtree.engine, which
-- uses kitty Unicode placeholders). Because each icon is ordinary buffer text it
-- scrolls with its line and repaints on redraw for free; the view only rebuilds
-- the text and calls the engine to re-place icons after a structural change.

local config = require('svgtree.config')
local engine = require('svgtree.engine')
local capability = require('svgtree.capability')
local icons = require('svgtree.icons')
local Tree = require('svgtree.tree')
local winlock = require('svgtree.winlock')
local text = require('svgtree.text')

local M = {}

---@type { buf:integer, win:integer, prev_win:integer, tree:svgtree.Tree, nodes:svgtree.Node[], engine?:svgtree.engine.Handle, grp:integer, images:boolean }|nil
local view = nil

-- byte column (1-indexed) where the icon sits for a given depth
local function icon_col(depth)
  return depth * config.options.indent + 1
end

-- Build buffer text from the flattened node list, truncating names that would
-- overflow the window so no line is wider than the view (hence no horizontal
-- scrolling).
local function render_lines()
  if not view then
    return
  end
  local opts = config.options
  local width = vim.api.nvim_win_is_valid(view.win) and vim.api.nvim_win_get_width(view.win)
    or opts.window.width
  local lines = {}
  for _, node in ipairs(view.nodes) do
    local indent = string.rep(' ', node.depth * opts.indent)
    local slot = string.rep(' ', opts.icon.width) .. ' ' -- reserved for the image
    -- When images are off, show the icon id as a text tag so it's still usable.
    -- A nil id (theme maps this entry to no icon) yields no tag.
    local tag = ''
    if not view.images and opts.fallback_text then
      local s = icons.stem(node.name, node.kind, { open = view.tree:is_expanded(node.path) })
      if s then
        tag = '[' .. s .. '] '
      end
    end
    local prefix = indent .. slot .. tag
    local suffix = node.kind == 'dir' and '/' or ''
    -- Budget the name to what's left of the window (1-cell right margin).
    local budget = width - vim.fn.strdisplaywidth(prefix) - 1
    lines[#lines + 1] = prefix .. text.truncate(node.name .. suffix, budget)
  end
  vim.bo[view.buf].modifiable = true
  vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
  vim.bo[view.buf].modifiable = false
end

-- Full rebuild after a structural change (expand/collapse/refresh): the node
-- list changed, so re-render text and drop/replace every image.
local function rebuild()
  if not view then
    return
  end
  view.nodes = view.tree:flatten()
  render_lines()
  if view.engine then
    view.engine.refresh()
  end
end

-- Re-render text (re-truncate to the new width) without re-scanning the tree.
-- Used on window/editor resize; the engine re-places images on its own.
local function relayout()
  if not view then
    return
  end
  render_lines()
end

local function close()
  if not view then
    return
  end
  pcall(vim.api.nvim_del_augroup_by_id, view.grp)
  if view.engine then
    view.engine.detach()
  end
  if vim.api.nvim_win_is_valid(view.win) then
    vim.api.nvim_win_close(view.win, true)
  end
  view = nil
end

-- Open the file/dir under the cursor.
local function on_enter()
  if not view then
    return
  end
  local line = vim.api.nvim_win_get_cursor(view.win)[1]
  local node = view.nodes[line]
  if not node then
    return
  end
  if node.kind == 'dir' then
    view.tree:toggle(node.path)
    rebuild()
  else
    local target = view.prev_win
    if not (target and vim.api.nvim_win_is_valid(target)) then
      vim.cmd('wincmd l')
      target = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_set_current_win(target)
    vim.cmd('edit ' .. vim.fn.fnameescape(node.path))
  end
end

local function on_collapse()
  if not view then
    return
  end
  local line = vim.api.nvim_win_get_cursor(view.win)[1]
  local node = view.nodes[line]
  if node and node.kind == 'dir' and view.tree:is_expanded(node.path) then
    view.tree:toggle(node.path)
    rebuild()
  end
end

local function map(lhs, fn)
  if not view then
    return
  end
  vim.keymap.set('n', lhs, fn, { buffer = view.buf, nowait = true, silent = true })
end

---@param root? string defaults to cwd
function M.open(root)
  if view then
    close()
  end
  root = root or vim.uv.cwd()

  local prev_win = vim.api.nvim_get_current_win()
  local cmd = config.options.window.side == 'right' and 'botright vsplit' or 'topleft vsplit'
  vim.cmd(cmd)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, config.options.window.width)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(win, buf)

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'svgtree'
  for opt, val in pairs({
    number = false,
    relativenumber = false,
    signcolumn = 'no',
    wrap = false,
    cursorline = true,
    foldcolumn = '0',
    list = false,
  }) do
    vim.wo[win][opt] = val
  end

  local grp = vim.api.nvim_create_augroup('svgtree_view', { clear = true })

  view = {
    buf = buf,
    win = win,
    prev_win = prev_win,
    tree = Tree.new(root),
    nodes = {},
    grp = grp,
    images = capability.supported(),
  }

  -- Weld an icon to each visible line via the shared placement engine. It
  -- owns its own augroup and self-binds scroll/resize, so render.lua only
  -- needs to call refresh() after a structural change (expand/collapse).
  if view.images then
    view.engine = engine.attach({
      win = win,
      buf = buf,
      name = 'svgtree_view_engine',
      resolve = function(line)
        local node = view and view.nodes[line]
        if not node then
          return nil
        end
        return {
          col = icon_col(node.depth),
          stem = icons.stem(node.name, node.kind, { open = view.tree:is_expanded(node.path) }),
          key = node.path,
        }
      end,
    })
  end

  -- Keymaps.
  map('<CR>', on_enter)
  map('l', on_enter)
  map('h', on_collapse)
  map('R', rebuild)
  map('q', close)

  -- A file tree never pans sideways. One shared seam locks horizontal scroll
  -- (keymaps + a leftcol-snap on view.grp, torn down with the view on close).
  winlock.lock_horizontal(win, buf, grp)

  -- On resize, the window width changed: re-truncate names. (The engine
  -- re-places images on its own resize handler.)
  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, {
    group = grp,
    callback = relayout,
  })
  -- Tear down if the window goes away.
  vim.api.nvim_create_autocmd({ 'WinClosed' }, {
    group = grp,
    callback = function(args)
      if view and tonumber(args.match) == view.win then
        close()
      end
    end,
  })

  rebuild()
  vim.api.nvim_set_current_win(win)
end

M.close = close

function M.toggle(root)
  if view then
    close()
  else
    M.open(root)
  end
end

return M
