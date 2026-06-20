-- svgtree.nvim — a minimal Neovim file tree that renders real SVG icons as
-- images (via the native vim.ui.img API), instead of font glyphs.
--
-- Requires: Neovim >= 0.13 (vim.ui.img), a terminal with the Kitty graphics
-- protocol (Kitty, Ghostty, WezTerm), and ImageMagick for SVG rasterization.

local config = require('svgtree.config')
local raster = require('svgtree.raster')
local render = require('svgtree.render')

local M = {}

---@param opts? svgtree.Config
function M.setup(opts)
  config.setup(opts)
  -- Kick off graphics detection as early as the UI allows. Unlike the blocking
  -- supported() probe, capability.detect() sends the terminal query and resolves on
  -- the reply WITHOUT vim.wait — no event-loop pumping — so it's safe during
  -- startup and the answer is ready around the first paint. Hosts that hold
  -- their first render until detection resolves (see the snacks adapter) then
  -- show text and icons together, with no glyph flash and no icon pop-in.
  local function start_detection()
    require('svgtree.capability').detect()
  end
  if vim.v.vim_did_enter == 1 then
    start_detection()
  else
    vim.api.nvim_create_autocmd('UIEnter', { once = true, callback = start_detection })
  end
  -- Optionally pre-rasterize the whole pack. Off by default: icons rasterize
  -- on first use and cache to disk, so warming a large pack (e.g. Material's
  -- 1200+ icons) would burn startup CPU for icons you may never see.
  if config.options.warm and raster.has_converter() then
    vim.schedule(raster.warm)
  end
end

---Open the tree. @param root? string defaults to cwd
function M.open(root)
  if not config.options.pack then
    config.setup({})
  end
  render.open(root)
end

function M.close()
  render.close()
end

function M.toggle(root)
  render.toggle(root)
end

return M
