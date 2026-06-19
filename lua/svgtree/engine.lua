-- The placement engine: keeps a rasterized icon image welded to a buffer line,
-- repositioning it on scroll/resize via vim.ui.img. This is the host-agnostic
-- core — svgtree's own tree and the neo-tree/snacks adapters all drive it the
-- same way. A host supplies four things through `attach`:
--   * win, buf            — where to draw
--   * resolve(line)        — for a (1-indexed) buffer line, the icon to show
--                            and the byte column it anchors to, or nil
--   * events (optional)    — autocmds that should trigger a reconcile
--
-- Each attachment owns its own image ids and augroup, so several engines can
-- coexist (e.g. svgtree's tree and a snacks explorer in another window) without
-- culling each other's images.

local config = require('svgtree.config')
local raster = require('svgtree.raster')

local M = {}

-- `_supported` is a *blocking terminal round-trip* that pumps the event loop.
-- It must NEVER run inside a host's render path (e.g. snacks calls our
-- formatter mid-render with the buffer temporarily modifiable; pumping the
-- loop there lets another render reset `modifiable` and corrupts the write).
-- So we probe exactly once, off the hot path, and everything else reads the
-- cached boolean.
local supported_cache = nil

---Probe (once) whether real-image rendering is available, and cache it.
---Call this from a safe context (startup/idle), NOT from a render callback.
---@return boolean
function M.supported()
  if supported_cache ~= nil then
    return supported_cache
  end
  local ok, res = pcall(function()
    return vim.ui.img ~= nil and vim.ui.img._supported({ timeout = 800 }) == true
  end)
  supported_cache = (ok and res and raster.has_converter()) or false
  return supported_cache
end

---Non-blocking read of the cached support result. Returns false until
---`supported()` has been called once. Safe to call from any hot path.
---@return boolean
function M.supported_cached()
  return supported_cache == true
end

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
  local events = opts.events or { 'WinScrolled', 'CursorMoved' }
  -- Keyed by STABLE ITEM IDENTITY (resolve's `key`, e.g. a path), NOT by line.
  -- Hosts like snacks "scroll" by rewriting buffer lines in place, so a given
  -- line holds different items over time. Keying by identity means a scroll
  -- just *repositions* each still-visible image (vim.ui.img.set(id,…) hits the
  -- terminal's flicker-free update path — no byte re-transmit); only items
  -- entering/leaving the viewport are created/deleted.
  local shown = {} ---@type table<string, { id:integer, stem:string }>
  local function del_all()
    for key, cur in pairs(shown) do
      pcall(vim.ui.img.del, cur.id)
      shown[key] = nil
    end
  end
  local grp = vim.api.nvim_create_augroup(opts.name or ('svgtree_engine_' .. opts.buf), { clear = true })
  local queued = false

  local handle = {}

  local function valid()
    return vim.api.nvim_win_is_valid(opts.win) and vim.api.nvim_buf_is_valid(opts.buf)
  end

  local function reconcile()
    if not valid() then
      return
    end
    local win = opts.win
    local top = vim.fn.line('w0', win)
    local bot = vim.fn.line('w$', win)

    -- Place/move icons whose anchor cell is actually on screen. screenpos()
    -- returns row==0 when the cell is off-screen — vertically (scrolled past)
    -- OR horizontally — so it doubles as our cull test on both axes.
    local want = {}
    for line = top, bot do
      local spec = opts.resolve(line)
      if spec and spec.stem then
        local pos = vim.fn.screenpos(win, line, spec.col)
        if pos.row > 0 then
          local key = spec.key or ('#' .. line)
          want[key] = true
          local cur = shown[key]
          if cur and cur.stem == spec.stem then
            -- Same item still visible: cheap reposition (no byte re-transmit).
            vim.ui.img.set(cur.id, { row = pos.row, col = pos.col })
          else
            -- New item, or same item whose icon changed (e.g. folder open):
            -- (re)create. This only happens at the viewport edges on scroll.
            if cur then
              vim.ui.img.del(cur.id)
              shown[key] = nil
            end
            local bytes = raster.png_bytes(spec.stem) or raster.png_bytes('file')
            if bytes then
              local id = vim.ui.img.set(bytes, {
                row = pos.row,
                col = pos.col,
                width = icon.width,
                height = icon.height,
                zindex = icon.zindex,
              })
              shown[key] = { id = id, stem = spec.stem }
            end
          end
        end
      end
    end

    for key, cur in pairs(shown) do
      if not want[key] then
        vim.ui.img.del(cur.id)
        shown[key] = nil
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
  -- On resize we only *reposition*, never clear+recreate. A width change can't
  -- move an icon's anchor column (icons live at a fixed byte column, near the
  -- left edge), so reconcile recomputes screenpos and nudges each still-visible
  -- image via the cheap flicker-free update path. Clearing here (del all +
  -- re-transmit bytes) made every icon flash during a continuous edge-drag,
  -- since WinResized fires once per drag step.
  vim.api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, {
    group = grp,
    callback = schedule,
  })
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
