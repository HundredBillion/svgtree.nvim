-- Resolves a filesystem entry to an icon stem (a <stem>.svg in the pack).
--
-- Two layers:
--   * a small built-in mapping used by the bundled starter pack, and
--   * an optional `icon_map` (see config) that overrides it — e.g. the
--     generated Material Icon Theme map, which also gives per-folder icons.

local config = require('svgtree.config')

local M = {}

-- Built-in starter mapping (exact filename matches take priority over ext).
local builtin = {
  dir = 'directory',
  dir_open = 'directory_open',
  file = 'file',
  by_name = {
    ['.gitignore'] = 'git',
    ['.gitattributes'] = 'git',
    ['.gitmodules'] = 'git',
    ['Gemfile'] = 'ruby',
    ['Gemfile.lock'] = 'lock',
    ['Cargo.toml'] = 'rust',
    ['Cargo.lock'] = 'lock',
    ['package.json'] = 'json',
    ['package-lock.json'] = 'lock',
    ['go.mod'] = 'go',
    ['go.sum'] = 'lock',
    ['Makefile'] = 'shell',
  },
  by_ext = {
    lua = 'lua',
    py = 'python',
    js = 'javascript',
    mjs = 'javascript',
    cjs = 'javascript',
    jsx = 'javascript',
    ts = 'typescript',
    tsx = 'typescript',
    json = 'json',
    jsonc = 'json',
    md = 'markdown',
    markdown = 'markdown',
    html = 'html',
    htm = 'html',
    css = 'css',
    scss = 'css',
    rb = 'ruby',
    go = 'go',
    rs = 'rust',
    sh = 'shell',
    bash = 'shell',
    zsh = 'shell',
    yaml = 'yaml',
    yml = 'yaml',
    toml = 'toml',
    lock = 'lock',
    png = 'image',
    jpg = 'image',
    jpeg = 'image',
    gif = 'image',
    webp = 'image',
    svg = 'image',
  },
}

---Return the icon stem for a node.
---@param name string basename
---@param kind 'dir'|'file'
---@param opts? { open?: boolean }
---@return string stem
function M.stem(name, kind, opts)
  local map = config.options.icon_map or builtin
  local dir = map.dir or builtin.dir
  local dir_open = map.dir_open or builtin.dir_open
  local file_def = map.file or builtin.file
  local by_name = map.by_name or {}
  local by_ext = map.by_ext or {}

  if kind == 'dir' then
    local key = name:lower()
    if opts and opts.open then
      return (map.by_folder_open and map.by_folder_open[key]) or dir_open
    end
    return (map.by_folder and map.by_folder[key]) or dir
  end

  -- Files: exact name (lower- or original-case) wins, then extension.
  local lname = name:lower()
  if by_name[lname] then
    return by_name[lname]
  end
  if by_name[name] then
    return by_name[name]
  end
  local ext = name:match('%.([%w_]+)$')
  if ext and by_ext[ext:lower()] then
    return by_ext[ext:lower()]
  end
  return file_def
end

return M
