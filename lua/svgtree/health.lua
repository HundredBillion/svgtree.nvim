-- :checkhealth svgtree
local raster = require('svgtree.raster')
local capability = require('svgtree.capability')
local config = require('svgtree.config')

local M = {}

function M.check()
  local h = vim.health
  h.start('svgtree.nvim')

  local renderer = config.options.renderer
  local native_api = renderer ~= 'terminal' and pcall(require, 'sprite')
  if renderer == 'terminal' then
    h.info('renderer: terminal tree')
  elseif native_api then
    h.ok('Sprite plugin API found; native tree is available when Sprite negotiates the dock features')
    h.info('native icons use the selected SVG pack directly; terminal prerequisites below apply only to fallback')
  else
    h.info('Sprite plugin API not found; terminal tree will be used')
  end

  -- Neovim version / vim.ui.img.
  if vim.ui and vim.ui.img then
    h.ok('vim.ui.img is available (Neovim >= 0.13)')
  else
    (native_api and h.info or h.error)('vim.ui.img not found — terminal image icons require Neovim 0.13+')
  end

  -- Terminal graphics support (terminal axis only; converter checked separately
  -- below, so the user sees which piece is missing).
  if capability.terminal_supported({ timeout = 1000 }) then
    h.ok('terminal supports the graphics protocol')
  else
    (native_api and h.info or h.warn)('terminal did not report graphics support — terminal icons will fall back to text')
    h.info('use Kitty, Ghostty, or WezTerm; check tmux passthrough if multiplexed')
  end

  -- SVG converter.
  if vim.fn.executable('rsvg-convert') == 1 then
    h.ok('rsvg-convert found (best for SVG text/fonts)')
  elseif raster.has_converter() then
    (native_api and h.info or h.warn)('using ImageMagick; install `librsvg` (rsvg-convert) for reliable terminal SVG text rendering')
  else
    (native_api and h.info or h.error)('no SVG converter — terminal image icons require `rsvg-convert` or `magick`')
  end
end

return M
