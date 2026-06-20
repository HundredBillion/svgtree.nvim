-- A tree window never pans sideways. This neutralizes every horizontal-scroll
-- input on the buffer and, as a safety net, snaps leftcol back to 0 if anything
-- still scrolls the window horizontally. One seam shared by svgtree's own view
-- and the host adapters, so the rule (incl. the Mac trackpad swipe handling)
-- can't drift between them.

local M = {}

-- The horizontal-scroll inputs to neutralize, including Mac trackpad horizontal
-- swipes (which arrive as ScrollWheelLeft/Right).
local HORIZONTAL_KEYS = {
  'zh', 'zl', 'zH', 'zL',
  '<ScrollWheelLeft>', '<ScrollWheelRight>',
  '<S-ScrollWheelLeft>', '<S-ScrollWheelRight>',
}

---Lock a window so it never scrolls horizontally.
---@param win integer window handle (the WinScrolled handler operates on it)
---@param buf integer buffer handle (keymaps are buffer-local)
---@param group? integer augroup id to own the WinScrolled autocmd; if omitted,
---  winlock creates its own group keyed to the buffer
function M.lock_horizontal(win, buf, group)
  for _, lhs in ipairs(HORIZONTAL_KEYS) do
    pcall(vim.keymap.set, 'n', lhs, '<Nop>', { buffer = buf, nowait = true, silent = true })
  end
  group = group or vim.api.nvim_create_augroup('svgtree_winlock_' .. buf, { clear = true })
  vim.api.nvim_create_autocmd('WinScrolled', {
    group = group,
    buffer = buf,
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      vim.api.nvim_win_call(win, function()
        local v = vim.fn.winsaveview()
        if v.leftcol and v.leftcol ~= 0 then
          v.leftcol = 0
          vim.fn.winrestview(v)
        end
      end)
    end,
  })
end

return M
