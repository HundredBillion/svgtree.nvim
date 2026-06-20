-- The placement engine: welds a rasterized icon to a buffer line using the
-- kitty Unicode-placeholder protocol (see svgtree.kitty). Each icon's PNG is
-- transmitted once and given a virtual placement; the icon is then drawn by
-- writing placeholder cells (U+10EEEE) into the line as an overlay extmark.
-- Because the anchor is ordinary buffer text, the icon scrolls with its line
-- and is repainted by the terminal on every redraw — for free. This is the
-- host-agnostic core — svgtree's own tree and the neo-tree/snacks adapters all
-- drive it the same way. A host supplies through `attach`:
--   * win, buf            — where to draw
--   * resolve(line)        — for a (1-indexed) buffer line, the icon to show
--                            and the byte column it anchors to, or nil
--   * events (optional)    — autocmds that should trigger a reconcile
--
-- Each attachment owns its own image ids, extmark namespace, and augroup, so
-- several engines can coexist (e.g. svgtree's tree and a snacks explorer)
-- without disturbing each other. Re-attaching re-transmits, so reopening a
-- view is a clean recovery path if the terminal ever drops image bytes.

local config = require('svgtree.config')
local raster = require('svgtree.raster')
local kitty = require('svgtree.kitty')

local M = {}

---@class svgtree.engine.Spec
---@field stem string icon stem (resolves to <pack>/<stem>.svg)
---@field col integer 1-indexed *byte* column the icon anchors to
---@field key? string stable item identity (e.g. a path) for reuse across
---  scroll/redraw; falls back to the line number when omitted

---@class svgtree.engine.Opts
---@field win integer window handle to draw in
---@field buf integer buffer the lines live in
---@field resolve fun(line:integer):svgtree.engine.Spec? per-line icon resolver
---@field icon? { width:integer, height:integer, size_px:integer, zindex:integer }
---@field events? string[] buffer-scoped autocmds that trigger a reconcile
---@field name? string augroup name (must be unique per attachment)

---@class svgtree.engine.Handle
---@field reconcile fun() place/move/cull images for the current view (sync)
---@field schedule fun() debounced reconcile (coalesces a burst into one pass)
---@field refresh fun() drop all images, then reschedule (after a structural change)
---@field clear fun() drop all images this engine owns
---@field detach fun() clear images and remove autocmds

---Attach the engine to a window/buffer.
---@param opts svgtree.engine.Opts
---@return svgtree.engine.Handle
function M.attach(opts)
  local icon = opts.icon or config.options.icon
  local events = opts.events or { 'CursorMoved' }
  local name = opts.name or ('svgtree_engine_' .. opts.buf)
  -- One namespace holds all our placeholder extmarks; one augroup, our autocmds.
  local ns = vim.api.nvim_create_namespace(name)
  local grp = vim.api.nvim_create_augroup(name, { clear = true })
  -- stem -> { id, pid }: each unique icon is transmitted and given a virtual
  -- placement exactly once per attachment. Placeholder cells reference it by id,
  -- so one transmit paints the icon on every line that shows it. A fresh attach
  -- builds a fresh table and re-transmits — the reopen recovery path.
  local imgs = {} ---@type table<string, { id:integer, pid:integer }>
  local queued = false

  local handle = {}

  local function valid()
    return vim.api.nvim_win_is_valid(opts.win) and vim.api.nvim_buf_is_valid(opts.buf)
  end

  -- Transmit + virtually-place an icon stem once; cache and reuse its ids.
  ---@param stem string
  ---@return { id:integer, pid:integer }?
  local function image_for(stem)
    local rec = imgs[stem]
    if rec then
      return rec
    end
    -- Runtime fallback: the active theme's own default-file id, not a literal
    -- 'file' (which may not exist in this theme). nil if the theme defines none.
    local default_file = config.options.resolved and config.options.resolved.theme.file
    local png = raster.png_path(stem) or (default_file and raster.png_path(default_file)) or nil
    if not png then
      return nil
    end
    local id = kitty.transmit(png)
    local pid = kitty.place(id, icon.width, icon.height)
    rec = { id = id, pid = pid }
    imgs[stem] = rec
    return rec
  end

  -- Remove every placeholder extmark and free each transmitted image. Ids are
  -- unique to this attachment, so deleting them can't disturb another engine.
  local function del_all()
    if vim.api.nvim_buf_is_valid(opts.buf) then
      vim.api.nvim_buf_clear_namespace(opts.buf, ns, 0, -1)
    end
    for stem, rec in pairs(imgs) do
      pcall(kitty.delete, rec.id)
      imgs[stem] = nil
    end
  end

  -- Re-anchor every visible icon. With placeholders there is no screen-position
  -- tracking, redraw-recovery, or startup-race retry (all of which the absolute
  -- engine needed and still couldn't make reliable on a cold open): we just
  -- clear our extmarks and re-emit one overlay per resolvable line. The terminal
  -- repaints from the buffer cells on its own. Cheap enough to run per redraw.
  local function reconcile()
    if not valid() then
      return
    end
    local buf = opts.buf
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    local line_count = vim.api.nvim_buf_line_count(buf)
    for line = 1, line_count do
      local spec = opts.resolve(line)
      if spec and spec.stem then
        local rec = image_for(spec.stem)
        if rec then
          -- 1-indexed byte column -> 0-indexed extmark column. Overlaying at the
          -- byte position lets Neovim compute the display column, so a multibyte
          -- tree-guide prefix can't misalign the icon.
          local col = math.max((spec.col or 1) - 1, 0)
          pcall(vim.api.nvim_buf_set_extmark, buf, ns, line - 1, col, {
            virt_text = kitty.virt_text(rec.id, rec.pid, icon.width, 1),
            virt_text_pos = 'overlay',
            hl_mode = 'combine',
            priority = icon.zindex or 50,
          })
        end
      end
    end
  end

  local function schedule()
    if queued then
      return
    end
    queued = true
    vim.schedule(function()
      queued = false
      reconcile()
    end)
  end

  function handle.reconcile()
    reconcile()
  end

  function handle.schedule()
    schedule()
  end

  function handle.clear()
    del_all()
  end

  function handle.refresh()
    handle.clear()
    schedule()
  end

  function handle.detach()
    pcall(vim.api.nvim_del_augroup_by_id, grp)
    handle.clear()
  end

  if #events > 0 then
    vim.api.nvim_create_autocmd(events, { group = grp, buffer = opts.buf, callback = schedule })
  end
  vim.api.nvim_create_autocmd({ 'WinClosed' }, {
    group = grp,
    callback = function(args)
      if tonumber(args.match) == opts.win then
        handle.detach()
      end
    end,
  })

  schedule()
  return handle
end

return M
