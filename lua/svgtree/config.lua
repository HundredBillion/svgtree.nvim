local M = {}

---@class svgtree.Config
local defaults = {
  -- Pack selector: nil = bundled starter; a bare name resolves under
  -- stdpath('data')/svgtree/packs/<name>; an absolute path = an unpacked VSCode
  -- icon-theme dir (or a path straight to a theme JSON).
  pack = nil,
  -- Icon footprint in terminal cells and the pixel size to rasterize to.
  icon = {
    width = 2, -- cells
    height = 1, -- cells
    size_px = 40, -- rasterized PNG size (terminal scales into the cell box)
    zindex = 50,
  },
  -- Tree window.
  window = {
    width = 36,
    side = 'left', -- 'left' | 'right'
  },
  indent = 2, -- spaces per depth level
  show_hidden = false, -- show dotfiles
  -- Pre-rasterize the entire pack on setup. Leave false for large packs.
  warm = false,
  -- Fall back to plain text labels when the terminal can't display images.
  fallback_text = true,
}

M.options = vim.deepcopy(defaults)

---@param opts? svgtree.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})

  local pack = require('svgtree.pack')
  local resolved = pack.load(nil) -- bundled starter, always present
  if M.options.pack then
    resolved = pack.load(M.options.pack) or resolved
  end
  -- Never nil: a totally broken bundled set degrades to "no icons", not a crash.
  M.options.resolved = resolved or { theme = { iconDefinitions = {} }, dir = '' }
  return M.options
end

return M
