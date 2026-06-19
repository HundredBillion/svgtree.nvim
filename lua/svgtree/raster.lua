-- Rasterizes SVG icons to PNG (via ImageMagick) and caches them on disk.
-- Each unique (stem, size) is converted at most once; subsequent runs are
-- instant cache hits. Returns the raw PNG bytes for vim.ui.img.

local config = require('svgtree.config')

local M = {}

local cache_dir = vim.fn.stdpath('cache') .. '/svgtree'
local mem = {} -- stem -> png bytes (in-memory cache for the session)

local function ensure_cache_dir()
  if vim.fn.isdirectory(cache_dir) == 0 then
    vim.fn.mkdir(cache_dir, 'p')
  end
end

---Is an SVG-capable converter available?
---@return boolean
function M.has_converter()
  return vim.fn.executable('rsvg-convert') == 1
    or vim.fn.executable('magick') == 1
    or vim.fn.executable('convert') == 1
end

-- Build the SVG->PNG command. Prefer rsvg-convert: it renders <text> via
-- fontconfig/pango, whereas ImageMagick's internal SVG coder often fails on
-- fonts ("unable to read font"). Fall back to magick for shape-only packs.
local function convert_cmd(svg, png, size)
  if vim.fn.executable('rsvg-convert') == 1 then
    return { 'rsvg-convert', '-w', tostring(size), '-h', tostring(size), '-o', png, svg }
  end
  local bin = vim.fn.executable('magick') == 1 and 'magick' or 'convert'
  -- IM7 requires the input image before operators like -resize.
  return { bin, '-background', 'none', svg, '-resize', size .. 'x' .. size, png }
end

---Return PNG bytes for an icon stem, rasterizing+caching on first use.
---@param stem string
---@return string? bytes nil if the SVG is missing or conversion failed
function M.png_bytes(stem)
  if mem[stem] then
    return mem[stem]
  end
  local opts = config.options
  local size = opts.icon.size_px
  local svg = opts.pack .. '/' .. stem .. '.svg'
  if vim.fn.filereadable(svg) == 0 then
    return nil
  end

  ensure_cache_dir()
  local png = string.format('%s/%s_%d.png', cache_dir, stem, size)

  -- Treat the cached PNG as stale if the source SVG is newer (e.g. the icon
  -- pack was updated/swapped after the first rasterization). Keying by name
  -- alone would otherwise serve the old rendering forever.
  local fresh = vim.fn.filereadable(png) == 1
  if fresh then
    local svg_st, png_st = vim.uv.fs_stat(svg), vim.uv.fs_stat(png)
    if svg_st and png_st and svg_st.mtime.sec > png_st.mtime.sec then
      fresh = false
    end
  end

  if not fresh then
    local res = vim.system(convert_cmd(svg, png, size), { text = false }):wait()
    if res.code ~= 0 or vim.fn.filereadable(png) == 0 then
      return nil
    end
  end

  local bytes = vim.fn.readblob(png)
  mem[stem] = bytes
  return bytes
end

---Pre-rasterize every icon in the pack so later placement never blocks.
function M.warm()
  local opts = config.options
  local files = vim.fn.globpath(opts.pack, '*.svg', false, true)
  for _, svg in ipairs(files) do
    local stem = vim.fn.fnamemodify(svg, ':t:r')
    M.png_bytes(stem)
  end
end

return M
