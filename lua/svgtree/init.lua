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
  -- NOTE: do NOT probe graphics support here. vim.ui.img._supported() blocks on
  -- a terminal round-trip via vim.wait(), which pumps the event loop — running
  -- it during startup re-enters other plugins' deferred `config` callbacks. The
  -- probe is done lazily the first time an explorer is shown (a settled, user-
  -- triggered moment), see the adapters / render.open.
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
