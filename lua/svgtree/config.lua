local M = {}

---@class svgtree.Config
local defaults = {
  renderer = 'auto',
  native = { width = 280, compact_folders = true, mappings = {} },
  -- Pack selector, shared by every renderer: nil = bundled Material; a bare
  -- name resolves under stdpath('data')/svgtree/packs/<name> ('material' falls
  -- back to the bundled copy); an absolute path = an unpacked VSCode icon-theme
  -- dir (or a path straight to a theme JSON).
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
  show_hidden = true, -- show dotfiles
  -- Pre-rasterize the entire pack on setup. Leave false for large packs.
  warm = false,
  -- Fall back to plain text labels when the terminal can't display images.
  fallback_text = true,
}

M.options = vim.deepcopy(defaults)

---@param opts? svgtree.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  assert(vim.tbl_contains({ 'auto', 'terminal', 'sprite' }, M.options.renderer), 'invalid svgtree renderer')
  if package.loaded['svgtree.native_view'] then
    package.loaded['svgtree.native_view'].clear_cache()
  end

  local pack = require('svgtree.pack')
  local selector = M.options.pack
  local resolved = selector and pack.load(selector)
  if not resolved and (selector == nil or selector == 'material') then
    resolved = pack.load_bundled_material()
  end
  resolved = resolved or pack.load(nil) -- tiny starter set, always present
  -- Never nil: a totally broken bundled set degrades to "no icons", not a crash.
  M.options.resolved = resolved or { theme = { iconDefinitions = {} }, dir = '' }
  return M.options
end

---The active icon pack, resolving the defaults if setup() has not run yet.
---@return { theme:table, dir:string }
function M.resolved()
  if not M.options.resolved then M.setup(M.options) end
  return M.options.resolved
end

return M
