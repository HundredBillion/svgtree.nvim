-- Resolves a filesystem entry to an icon id from the active VSCode theme, using
-- the theme that config.setup() loaded once via svgtree.pack and cached at
-- config.options.resolved.theme. May return nil ("no icon"): callers draw nothing
-- for that row -- never a foreign stem.

local config = require('svgtree.config')
local pack = require('svgtree.pack')

local M = {}

---Resolve the pack for a renderer without changing the host adapter pack.
---@param renderer string
---@return {theme:table, dir:string}
function M.resolve_pack(renderer)
  if renderer ~= 'native' then
    return config.options.resolved or pack.load(nil)
  end
  local selector = config.options.pack
  if selector == nil then
    return pack.load_bundled_material() or config.options.resolved or pack.load(nil)
  end
  if selector == 'material' then
    return pack.load('material') or pack.load_bundled_material() or config.options.resolved or pack.load(nil)
  end
  return config.options.resolved or pack.load(nil)
end

---Return the icon id for a node, or nil for "no icon".
---@param name string basename
---@param kind 'dir'|'file'
---@param opts? { open?: boolean }
---@return string? iconId
function M.stem(name, kind, opts)
  return pack.resolve(config.options.resolved.theme, name, kind, opts and opts.open)
end

return M
