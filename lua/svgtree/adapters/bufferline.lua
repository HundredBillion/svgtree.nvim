-- Adapter: render svgtree's SVG image icons in the bufferline.nvim tabline.
--
-- The tabline is NOT a buffer, so the placement engine (which welds icons to
-- buffer lines via extmarks) can't drive it. But bufferline lets you supply the
-- per-tab icon via `get_element_icon`, which returns (icon_text, highlight) --
-- and svgtree's icon IS just placeholder text (U+10EEEE cells) carrying a
-- highlight whose `fg` is the image id. So we hand bufferline the placeholder
-- string as the "icon" and a SvgtreeImgFg<id> group as its highlight; the
-- terminal paints the image over those cells, re-emitted on every tabline
-- redraw for free (no extmark/reconcile needed).
--
-- Two constraints shape this adapter:
--   * bufferline rebuilds the icon highlight per tab-visibility state and keeps
--     only `fg` (see its highlights.set_icon_highlight) -- so we use kitty's
--     fg-only mode (place_default + hl_group_fg), which needs no placement id.
--     The host's config must also keep `color_icons = true`, else bufferline
--     forces fg=NONE and destroys the image id.
--   * `get_element_icon` runs INSIDE tabline evaluation, where writing terminal
--     escapes would corrupt the draw. So it only READS a cache; misses are
--     built on a scheduled (off-loop) tick and shown on the next repaint, and
--     buffer events pre-warm icons before they're first drawn.
--
-- Wire it into your bufferline config:
--
--   opts = function(_, opts)
--     require("svgtree.adapters.bufferline").setup()
--     opts.options.color_icons = true
--     opts.options.get_element_icon = function(el)
--       local text, hl = require("svgtree.adapters.bufferline").get_element_icon(el)
--       return text, hl  -- nil falls through to bufferline's glyph path
--     end
--     return opts
--   end

local config = require('svgtree.config')
local raster = require('svgtree.raster')
local kitty = require('svgtree.kitty')
local capability = require('svgtree.capability')
local icons = require('svgtree.icons')

local M = {}

-- stem -> { id, hl, text }. One transmit + default-placement per unique icon,
-- reused on every tab that shows it. Built only OUTSIDE the tabline render loop.
local cache = {}
-- stems queued for a scheduled (off-loop) build.
local queue = {}
local flushing = false
local did_setup = false

local function ensure_resolved()
  if not config.options.resolved then
    config.setup({})
  end
end

-- Transmit + place + build text/hl for one stem. Writes terminal escapes, so it
-- MUST run outside tabline evaluation. Returns the cached rec, or nil when the
-- theme (and its default-file fallback) has no SVG for the stem.
local function build(stem)
  if cache[stem] then
    return cache[stem]
  end
  ensure_resolved()
  local icon = config.options.icon
  local default_file = config.options.resolved and config.options.resolved.theme.file
  local png = raster.png_path(stem) or (default_file and raster.png_path(default_file))
  if not png then
    return nil
  end
  local id = kitty.transmit(png)
  kitty.place_default(id, icon.width, icon.height)
  cache[stem] = {
    id = id,
    hl = kitty.hl_group_fg(id),
    text = kitty.placeholder_text(icon.width, 1),
  }
  return cache[stem]
end

-- Drain the build queue once, off the render loop, then repaint the tabline so
-- freshly-built icons replace the glyph fallback shown in the meantime.
local function flush()
  flushing = false
  local built = false
  for stem in pairs(queue) do
    queue[stem] = nil
    if build(stem) then
      built = true
    end
  end
  if built then
    pcall(vim.cmd, 'redrawtabline')
  end
end

local function enqueue(stem)
  if cache[stem] or queue[stem] then
    return
  end
  queue[stem] = true
  if flushing then
    return
  end
  flushing = true
  vim.schedule(flush)
end

-- Resolve a fetcher element to a pack icon stem. File icons only: directories
-- and nameless/scratch buffers get no image, so the caller's glyph path runs.
local function stem_for(element)
  if element.directory then
    return nil
  end
  local path = element.path
  if not path or path == '' then
    return nil
  end
  local name = vim.fn.fnamemodify(path, ':t')
  if name == '' then
    return nil
  end
  return icons.stem(name, 'file')
end

-- Warm icons for one buffer name (used by the pre-warm autocmds).
local function warm_buf(buf)
  if not capability.supported_cached() then
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then
    return
  end
  local stem = icons.stem(vim.fn.fnamemodify(name, ':t'), 'file')
  if stem then
    enqueue(stem)
  end
end

-- Warm every currently-listed buffer, so the first tabline paint after support
-- is determined already has images (no glyph flash for already-open buffers).
local function warm_open_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
      warm_buf(buf)
    end
  end
end

---Install buffer-event pre-warming and kick off graphics detection. Idempotent.
---Call from the plugin's opts function (svgtree loaded, not in a render loop).
function M.setup()
  if did_setup then
    return
  end
  did_setup = true
  capability.detect()
  local grp = vim.api.nvim_create_augroup('svgtree_bufferline', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufAdd', 'BufWinEnter', 'BufFilePost' }, {
    group = grp,
    callback = function(args)
      warm_buf(args.buf)
    end,
  })
  capability.on_resolved(warm_open_buffers)
end

---Drop-in for bufferline's `get_element_icon`. Returns (placeholder_text, hl)
---when an SVG image is ready, or nil to fall through to bufferline's glyph path
---(nvim-web-devicons -- which LazyVim mocks with mini.icons, so the glyphs match
---the explorer's own fallback). Runs inside tabline evaluation, so it only READS
---the cache; misses are built on a scheduled tick and appear on the next paint.
---@param element table bufferline.IconFetcherOpts (.path, .filetype, .directory, ...)
---@return string? icon, string? hl
function M.get_element_icon(element)
  if not did_setup then
    M.setup()
  end
  if not capability.supported_cached() then
    capability.detect() -- instant for known terminals; harmless if still pending
    return nil
  end
  local stem = stem_for(element)
  if not stem then
    return nil
  end
  local rec = cache[stem]
  if rec then
    return rec.text, rec.hl
  end
  enqueue(stem) -- build off-loop; the glyph shows until the repaint
  return nil
end

return M
