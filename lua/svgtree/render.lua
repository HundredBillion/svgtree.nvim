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

-- Trim a string to a display-cell budget, appending '…' if it overflows
-- (VSCode-style). Width-aware, so multibyte names behave.
local function truncate(s, budget)
  if budget <= 0 then
    return ''
  end
  if vim.fn.strdisplaywidth(s) <= budget then
    return s
  end
  if budget == 1 then
    return '…'
  end
  local target = budget - 1 -- room for the ellipsis (1 cell)
  local n = vim.fn.strchars(s)
  local out = s
  while n > 0 and vim.fn.strdisplaywidth(out) > target do
    n = n - 1
    out = vim.fn.strcharpart(s, 0, n)
  end
  return out .. '…'
end

-- Build buffer text from the flattened node list, truncating names that would
-- overflow the window so no line is wider than the view (hence no horizontal
-- scrolling).
local function render_lines()
  local opts = config.options
  local width = vim.api.nvim_win_is_valid(view.win) and vim.api.nvim_win_get_width(view.win)
    or opts.window.width
  local lines = {}
  for _, node in ipairs(view.nodes) do
    local indent = string.rep(' ', node.depth * opts.indent)
    local slot = string.rep(' ', opts.icon.width) .. ' ' -- reserved for the image
    -- When images are off, show the icon stem as a text tag so it's still usable.
    local tag = ''
    if not view.images and opts.fallback_text then
      tag = '[' .. icons.stem(node.name, node.kind, { open = view.tree:is_expanded(node.path) }) .. '] '
    end
    local prefix = indent .. slot .. tag
    local suffix = node.kind == 'dir' and '/' or ''
    -- Budget the name to what's left of the window (1-cell right margin).
    local budget = width - vim.fn.strdisplaywidth(prefix) - 1
    lines[#lines + 1] = prefix .. truncate(node.name .. suffix, budget)
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
  local win = view.win
  local top = vim.fn.line('w0', win)
  local bot = vim.fn.line('w$', win)
  local icfg = config.options.icon

  -- Place/move icons whose anchor cell is actually on screen. screenpos()
  -- returns row==0 when the cell is off-screen — vertically (scrolled past) OR
  -- horizontally (anchor column scrolled off the left edge). Track exactly
  -- which lines are currently showable this pass.
  local want = {}
  for line = top, bot do
    local node = view.nodes[line]
    if node then
      local pos = vim.fn.screenpos(win, line, icon_col(node.depth))
      if pos.row > 0 then
        want[line] = true
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

  -- Cull anything shown that is no longer placeable (scrolled off either axis).
  for line, id in pairs(view.shown) do
    if not want[line] then
      vim.ui.img.del(id)
      view.shown[line] = nil
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

-- Re-render text (re-truncate to the new width) without re-scanning the tree.
-- Used on window/editor resize.
local function relayout()
  if not view then
    return
  end
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

  -- A file tree never pans sideways: neutralize the horizontal-scroll inputs
  -- (incl. Mac trackpad horizontal swipes -> ScrollWheelLeft/Right).
  for _, lhs in ipairs({
    'zh', 'zl', 'zH', 'zL',
    '<ScrollWheelLeft>', '<ScrollWheelRight>',
    '<S-ScrollWheelLeft>', '<S-ScrollWheelRight>',
  }) do
    map(lhs, '<Nop>')
  end

  -- Reposition icons on vertical scroll / cursor movement.
  vim.api.nvim_create_autocmd({ 'WinScrolled', 'CursorMoved' }, {
    group = grp,
    buffer = buf,
    callback = schedule_reconcile,
  })
  -- On resize, the window width changed: re-truncate names, then reposition.
  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, {
    group = grp,
    callback = relayout,
  })
  -- Safety net: if anything still pans the view sideways, snap it back.
  vim.api.nvim_create_autocmd('WinScrolled', {
    group = grp,
    buffer = buf,
    callback = function()
      if not (view and vim.api.nvim_win_is_valid(view.win)) then
        return
      end
      vim.api.nvim_win_call(view.win, function()
        local v = vim.fn.winsaveview()
        if v.leftcol and v.leftcol ~= 0 then
          v.leftcol = 0
          vim.fn.winrestview(v)
        end
      end)
    end,
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
