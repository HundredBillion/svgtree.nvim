-- Resolves a filesystem entry to an icon id from the active VSCode theme, using
-- the theme that config.setup() loaded once via svgtree.pack and cached at
-- config.options.resolved.theme. May return nil ("no icon"): callers draw nothing
-- for that row -- never a foreign stem.

local config = require('svgtree.config')
local pack = require('svgtree.pack')

local M = {}

---Return the icon id for a node, or nil for "no icon".
---@param name string basename
---@param kind 'dir'|'file'
---@param opts? { open?: boolean }
---@return string? iconId
function M.stem(name, kind, opts)
  return pack.resolve(config.options.resolved.theme, name, kind, opts and opts.open)
end

return M
