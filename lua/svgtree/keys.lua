local M = {}
local Keys = {}
Keys.__index = Keys

local function bindings(side)
  return {
    j='next', k='previous', h='parent', l='enter', ['<Down>']='next', ['<Up>']='previous',
    ['<Left>']='parent', ['<Right>']='enter', ['<Home>']='first', ['<End>']='last',
    ['<C-d>']='half_down', ['<C-u>']='half_up', gg='first', G='last',
    ['<CR>']='open', R='refresh', q='close', ['<Esc>']='close', ['/']='search',
    n='search_next', N='search_previous', [side == 'right' and '<C-w>h' or '<C-w>l']='focus_editor',
  }
end
local allowed = {}
for _, action in pairs(bindings()) do allowed[action] = true end
local aliases = {['<Space>']=' ', ['<Enter>']='<CR>', ['<Escape>']='<Esc>', ['<Backspace>']='<BS>'}
local function normalize_binding(key)
  assert(not key:find('%c'), 'native keymap cannot contain control characters')
  assert(not key:find('<[^>]*$'), 'malformed native key notation: ' .. key)
  for token in key:gmatch('<[^>]+>') do
    assert(vim.api.nvim_replace_termcodes(token,true,false,true) ~= token,
      'unknown native key notation: ' .. token)
  end
  for alias, canonical in pairs(aliases) do key=key:gsub(alias:gsub('([^%w])','%%%1'),canonical) end
  return key
end
function M.defaults(side) return vim.deepcopy(bindings(side)) end
function M.validate(overrides)
  if overrides == nil then return end
  assert(type(overrides)=='table', 'native keymaps must be a table')
  for key, action in pairs(overrides) do
    assert(type(key)=='string' and key~='', 'native keymap key must be nonempty text')
    assert(action == false or allowed[action], 'unknown native tree action: ' .. tostring(action))
    normalize_binding(key)
  end
end
function M.new(overrides, timeout_ms, side)
  M.validate(overrides)
  assert(timeout_ms == nil or (type(timeout_ms)=='number' and timeout_ms>=0), 'invalid native key timeout')
  local map = bindings(side)
  local normalized = {}
  for key, action in pairs(overrides or {}) do
    local canonical=normalize_binding(key)
    assert(normalized[canonical]==nil, 'duplicate native keymap: ' .. key)
    normalized[canonical]=action or false
  end
  for key, action in pairs(normalized) do map[key] = action or nil end
  for key, action in pairs(map) do
    if action then
      for other, other_action in pairs(map) do
        assert(not (other_action and key ~= other and other:sub(1,#key)==key),
          'ambiguous native keymap prefix: ' .. key)
      end
    end
  end
  return setmetatable({map=map, timeout=timeout_ms or vim.o.timeoutlen}, Keys)
end
function Keys:reset() self.pending=nil; self.since=nil end
local function token(event)
  if event.type ~= 'input' then return nil end
  local call = require('sprite.input').call(event)
  if not call or call.method ~= 'nvim_input' then return nil end
  local value = call.args[1]
  if value == '<lt>' then return '<' end
  return value
end
local function has_prefix(map, prefix)
  for sequence, action in pairs(map) do
    if action and #sequence > #prefix and sequence:sub(1,#prefix)==prefix then return true end
  end
  return false
end
function Keys:feed(event, now_ms)
  if event.type == 'blur' then self:reset(); return nil end
  local key = token(event)
  if not key then return nil end
  local pending, since = self.pending, self.since
  self:reset()
  if pending and now_ms - since < self.timeout then
    local combined = pending .. key
    if self.map[combined] then return self.map[combined] end
    if has_prefix(self.map,combined) then
      self.pending=combined; self.since=now_ms; return nil
    end
  end
  if has_prefix(self.map,key) then
    self.pending=key; self.since=now_ms; return nil
  end
  return self.map[key]
end
function M.search(rows, query)
  local matches = {}
  local needle = vim.fn.tolower(query or '')
  for _, row in ipairs(rows) do
    if vim.fn.tolower(row.text or ''):find(needle, 1, true) then matches[#matches+1]=row.id end
  end
  return matches
end
return M
