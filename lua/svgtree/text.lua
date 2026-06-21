-- Shared text helpers for the tree view and the host adapters. Kept in one
-- place so the view (render.lua) and the snacks/neo-tree adapters truncate
-- names identically.

local M = {}

-- Trim a string to a display-cell budget, appending '…' if it overflows
-- (VSCode-style end-truncation). Width-aware, so multibyte names behave.
---@param s string
---@param budget integer display cells available
---@return string
function M.truncate(s, budget)
  if budget <= 0 then
    return ''
  end
  if vim.fn.strdisplaywidth(s) <= budget then
    return s
  end
  if budget == 1 then
    return '…'
  end
  local target = budget - 1 -- room for the ellipsis (1 cell)
  local n = vim.fn.strchars(s)
  local out = s
  while n > 0 and vim.fn.strdisplaywidth(out) > target do
    n = n - 1
    out = vim.fn.strcharpart(s, 0, n)
  end
  return out .. '…'
end

return M
