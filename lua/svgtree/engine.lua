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
  -- Bounds the startup retry below (~20 * 30ms ≈ 600ms) so a window that never
  -- draws can't spin forever.
  local draw_retries = 0
  local MAX_DRAW_RETRIES = 20

  local handle = {}

  local function valid()
    return vim.api.nvim_win_is_valid(opts.win) and vim.api.nvim_buf_is_valid(opts.buf)
  end

  local function reconcile()
    if not valid() then
      return
    end
    local win = opts.win
    local top = math.max(vim.fn.line('w0', win), 1)
    local bot = vim.fn.line('w$', win)

    -- Place/move icons whose anchor cell is actually on screen. screenpos()
    -- returns row==0 when the cell is off-screen — vertically (scrolled past)
    -- OR horizontally — so it doubles as our cull test on both axes.
    local want = {}
    local wanted, placed = 0, 0
    for line = top, bot do
      local spec = opts.resolve(line)
      if spec and spec.stem then
        wanted = wanted + 1
        local pos = vim.fn.screenpos(win, line, spec.col)
        if pos.row > 0 then
          placed = placed + 1
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

    -- Startup race: on a cold open the window isn't laid out yet, so
    -- line('w$') reports a short visible range (often just the cursor line)
    -- and screenpos() returns row 0 — we place too few icons, or none, and the
    -- rest only showed up once later activity re-rendered. Detect an
    -- under-drawn window — its visible bottom is below what the window height
    -- and line count imply, or we had icons to show but placed none — and retry
    -- on a short timer until it settles. defer_fn doesn't pump the loop, so
    -- it's safe here; the cap stops a never-drawn window from spinning forever.
    local height = vim.api.nvim_win_get_height(win)
    local line_count = vim.api.nvim_buf_line_count(opts.buf)
    local expected_bot = math.min(line_count, top + height - 1)
    -- Fully drawn ⇒ w$ matches the height/line-count, and every on-screen line
    -- with an icon resolves to a real screen row (placed == wanted). A shortfall
    -- in either means the window is still painting. (Icons live at a fixed left
    -- column that h-scroll lock keeps visible, so placed < wanted is never a
    -- legitimate horizontal cull here.)
    local under_drawn = bot < expected_bot or placed < wanted
    if under_drawn and draw_retries < MAX_DRAW_RETRIES then
      draw_retries = draw_retries + 1
      vim.defer_fn(reconcile, 30)
    else
      draw_retries = 0
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
