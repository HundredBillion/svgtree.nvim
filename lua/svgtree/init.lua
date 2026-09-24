local config = require('svgtree.config')
local State = require('svgtree.state')
local Tree = require('svgtree.tree')

local M = {}
local active, generation = nil, 0

local function terminal()
  return require('svgtree.render')
end

local function graphics()
  local function detect() require('svgtree.capability').detect() end
  if vim.v.vim_did_enter == 1 then detect()
  else vim.api.nvim_create_autocmd('UIEnter', { once = true, callback = detect }) end
  if config.options.warm then
    local raster = require('svgtree.raster')
    if raster.has_converter() then vim.schedule(raster.warm) end
  end
end

function M.setup(opts)
  config.setup(opts)
  if config.options.renderer == 'terminal' then graphics() end
end

local function save()
  if not active then return end
  local snapshot = active.view and active.view:snapshot() or
    (active.kind == 'terminal' and terminal().snapshot() or nil)
  if snapshot then State.save(active.root, snapshot) end
end

function M.close()
  generation = generation + 1
  if not active then return end
  save()
  local old = active
  active = nil
  if old.kind == 'native' then old.cancel()
  elseif old.kind == 'pending' and old.cancel then old.cancel()
  elseif old.kind == 'terminal' then terminal().close() end
end

local function fallback(root, token, err)
  if token ~= generation then return end
  if active and active.kind == 'terminal' then return end
  if err and config.options.renderer == 'sprite' then
    local reason = type(err) == 'table' and (err.message or err.code) or tostring(err or 'unavailable')
    vim.notify('SVGTree Sprite renderer unavailable: ' .. reason, vim.log.levels.WARN)
  end
  if config.options.renderer ~= 'terminal' then graphics() end
  active = {kind = 'terminal', root = root}
  terminal().open(root, nil, function(path)
    if token == generation then M.open(path) end
  end)
end

function M.open(root)
  if not config.options.resolved then M.setup({}) end
  root = Tree.normalize(root or vim.uv.cwd())
  vim.api.nvim_set_current_dir(root)
  M.close()
  local token = generation
  if config.options.renderer == 'terminal' then fallback(root, token); return end
  local ok, sprite = pcall(require, 'sprite')
  if not ok or type(sprite) ~= 'table' or type(sprite.available) ~= 'function' then
    fallback(root, token, {message = 'Sprite plugin API is unavailable'})
    return
  end
  active = {kind = 'pending', root = root}
  local available_ok, available_cancel = pcall(sprite.available, function(err, capabilities)
    if token ~= generation then return end
    if err or not capabilities then
      fallback(root, token, err or {message = 'Sprite pane is ineligible'})
      return
    end
    local features = capabilities.features or {}
    for _, feature in ipairs({'owned-dock-v1', 'virtual-list-v1', 'svg-assets-v1', 'dock-resize-v1'}) do
      if not features[feature] and not vim.tbl_contains(features, feature) then
        fallback(root, token, {message = 'Sprite server lacks ' .. feature})
        return
      end
    end
    local opened, cancel = pcall(function() return require('svgtree.native').open(root, nil, {
      ready = function(view)
        if token ~= generation then view:close(); return end
        active = {kind = 'native', root = root, view = view, cancel = function() view:close() end}
      end,
      root = function(path)
        if token == generation then M.open(path) end
      end,
      failed = function(failure)
        if token == generation then
          if active and active.view then State.save(root, active.view:snapshot()) end
          fallback(root, token, failure)
        end
      end,
      closed = function()
        if token == generation then active = nil; generation = generation + 1 end
      end,
    }) end)
    if not opened then fallback(root, token, {message = tostring(cancel)})
    elseif token == generation and active and active.kind == 'pending' then active.cancel = cancel end
    if token ~= generation and opened then cancel() end
  end)
  if not available_ok then fallback(root, token, {message = tostring(available_cancel)})
  elseif token == generation and active and active.kind == 'pending' and not active.cancel then active.cancel = available_cancel end
end

function M.root()
  if not active then return nil end
  if active.kind == 'terminal' and not terminal().root() then active = nil; return nil end
  return active.root
end

---Focus the native Explorer when it is open on `side`.
---Returns false when the Explorer is not a native view on that side, so callers
---can fall back to ordinary Neovim split navigation.
---@param side? 'left'|'right'
---@return boolean
function M.focus(side)
  if not active or active.kind ~= 'native' or not active.view then return false end
  local native_side = (config.options.native and config.options.native.side)
    or (config.options.window and config.options.window.side) or 'left'
  if side and side ~= native_side then return false end
  active.view:focus()
  return true
end

function M.toggle(root)
  if M.root() then M.close() else M.open(root) end
end

return M
