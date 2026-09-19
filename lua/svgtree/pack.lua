-- Reads a VSCode file-icon theme in place and resolves filesystem entries to its
-- icons. Pure functions (resolve/icon_svg) are the testable seam; load() finds &
-- decodes the theme JSON for a pack selector. No svgtree-specific pack format:
-- a pack is just an unpacked VSCode icon theme (theme JSON + SVGs). load() returns
-- nil on any failure so config can substitute the bundled starter.

local M = {}
local lowercase_maps = setmetatable({}, { __mode = 'k' })

local function association(map, key)
  if type(map) ~= 'table' or not key then return nil end
  local index = lowercase_maps[map]
  if not index then
    index = {}
    for name, id in pairs(map) do
      if type(name) == 'string' then index[name:lower()] = id end
    end
    lowercase_maps[map] = index
  end
  return index[key:lower()]
end

-- Bundled starter dir: <this file>/../../assets/icons (pack.lua is lua/svgtree/).
local function bundled_dir()
  local src = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(src, ':h:h:h') .. '/assets/icons'
end

local function material_dir()
  return vim.fn.fnamemodify(bundled_dir(), ':h') .. '/material'
end

local function read_json(path)
  return vim.json.decode(table.concat(vim.fn.readfile(path), '\n'))
end

local function looks_like_path(s)
  return s:match('[/\\]') ~= nil or s:match('^~') ~= nil or s:match('^%a:[/\\]') ~= nil
end

-- Find the theme JSON for a pack directory. The bundled set keeps it at
-- icon-theme.json; a real extension declares it in package.json's
-- contributes.iconThemes (at the dir root or under extension/).
local function find_theme_json(dir)
  local bundled = dir .. '/icon-theme.json'
  if vim.fn.filereadable(bundled) == 1 then
    return bundled
  end
  for _, pj in ipairs({ dir .. '/package.json', dir .. '/extension/package.json' }) do
    if vim.fn.filereadable(pj) == 1 then
      local ok, data = pcall(read_json, pj)
      if ok and type(data) == 'table' and type(data.contributes) == 'table'
        and type(data.contributes.iconThemes) == 'table' and data.contributes.iconThemes[1]
        and type(data.contributes.iconThemes[1].path) == 'string' then
        local base = vim.fn.fnamemodify(pj, ':h')
        return vim.fs.normalize(base .. '/' .. data.contributes.iconThemes[1].path)
      end
    end
  end
  return nil
end

---Resolve a `pack` selector to its decoded theme + the theme JSON's dir.
---@param selector string|nil
---@return { theme:table, dir:string }|nil
function M.load(selector)
  local dir, theme_json
  if selector == nil then
    dir = bundled_dir()
  elseif looks_like_path(selector) then
    local p = (vim.fn.fnamemodify(vim.fn.expand(selector), ':p')):gsub('[/\\]+$', '')
    if vim.fn.filereadable(p) == 1 and vim.fn.isdirectory(p) == 0 then
      theme_json = p -- selector points straight at a theme JSON file
    else
      dir = p
    end
  else
    dir = vim.fn.stdpath('data') .. '/svgtree/packs/' .. selector
  end

  theme_json = theme_json or (dir and find_theme_json(dir))
  if not theme_json then
    return nil
  end

  local ok, theme = pcall(read_json, theme_json)
  if not ok or type(theme) ~= 'table' or type(theme.iconDefinitions) ~= 'table' then
    return nil
  end
  return { theme = theme, dir = vim.fn.fnamemodify(theme_json, ':h') }
end

function M.load_bundled_material()
  return M.load(material_dir())
end

---Resolve a filesystem entry to an iconId, or nil for "no icon". Pure.
---@param theme table
---@param name string basename
---@param kind 'dir'|'file'
---@param open? boolean
---@param opts? { root?: boolean, parent?: string }
---@return string? iconId
function M.resolve(theme, name, kind, open, opts)
  if type(theme) ~= 'table' then
    return nil
  end

  if kind == 'dir' then
    if opts and opts.root then
      local root = open and (theme.rootFolderExpanded or theme.rootFolder) or theme.rootFolder
      if root then return root end
    end
    local qualified = opts and opts.parent and (opts.parent .. '/' .. name) or nil
    local id
    if open and type(theme.folderNamesExpanded) == 'table' then
      id = association(theme.folderNamesExpanded, qualified) or association(theme.folderNamesExpanded, name)
    end
    if not id and type(theme.folderNames) == 'table' then
      id = association(theme.folderNames, qualified) or association(theme.folderNames, name)
    end
    if not id then
      id = (open and (theme.folderExpanded or theme.folder)) or theme.folder
    end
    return id
  end

  local id
  if type(theme.fileNames) == 'table' then
    id = association(theme.fileNames, opts and opts.parent and (opts.parent .. '/' .. name))
      or association(theme.fileNames, name)
  end
  if not id then
    if type(theme.fileExtensions) == 'table' then
      local extensions = {}
      for dot in name:gmatch('()%.') do
        extensions[#extensions + 1] = name:sub(dot + 1)
      end
      if opts and opts.parent then
        for _, extension in ipairs(extensions) do
          id = association(theme.fileExtensions, opts.parent .. '/' .. extension)
          if id then break end
        end
      end
      if not id then
        for _, extension in ipairs(extensions) do
          id = association(theme.fileExtensions, extension)
          if id then break end
        end
      end
    end
  end
  return id or theme.file
end

---Absolute SVG path for an iconId, or nil (font-def / unknown id). Pure.
---@param theme table
---@param dir string
---@param iconId string?
---@return string? path
function M.icon_svg(theme, dir, iconId)
  if not iconId or type(theme) ~= 'table' then
    return nil
  end
  local defs = theme.iconDefinitions
  local def = (type(defs) == 'table') and defs[iconId] or nil
  if type(def) ~= 'table' or type(def.iconPath) ~= 'string' then
    return nil
  end
  return vim.fs.normalize(dir .. '/' .. def.iconPath)
end

return M
