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
  -- Prime the graphics-support probe once, at the first settled moment.
  --
  -- vim.ui.img._supported() blocks on a terminal round-trip via vim.wait(),
  -- which pumps the event loop. We must NOT do that during startup (it
  -- re-enters other plugins' deferred `config`), nor inside a picker's first
  -- render/show — and that last point is the subtle one: when the adapters
  -- probe lazily on the very first explorer open, pumping the loop mid-show
  -- disrupts that show and the icons never get placed (they only appear once
  -- the explorer is closed and reopened, by which point support is cached).
  --
  -- SafeState fires once the editor is idle and about to wait for input: post
  -- startup (deferred configs already ran) and with no pending render to
  -- corrupt. Probing here caches the result before any explorer is shown, so
  -- the first open behaves like a reopen. The adapters still probe lazily as a
  -- fallback; once cached it's instant and harmless.
  vim.api.nvim_create_autocmd('SafeState', {
    once = true,
    callback = function()
      require('svgtree.engine').supported()
    end,
  })
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
