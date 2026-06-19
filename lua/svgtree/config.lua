local M = {}

---@class svgtree.Config
local defaults = {
  -- Directory containing the SVG icon pack. Defaults to the bundled set.
  pack = nil, -- resolved to <plugin>/assets/icons at setup if nil
  -- Optional resolver override: { dir, dir_open, file, by_name, by_ext,
  -- by_folder, by_folder_open }. nil = built-in starter mapping. See
  -- svgtree.packs.material for the generated VSCode/Material map.
  icon_map = nil,
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
  -- Pre-rasterize the entire pack on setup. Leave false for large packs
  -- (Material) — icons rasterize on demand and cache to disk anyway.
  warm = false,
  -- Fall back to plain text labels when the terminal can't display images.
  -- (A future version can fall back to Nerd Font glyphs instead.)
  fallback_text = true,
}

M.options = vim.deepcopy(defaults)

---@param opts? svgtree.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  if not M.options.pack then
    -- <this file>/../../../assets/icons
    local src = debug.getinfo(1, 'S').source:sub(2)
    local root = vim.fn.fnamemodify(src, ':h:h:h')
    M.options.pack = root .. '/assets/icons'
  end
  return M.options
end

return M
