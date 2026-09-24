-- Keep bufferline.nvim's tabs clear of the terminal tree.
--
-- The terminal tree is an ordinary window at the editor's left edge, so the
-- tabline spans it unless bufferline is given an offset for its filetype.
-- Sprite's native Explorer sits outside Neovim's window grid and needs none,
-- but the terminal renderer (Ghostty, kitty, or Sprite's own fallback) does.
-- Registering it here means no host config has to remember to.

local M = {}
local did_watch = false

-- Add a `svgtree` offset to bufferline's live config unless one is there.
-- Reads bufferline only if it is already loaded; never loads it.
local function ensure()
  local bufferline = package.loaded['bufferline.config']
  local options = type(bufferline) == 'table' and bufferline.options
  if type(options) ~= 'table' then return end
  options.offsets = options.offsets or {}
  for _, offset in ipairs(options.offsets) do
    if offset.filetype == 'svgtree' then return end
  end
  table.insert(options.offsets, {
    filetype = 'svgtree',
    text = 'SVGTree',
    highlight = 'Directory',
    text_align = 'left',
  })
end

---Register the offset now and again whenever bufferline re-runs its setup,
---which rebuilds its config and then sets 'tabline'. Idempotent.
function M.ensure_offset()
  ensure()
  if did_watch then return end
  did_watch = true
  vim.api.nvim_create_autocmd('OptionSet', {
    group = vim.api.nvim_create_augroup('svgtree_tabline', { clear = true }),
    pattern = 'tabline',
    callback = ensure,
  })
end

return M
