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
  -- Warm the icon cache in the background so first open is instant.
  if raster.has_converter() then
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
