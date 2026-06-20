-- Headless checks for svgtree.pack (VSCode-theme reader/resolver). Run via scripts/test.sh.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local pack = require('svgtree.pack')

local fails = 0
local function check(c, m)
  if c then print('  ok  ' .. m) else print('  FAIL ' .. m); fails = fails + 1 end
end

-- ---- pure resolve against a fixture theme ----
local theme = {
  iconDefinitions = {
    _py = { iconPath = './py.svg' }, _f = { iconPath = './folder.svg' },
    _fo = { iconPath = './folder-open.svg' }, _file = { iconPath = './file.svg' },
    _src = { iconPath = './src.svg' }, _font = { fontCharacter = 'x' },
  },
  file = '_file', folder = '_f', folderExpanded = '_fo',
  fileExtensions = { py = '_py' }, fileNames = { ['makefile'] = '_py' },
  folderNames = { src = '_src' },
}
check(pack.resolve(theme, 'main.py', 'file') == '_py', 'ext py -> _py')
check(pack.resolve(theme, 'Makefile', 'file') == '_py', 'fileName matches lowercased')
check(pack.resolve(theme, 'README', 'file') == '_file', 'unmatched file -> file default')
check(pack.resolve(theme, 'whatever.zzz', 'file') == '_file', 'unknown ext -> file default')
check(pack.resolve(theme, 'src', 'dir', false) == '_src', 'folderNames -> _src')
check(pack.resolve(theme, 'lib', 'dir', false) == '_f', 'unmatched folder -> folder')
check(pack.resolve(theme, 'lib', 'dir', true) == '_fo', 'open unmatched folder -> folderExpanded')
check(pack.resolve({ iconDefinitions = {}, folder = '_f' }, 'lib', 'dir', true) == '_f', 'no folderExpanded -> folder')

-- ---- pure icon_svg ----
check(pack.icon_svg(theme, '/p', '_py') == '/p/py.svg', 'icon_svg resolves iconPath')
check(pack.icon_svg(theme, '/p', '_font') == nil, 'font def (no iconPath) -> nil')
check(pack.icon_svg(theme, '/p', '_nope') == nil, 'unknown id -> nil')
check(pack.icon_svg(theme, '/p', nil) == nil, 'nil id -> nil')

-- ---- load: package.json-style pack ----
local SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>'
local d = vim.fn.tempname()
vim.fn.mkdir(d, 'p')
vim.fn.writefile({ SVG }, d .. '/a.svg')
vim.fn.writefile({ vim.json.encode({ iconDefinitions = { _a = { iconPath = './a.svg' } }, file = '_a' }) }, d .. '/theme.json')
vim.fn.writefile({ vim.json.encode({ contributes = { iconThemes = { { path = 'theme.json' } } } }) }, d .. '/package.json')
local p = pack.load(d)
check(p ~= nil and p.dir == d, 'load via package.json -> dir')
check(p ~= nil and p.theme.file == '_a', 'load decodes theme')
check(p ~= nil and pack.icon_svg(p.theme, p.dir, '_a') == d .. '/a.svg', 'loaded theme resolves svg')

-- ---- load: a direct theme JSON path ----
local p2 = pack.load(d .. '/theme.json')
check(p2 ~= nil and p2.theme.file == '_a', 'load via direct theme JSON')

-- ---- load: the bundled starter ----
local b = pack.load(nil)
check(b ~= nil and type(b.theme.iconDefinitions) == 'table', 'bundled loads')
check(b ~= nil and pack.resolve(b.theme, 'main.py', 'file') == 'python', 'bundled resolves py -> python')
check(b ~= nil and pack.resolve(b.theme, 'src', 'dir', false) == 'directory', 'bundled folder default -> directory')

-- ---- load failures -> nil ----
local cd = vim.fn.tempname(); vim.fn.mkdir(cd, 'p')
vim.fn.writefile({ '{ not json' }, cd .. '/icon-theme.json')
check(pack.load(cd) == nil, 'corrupt theme -> nil')
check(pack.load(vim.fn.tempname()) == nil, 'missing pack -> nil')

if fails > 0 then print('FAILED: ' .. fails); os.exit(1) else print('test-pack: ALL PASS') end
