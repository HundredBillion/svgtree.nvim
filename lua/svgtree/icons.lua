-- Resolves a filesystem entry to an icon name in the pack.
-- Pure mapping: name/extension -> icon stem (matching a <stem>.svg in the pack).

local M = {}

-- Exact filename matches take priority over extension matches.
local by_name = {
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
}

local by_ext = {
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
}

---Return the icon stem for a node.
---@param name string basename
---@param kind 'dir'|'file'
---@param opts? { open?: boolean }
---@return string stem
function M.stem(name, kind, opts)
  if kind == 'dir' then
    return (opts and opts.open) and 'directory_open' or 'directory'
  end
  if by_name[name] then
    return by_name[name]
  end
  local ext = name:match('%.([%w_]+)$')
  if ext and by_ext[ext:lower()] then
    return by_ext[ext:lower()]
  end
  return 'file'
end

return M
