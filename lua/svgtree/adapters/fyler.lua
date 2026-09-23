-- Adapter: render svgtree SVG icons in Fyler's editable terminal buffer.
--
-- Fyler owns the filesystem buffer and refresh lifecycle. This module supplies
-- a blank icon provider (real cells for the Kitty placeholders) and registers
-- a post-refresh extension which reconciles svgtree's placement engine.

local capability = require('svgtree.capability')
local config = require('svgtree.config')
local engine = require('svgtree.engine')
local icons = require('svgtree.icons')

local M = {}
local handles = {}
local entries = {}
local awaiting = {}
local windows = {}

---Fyler icon provider. Configure this as `integrations.icon`.
---It reserves actual buffer cells; the engine overlays them with the SVG.
---@return string|nil, nil
function M.icon()
  if not capability.supported_cached() then return nil, nil end
  return string.rep(' ', config.options.icon.width), nil
end

local function detach(buf)
  if handles[buf] then handles[buf].detach(); handles[buf] = nil end
  entries[buf] = nil
  windows[buf] = nil
end

local function stem_for(item)
  if item.type == 'directory' then
    return icons.stem(vim.fs.basename(item.path), 'dir', { open = item.expanded })
  end
  return icons.stem(vim.fs.basename(item.path), 'file')
end

local function attach(instance, visible)
  local win, buf = instance.win_id, instance.buf_id
  if not (win and buf and vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf)) then return end
  entries[buf] = visible
  if handles[buf] and windows[buf] == win then
    handles[buf].reconcile()
    return
  end
  detach(buf)
  entries[buf] = visible
  windows[buf] = win
  handles[buf] = engine.attach({
    win = win,
    buf = buf,
    name = 'svgtree_fyler_' .. buf,
    resolve = function(line)
      local item = entries[buf] and entries[buf][line]
      if not item then return nil end
      -- Fyler indents each depth by two bytes, then renders the icon slot.
      local col = (item.depth or 0) * 2 + 1
      -- Only overlay cells M.icon reserved. Without them (Fyler not using this
      -- provider, or another provider's glyph) the overlay would hide the name.
      local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ''
      local width = config.options.icon.width
      if text:sub(col, col + width - 1) ~= string.rep(' ', width) then return nil end
      return { col = col, stem = stem_for(item), key = item.path }
    end,
  })
end

---Fyler's `finder_refresh_post` hook.
---@param instance table
---@param visible table[]
function M.on_refresh(instance, visible)
  capability.detect()
  if not capability.supported_cached() then
    local buf = instance and instance.buf_id
    if buf and not awaiting[buf] then
      awaiting[buf] = true
      capability.on_resolved(function()
        awaiting[buf] = nil
        if capability.supported_cached() then
          -- The first render used Fyler's normal text layout while terminal
          -- support was unknown. Render again to reserve the icon cells, then
          -- this hook attaches the image engine on the refreshed buffer.
          instance:refresh()
        end
      end)
    end
    return
  end
  if not config.options.resolved then config.setup({}) end
  attach(instance, visible)
end

---Register the adapter with Fyler. Call after `require('fyler').setup()`.
function M.setup()
  local ok, extensions = pcall(require, 'fyler.extensions')
  if not ok then
    vim.notify('svgtree Fyler adapter: call setup after fyler.nvim is loaded', vim.log.levels.WARN)
    return false
  end
  extensions.register({
    name = 'svgtree',
    hooks = { finder_refresh_post = M.on_refresh },
  })
  capability.detect()
  return true
end

return M
