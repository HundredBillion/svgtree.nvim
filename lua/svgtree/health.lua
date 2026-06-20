-- :checkhealth svgtree
local raster = require('svgtree.raster')
local capability = require('svgtree.capability')

local M = {}

function M.check()
  local h = vim.health
  h.start('svgtree.nvim')

  -- Neovim version / vim.ui.img.
  if vim.ui and vim.ui.img then
    h.ok('vim.ui.img is available (Neovim >= 0.13)')
  else
    h.error('vim.ui.img not found — requires Neovim 0.13+ (nightly currently)')
  end

  -- Terminal graphics support (terminal axis only; converter checked separately
  -- below, so the user sees which piece is missing).
  if capability.terminal_supported({ timeout = 1000 }) then
    h.ok('terminal supports the graphics protocol')
  else
    h.warn('terminal did not report graphics support — icons will fall back to text')
    h.info('use Kitty, Ghostty, or WezTerm; check tmux passthrough if multiplexed')
  end

  -- SVG converter.
  if vim.fn.executable('rsvg-convert') == 1 then
    h.ok('rsvg-convert found (best for SVG text/fonts)')
  elseif raster.has_converter() then
    h.warn('using ImageMagick; install `librsvg` (rsvg-convert) for reliable SVG text rendering')
  else
    h.error('no SVG converter — install `librsvg` (rsvg-convert) or `imagemagick`')
  end
end

return M
