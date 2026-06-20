-- Adapter: render svgtree's SVG image icons inside neo-tree.nvim.
--
-- EXPERIMENTAL — less battle-tested than the snacks adapter. neo-tree renders
-- through a component pipeline that assigns line numbers only after components
-- run, so (unlike snacks) we can't learn the icon's exact byte column from the
-- formatter. We hook the documented `after_render` event, map each visible
-- line back to its node, and anchor the image at a column derived from the
-- node's depth. If the icon lands a cell or two off, tune `col_offset`.
--
-- Wire it up — suppress neo-tree's own glyph by dropping the `icon` component,
-- then register the handler:
--
--   require("svgtree").setup({})
--   require("neo-tree").setup({
--     default_component_configs = { icon = { provider = function(icon)
--       icon.text, icon.highlight = "  ", "NeoTreeFileIcon"  -- blank, keep width
--     end } },
--     event_handlers = {
--       { event = "after_render", handler = require("svgtree.adapters.neotree").on_render },
--     },
--   })

local config = require('svgtree.config')
local engine = require('svgtree.engine')
local capability = require('svgtree.capability')
local icons = require('svgtree.icons')

local M = {}

-- Tunables (override via M.setup).
M.opts = {
  indent = 2, -- neo-tree indent_size
  col_offset = 0, -- nudge if the icon lands off the glyph slot
}

function M.setup(opts)
  M.opts = vim.tbl_extend('force', M.opts, opts or {})
end

-- buf -> engine handle
local handles = {}

---@param node table neo-tree NuiNode
---@return string stem
local function stem_for(node)
  if node.type == 'directory' then
    return node:is_expanded() and 'directory_open' or 'directory'
  end
  return icons.stem(node.name, 'file')
end

-- Byte column where the icon sits, from the node's depth. neo-tree indents by
-- (depth-1)*indent and draws the icon after the indent/expander.
local function icon_col(node)
  local depth = (node.get_depth and node:get_depth()) or 1
  return (depth - 1) * M.opts.indent + 1 + M.opts.col_offset
end

---`after_render` handler: (re)attach the engine for this tree and reconcile.
---@param args table neo-tree event payload (carries the source state)
function M.on_render(args)
  if not capability.supported_cached() then
    return
  end
  if not config.options.pack then
    config.setup({})
  end

  local state = args and (args.state or args)
  local win = state and state.winid
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local tree = state.tree
  if not tree then
    return
  end

  if handles[buf] then
    handles[buf].detach()
  end

  handles[buf] = engine.attach({
    win = win,
    buf = buf,
    name = 'svgtree_neotree_' .. buf,
    resolve = function(line)
      local ok, node = pcall(function()
        return tree:get_node(line)
      end)
      if not ok or not node then
        return nil
      end
      local key = (node.get_id and node:get_id()) or node.id or node.path
      return { col = icon_col(node), stem = stem_for(node), key = key }
    end,
  })
  handles[buf].schedule()
end

return M
