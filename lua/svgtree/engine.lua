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

-- Whether the terminal can render images (kitty graphics protocol).
--   nil   = not yet determined
--   true  = supported
--   false = unsupported / unavailable
-- Determining this means asking the terminal and reading its reply — a round
-- trip. vim.ui.img._supported() does that but BLOCKS on the answer via
-- vim.wait(), which pumps the event loop; running it during startup or inside
-- a render is unsafe. So our primary path is detect() below, which sends the
-- same query but resolves on the reply asynchronously — no blocking, safe to
-- fire at startup. supported() remains as a synchronous fallback.
local supported_cache = nil
local detecting = false

-- Callbacks to run once support is determined (true or false). Used by hosts
-- to hold their first render until they know whether to draw icons or glyphs.
local resolved_listeners = {}

local function fire_resolved()
  local ls = resolved_listeners
  resolved_listeners = {}
  for _, fn in ipairs(ls) do
    pcall(fn)
  end
end

local function resolve(val)
  if supported_cache == nil then
    supported_cache = val and raster.has_converter() and true or false
    detecting = false
    vim.schedule(fire_resolved)
  end
end

-- Mirror of vim.ui.img._kitty's query-id generator so our APC echo id is in the
-- same space the terminal expects.
local gen_query_id = (function()
  local bit = require('bit')
  local NVIM_PID_BITS = 10
  local nvim_pid = 0
  local cnt = 30
  return function()
    if nvim_pid == 0 then
      local pid = vim.fn.getpid()
      nvim_pid = bit.band(bit.bxor(pid, bit.rshift(pid, 5), bit.rshift(pid, NVIM_PID_BITS)), 0x3FF)
    end
    cnt = cnt + 1
    return bit.bor(bit.lshift(nvim_pid, 24 - NVIM_PID_BITS), cnt)
  end
end)()

-- Does the environment identify a terminal known to support the kitty graphics
-- protocol? Lets us resolve support instantly, with no terminal round-trip, for
-- the common emulators. Conservative: unknowns fall through to the async query.
local function known_graphics_terminal()
  local term = (vim.env.TERM or ''):lower()
  if term:find('kitty', 1, true) or term:find('ghostty', 1, true) then
    return true
  end
  local prog = (vim.env.TERM_PROGRAM or ''):lower()
  if prog == 'ghostty' or prog == 'wezterm' then
    return true
  end
  return vim.env.KITTY_WINDOW_ID ~= nil
    or vim.env.GHOSTTY_RESOURCES_DIR ~= nil
    or vim.env.WEZTERM_EXECUTABLE ~= nil
end

---Asynchronously determine image support, without blocking. Sends the kitty
---graphics query APC and resolves on the terminal's reply (or a short timeout)
---via callback — no vim.wait, so it's safe to call during startup. Idempotent:
---a no-op once detection is in flight or already resolved. Fire this as early
---as the UI allows so the answer is ready around the first paint.
---@param opts? { timeout?: integer }
function M.detect(opts)
  if supported_cache ~= nil or detecting then
    return
  end
  -- Cheap disqualifiers: no API/converter, or a terminal that echoes unknown
  -- sequences (mirrors vim.ui.img._kitty) — resolve to false without querying.
  if not M.capable() then
    return resolve(false)
  end
  if vim.env.TERM_PROGRAM == 'Apple_Terminal' then
    return resolve(false)
  end
  -- Fast path: a terminal that advertises kitty-graphics support in the
  -- environment (Kitty, Ghostty, WezTerm). Resolve synchronously — no round
  -- trip — so the explorer never waits on a reply. This is what collapses the
  -- first-paint blank beat to a single redraw tick. The async query below is
  -- only the fallback for terminals we can't identify up front.
  if known_graphics_terminal() then
    return resolve(true)
  end
  if not (vim.tty and vim.tty.query_apc) then
    return -- no async path; leave undetermined for a later supported() fallback
  end

  detecting = true
  local timeout = (opts and opts.timeout) or 250
  local query_id = gen_query_id()
  local query = string.format('\027_Ga=q,i=%d,s=1,v=1\027\\', query_id)
  pcall(vim.tty.query_apc, query, { timeout = timeout }, function(resp)
    -- kitty APC reply: \027_G...i=<id>...;<status>
    local id = resp:match('^\027_G[^;]*i=(%d+)')
    local status = resp:match(';(.-)%s*$')
    if id and tonumber(id) == query_id and status then
      resolve(true)
      return true
    end
  end)
  -- The callback only fires on a positive match, so resolve to false if the
  -- terminal stays silent past the window.
  vim.defer_fn(function()
    resolve(false)
  end, timeout + 100)
end

---Run fn once support is determined. Calls immediately (next tick) if already
---known; otherwise queues it for when detect()/supported() resolves.
---@param fn fun()
function M.on_resolved(fn)
  if supported_cache ~= nil then
    vim.schedule(fn)
  else
    resolved_listeners[#resolved_listeners + 1] = fn
  end
end

---Synchronous fallback probe. BLOCKS on a terminal round-trip via vim.wait()
---(pumps the event loop), so call only from a safe, user-triggered, post-startup
---context (e.g. opening svgtree's own tree) — never from a render or startup.
---Prefer detect() + on_resolved() for the auto-open path.
---@return boolean
function M.supported()
  if supported_cache ~= nil then
    return supported_cache
  end
  local ok, res = pcall(function()
    return vim.ui.img ~= nil and vim.ui.img._supported({ timeout = 800 }) == true
  end)
  supported_cache = (ok and res and raster.has_converter()) or false
  vim.schedule(fire_resolved)
  return supported_cache
end

---Non-blocking read of the cached support result. Returns false until support
---has been determined. Safe to call from any hot path.
---@return boolean
function M.supported_cached()
  return supported_cache == true
end

---Has support been determined yet (true or false), regardless of result?
---@return boolean
function M.probed()
  return supported_cache ~= nil
end

---Cheap, synchronous capability check — no terminal round-trip. True if this
---build could render images at all (vim.ui.img present + a converter on PATH).
---Lets a host hold its first render while detect() is still pending, instead of
---committing to glyphs-or-icons before the answer is known.
---@return boolean
function M.capable()
  return vim.ui.img ~= nil and raster.has_converter()
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
    local png = raster.png_path(stem) or raster.png_path('file')
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
