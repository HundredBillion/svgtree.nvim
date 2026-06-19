-- The view: owns the tree window/buffer, renders node lines, and keeps an
-- image icon welded to each visible line via the anchoring shim
-- (extmark-free variant: line<->buffer-row is stable between rebuilds, so we
-- reconcile by visible range and reposition with vim.ui.img on scroll).

local config = require('svgtree.config')
local icons = require('svgtree.icons')
local raster = require('svgtree.raster')
local Tree = require('svgtree.tree')

local M = {}

---@type { buf:integer, win:integer, prev_win:integer, tree:svgtree.Tree, nodes:svgtree.Node[], shown:table<integer,integer>, grp:integer, images:boolean }|nil
local view = nil

local function graphics_ok()
  local ok = pcall(function()
    return vim.ui.img and vim.ui.img._supported({ timeout = 800 })
  end)
  return ok and vim.ui.img._supported({ timeout = 800 }) and raster.has_converter()
end

-- byte column (1-indexed) where the icon sits for a given depth
local function icon_col(depth)
  return depth * config.options.indent + 1
end

-- Build buffer text from the flattened node list.
local function render_lines()
  local opts = config.options
  local lines = {}
  for _, node in ipairs(view.nodes) do
    local indent = string.rep(' ', node.depth * opts.indent)
    local slot = string.rep(' ', opts.icon.width) .. ' ' -- reserved for the image
    local suffix = node.kind == 'dir' and '/' or ''
    -- When images are off, show the icon stem as a text tag so it's still usable.
    local tag = ''
    if not view.images and opts.fallback_text then
      tag = '[' .. icons.stem(node.name, node.kind, { open = view.tree:is_expanded(node.path) }) .. '] '
    end
    lines[#lines + 1] = indent .. slot .. tag .. node.name .. suffix
  end
  vim.bo[view.buf].modifiable = true
  vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
  vim.bo[view.buf].modifiable = false
end

-- Position/refresh images for currently-visible lines only.
local function reconcile()
  if not view or not view.images or not vim.api.nvim_win_is_valid(view.win) then
    return
  end
  local win, buf = view.win, view.buf
  local top = vim.fn.line('w0', win)
  local bot = vim.fn.line('w$', win)
  local icfg = config.options.icon

  -- Drop icons scrolled out of view.
  for line, id in pairs(view.shown) do
    if line < top or line > bot then
      vim.ui.img.del(id)
      view.shown[line] = nil
    end
  end

  -- Place/move icons for visible lines.
  for line = top, bot do
    local node = view.nodes[line]
    if node then
      local pos = vim.fn.screenpos(win, line, icon_col(node.depth))
      if pos.row > 0 then
        local id = view.shown[line]
        if id then
          vim.ui.img.set(id, { row = pos.row, col = pos.col })
        else
          local stem = icons.stem(node.name, node.kind, { open = view.tree:is_expanded(node.path) })
          local bytes = raster.png_bytes(stem) or raster.png_bytes('file')
          if bytes then
            view.shown[line] = vim.ui.img.set(bytes, {
              row = pos.row,
              col = pos.col,
              width = icfg.width,
              height = icfg.height,
              zindex = icfg.zindex,
            })
          end
        end
      end
    end
  end
end

local queued = false
local function schedule_reconcile()
  if queued then
    return
  end
  queued = true
  vim.schedule(function()
    queued = false
    reconcile()
  end)
end

-- Clear all images and the shown map (used before a structural rebuild).
local function clear_images()
  if vim.ui.img then
    vim.ui.img.del(math.huge)
  end
  if view then
    view.shown = {}
  end
end

-- Full rebuild after a structural change (expand/collapse/refresh).
local function rebuild()
  view.nodes = view.tree:flatten()
  render_lines()
  clear_images()
  schedule_reconcile()
end

local function close()
  if not view then
    return
  end
  pcall(vim.api.nvim_del_augroup_by_id, view.grp)
  clear_images()
  if vim.api.nvim_win_is_valid(view.win) then
    vim.api.nvim_win_close(view.win, true)
  end
  view = nil
end

-- Open the file/dir under the cursor.
local function on_enter()
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
  local line = vim.api.nvim_win_get_cursor(view.win)[1]
  local node = view.nodes[line]
  if node and node.kind == 'dir' and view.tree:is_expanded(node.path) then
    view.tree:toggle(node.path)
    rebuild()
  end
end

local function map(lhs, fn)
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
    shown = {},
    grp = grp,
    images = graphics_ok(),
  }

  -- Keymaps.
  map('<CR>', on_enter)
  map('l', on_enter)
  map('h', on_collapse)
  map('R', rebuild)
  map('q', close)

  -- Reconcile on anything that can move lines on screen.
  vim.api.nvim_create_autocmd({ 'WinScrolled', 'CursorMoved', 'VimResized', 'WinResized' }, {
    group = grp,
    buffer = buf,
    callback = schedule_reconcile,
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
