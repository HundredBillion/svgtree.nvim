-- Headless checks for svgtree.kitty fg-only mode. Run via scripts/test.sh (0.13+).
-- fg-only mode lets a text host (e.g. the bufferline tabline) carry an icon as
-- ordinary text + a highlight whose fg encodes the image id, with no dependency
-- on the placement id (sp), which such hosts may drop. These checks assert the
-- two properties that path relies on: cell width and the image-id-in-fg.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require('svgtree.config').setup({})
local kitty = require('svgtree.kitty')

local fails = 0
local function check(c, m)
  if c then print('  ok  ' .. m) else print('  FAIL ' .. m); fails = fails + 1 end
end

-- placeholder_text: the icon string a text host injects. Its display width must
-- equal the requested cell count, or the host reserves the wrong space and the
-- image misaligns. (The load-bearing property for tabline layout.)
check(vim.fn.strdisplaywidth(kitty.placeholder_text(1, 1)) == 1, 'placeholder_text(1) -> width 1')
check(vim.fn.strdisplaywidth(kitty.placeholder_text(2, 1)) == 2, 'placeholder_text(2) -> width 2')
check(vim.fn.strdisplaywidth(kitty.placeholder_text(3, 1)) == 3, 'placeholder_text(3) -> width 3')

-- Each cell starts with the kitty Unicode placeholder code point (U+10EEEE);
-- the terminal paints the bound image over those cells.
check(vim.fn.char2nr(kitty.placeholder_text(2, 1)) == 0x10EEEE, 'placeholder cells use U+10EEEE')

-- hl_group_fg: the image id rides in the highlight's fg (the part bufferline
-- preserves when it rebuilds the per-tab icon group), with nocombine so it
-- isn't blended away.
local id = 1357
local name = kitty.hl_group_fg(id)
local def = vim.api.nvim_get_hl(0, { name = name })
check(def.fg == id, 'hl_group_fg encodes the image id in fg')
check(def.nocombine == true, 'hl_group_fg sets nocombine')

-- Stable + cached: same id -> same group name; different ids -> different names.
check(kitty.hl_group_fg(id) == name, 'hl_group_fg is idempotent for one id')
check(kitty.hl_group_fg(id + 1) ~= name, 'distinct ids -> distinct groups')

-- A tabline upload must use direct PNG chunks without changing the sidebar's
-- path-based image transfer; separate transfers prevent placed icons vanishing.
local sent = {}
local original_send = vim.api.nvim_ui_send
vim.api.nvim_ui_send = function(data) sent[#sent + 1] = data end
local path = vim.fn.tempname() .. '.png'
local bytes = string.rep('png-bytes', 1400)
local file = assert(io.open(path, 'wb'))
file:write(bytes)
file:close()
local direct_id = kitty.transmit_direct(path)
vim.api.nvim_ui_send = original_send
os.remove(path)
check(type(direct_id) == 'number', 'direct transfer allocates an image id')
check(#sent > 1, 'direct transfer chunks large PNG data')
local encoded = {}
for index, escape in ipairs(sent) do
  local control, payload = escape:match('^\027_G([^;]+);([^\027]+)\027\\$')
  check(control ~= nil and payload ~= nil, 'direct chunk is a Kitty graphics escape')
  if control then
    if index == 1 then
      check(control:find('t=d', 1, true) ~= nil and control:find('f=100', 1, true) ~= nil,
        'first chunk transfers PNG bytes directly')
      check(control:find('i=' .. direct_id, 1, true) ~= nil, 'first chunk carries image id')
    end
    check(control:find('m=' .. (index == #sent and '0' or '1'), 1, true) ~= nil,
      'continuation flag matches chunk position')
  end
  if payload then encoded[#encoded + 1] = payload end
end
check(vim.base64.decode(table.concat(encoded)) == bytes, 'direct transfer preserves PNG bytes')

if fails > 0 then print('FAILED: ' .. fails); os.exit(1) else print('test-kitty: ALL PASS') end
