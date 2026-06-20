-- Terminal-graphics capability: does this terminal speak the kitty graphics
-- protocol, and can we rasterize SVGs at all? Split out of the placement engine
-- so support detection lives in exactly one place -- the engine draws icons;
-- this module decides whether drawing is even possible. health.lua and every
-- host adapter ask here instead of probing the terminal themselves.

local raster = require('svgtree.raster')

local M = {}

-- nil = not yet determined, true = supported, false = unsupported. "supported"
-- here means BOTH the terminal speaks the protocol AND a converter is present
-- (the render path's meaning). health.lua wants the terminal axis alone; see
-- terminal_supported(). Determining it means asking the terminal -- a round trip
-- -- so detect() resolves asynchronously and supported() is the blocking fallback.
local supported_cache = nil
local detecting = false

-- Callbacks to run once support is determined (true or false). Hosts use this to
-- hold their first render until they know whether to draw icons or glyphs.
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
-- protocol? Lets us resolve support instantly, with no round-trip, for the
-- common emulators. Conservative: unknowns fall through to the async query.
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

---Parse a kitty graphics APC reply. Pure: returns true iff `resp` is a
---well-formed positive reply whose image id equals `query_id`. Extracted from
---the query callback so the riskiest logic is testable without a live terminal.
---@param resp string
---@param query_id integer
---@return boolean
function M.parse_apc_reply(resp, query_id)
  local id = resp:match('^\027_G[^;]*i=(%d+)')
  local status = resp:match(';(.-)%s*$')
  return id ~= nil and tonumber(id) == query_id and status ~= nil
end

---Asynchronously determine image support, without blocking. Sends the kitty
---graphics query APC and resolves on the terminal's reply (or a short timeout)
---via callback -- no vim.wait, so it's safe during startup. Idempotent.
---@param opts? { timeout?: integer }
function M.detect(opts)
  if supported_cache ~= nil or detecting then
    return
  end
  if not M.capable() then
    return resolve(false)
  end
  if vim.env.TERM_PROGRAM == 'Apple_Terminal' then
    return resolve(false)
  end
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
    if M.parse_apc_reply(resp, query_id) then
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

---Run fn once support is determined. Calls next tick if already known.
---@param fn fun()
function M.on_resolved(fn)
  if supported_cache ~= nil then
    vim.schedule(fn)
  else
    resolved_listeners[#resolved_listeners + 1] = fn
  end
end

---Blocking terminal-ONLY probe: does the terminal speak the protocol? Does NOT
---require a converter and does NOT touch supported_cache -- for health.lua's
---terminal diagnostic, kept distinct from its separate converter check. Blocks
---on a round-trip via vim.wait; call only post-startup (e.g. :checkhealth).
---@param opts? { timeout?: integer }
---@return boolean
function M.terminal_supported(opts)
  local timeout = (opts and opts.timeout) or 800
  local ok, res = pcall(function()
    return vim.ui.img ~= nil and vim.ui.img._supported({ timeout = timeout }) == true
  end)
  return (ok and res) or false
end

---Synchronous fallback probe. BLOCKS on a terminal round-trip via vim.wait, so
---call only from a safe, user-triggered, post-startup context. Means terminal
---support AND a converter present (the render path's meaning). Prefer detect() +
---on_resolved() for the auto-open path.
---@return boolean
function M.supported()
  if supported_cache ~= nil then
    return supported_cache
  end
  supported_cache = (M.terminal_supported({ timeout = 800 }) and raster.has_converter()) or false
  vim.schedule(fire_resolved)
  return supported_cache
end

---Non-blocking read of the cached support result. False until determined.
---@return boolean
function M.supported_cached()
  return supported_cache == true
end

---Has support been determined yet (true or false)?
---@return boolean
function M.probed()
  return supported_cache ~= nil
end

---Cheap, synchronous capability check -- no round-trip. True if this build could
---render images at all (vim.ui.img present + a converter on PATH).
---@return boolean
function M.capable()
  return vim.ui.img ~= nil and raster.has_converter()
end

return M
