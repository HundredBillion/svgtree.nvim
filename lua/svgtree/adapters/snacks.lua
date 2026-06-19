-- Adapter: render svgtree's SVG image icons inside the snacks.nvim explorer.
--
-- snacks' explorer is a picker. Two facts make this clean:
--   * The list never truly scrolls — it rewrites buffer lines with the top
--     pinned to 1 — so buffer line `k` is always `picker.list.visible[k]`.
--   * The file-type glyph lives only in the `filename` formatter; git-status
--     and diagnostics are separate elements.
-- So we provide a `format` that rebuilds the line WITHOUT the glyph (keeping
-- git/diagnostics) and reserves a real-space slot for the image, and an
-- `on_show` that attaches the placement engine and reconciles after each
-- redraw.
--
-- Wire it into your snacks config:
--
--   require("svgtree").setup({})  -- once, anywhere
--   -- lua/plugins/snacks.lua
--   opts = {
--     picker = {
--       sources = {
--         explorer = {
--           format = require("svgtree.adapters.snacks").format,
--           on_show = require("svgtree.adapters.snacks").on_show,
--         },
--       },
--     },
--   }

local config = require('svgtree.config')
local engine = require('svgtree.engine')
local icons = require('svgtree.icons')

local M = {}

-- picker -> engine handle (weak, so closed pickers get collected)
local attached = setmetatable({}, { __mode = 'k' })

---@param item snacks.picker.explorer.Item
-- Trim a string to a display-cell budget, appending '…' if it overflows
-- (VSCode-style end-truncation). Width-aware, so multibyte names behave.
local function truncate(s, budget)
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

---@return string stem
local function stem_for(item)
  local name = vim.fn.fnamemodify(item.file, ':t')
  if item.dir then
    return icons.stem(name, 'dir', { open = item.open })
  end
  return icons.stem(name, 'file')
end

---Replacement explorer formatter: identical to snacks' default file format,
---minus the devicon, plus a reserved real-space slot we anchor the image into.
---Records the slot's byte column on the item for the engine to read.
---@param item snacks.picker.explorer.Item
---@param picker snacks.Picker
function M.format(item, picker)
  -- Never probe here: this runs inside snacks' render loop, where a blocking
  -- probe would corrupt the write. Decide purely from cached state:
  --   * image-capable but support not yet determined -> HOLD: render a blank
  --     line. Showing filenames now and dropping icons in a moment later is the
  --     "pop" we're avoiding. detect() resolves around first paint, then
  --     attach() forces a re-render and text + icons appear together. (Held
  --     before requiring snacks: the blank line needs nothing from it.)
  --   * determined unsupported (or not capable) -> snacks' default glyphs.
  --   * determined supported -> build the image line below.
  if engine.capable() and not engine.probed() then
    return { { '' } }
  end
  local F = require('snacks.picker.format')
  if not engine.supported_cached() then
    return F.file(item, picker)
  end
  local ret = {} ---@type snacks.picker.Highlight[]
  local col = 1 -- 1-indexed byte column of the next *real* character

  local function add(els)
    for _, el in ipairs(els) do
      ret[#ret + 1] = el
      if not el.virtual and type(el[1]) == 'string' then
        col = col + #el[1]
      end
    end
  end

  -- Mirror snacks.picker.format.file's prefix, tracking real byte width.
  if item.label then
    add({ { item.label, 'SnacksPickerLabel' }, { ' ', virtual = true } })
  end
  if item.parent then
    add(F.tree(item, picker))
  end
  if item.status then
    add(F.file_git_status(item, picker))
  end
  if item.severity then
    add(F.severity(item, picker))
  end

  -- The image anchors at this column. A *real* space slot gives it a byte
  -- column screenpos() can resolve (virtual text has none).
  local w = ((picker.opts.formatters or {}).file or {}).icon_width or 2
  item._svg_icon_col = col
  add({ { string.rep(' ', w) } })

  -- Filename with snacks' own glyph suppressed (we draw the image over it).
  local files = picker.opts.icons.files
  local saved = files and files.enabled
  if files then
    files.enabled = false
  end
  local fn = F.filename(item, picker)
  if files then
    files.enabled = saved
  end

  -- VSCode-style trailing-… truncation. snacks doesn't truncate basenames in
  -- filename_only mode (it emits a plain element), so convert that element into
  -- a width-resolving one: highlight.resolve() calls resolve(avail) with the
  -- width left after all other elements, and we trim to fit. (-1 leaves room
  -- for the 1-col selection prefix snacks prepends outside this line.)
  for _, el in ipairs(fn) do
    if type(el) == 'table' and el.field == 'file' and type(el[1]) == 'string' and not el.resolve then
      local name, hl = el[1], el[2]
      el[1] = ''
      el.field = nil
      el.resolve = function(avail)
        return { { truncate(name, math.max(avail - 1, 1)), hl, field = 'file' } }
      end
      break
    end
  end
  add(fn)

  return ret
end

-- Attach the placement engine for this explorer. Called from on_show via
-- engine.on_resolved — i.e. only once support has been determined, so no
-- blocking probe happens here. For the auto-open case format() held the lines
-- blank until now; this renders the real content and places icons in the SAME
-- synchronous pass, so they appear together (no pop).
---@param picker snacks.Picker
local function attach(picker)
  local ok = engine.supported_cached()
  local list = picker.list
  if not (list and list.win and list.win.win and list.win.buf) then
    return
  end
  if not ok then
    -- Determined unsupported (e.g. non-graphics terminal). format() held lines
    -- blank while pending; re-render so it now falls back to snacks' glyphs.
    pcall(function()
      list.dirty = true
      list:update({ force = true })
    end)
    return
  end
  if not config.options.pack then
    config.setup({})
  end
  local win, buf = list.win.win, list.win.buf

  if attached[picker] then
    attached[picker].detach()
  end

  local handle = engine.attach({
    win = win,
    buf = buf,
    name = 'svgtree_snacks_' .. buf,
    -- CursorMoved fires on navigation; the render wrap below covers
    -- scroll/filter/expand (snacks suppresses WinScrolled on the list).
    events = { 'CursorMoved' },
    resolve = function(line)
      local item = list.visible[line]
      if not item or not item.file then
        return nil
      end
      return { col = item._svg_icon_col or 1, stem = stem_for(item), key = item.file }
    end,
  })

  -- The list has no public render event; wrap the instance method once so we
  -- reconcile after every redraw it performs.
  if not list._svg_wrapped then
    local orig = list.render
    list.render = function(self, ...)
      local r = orig(self, ...)
      if attached[picker] then
        attached[picker].schedule()
      end
      return r
    end
    list._svg_wrapped = true
  end

  attached[picker] = handle

  -- VSCode-style: the explorer never pans sideways (and horizontal scroll would
  -- slide icons off their anchor column). Lock it on the list buffer — neutralize
  -- the horizontal-scroll inputs and snap leftcol back to 0. Once per list.
  if not list._svg_hlock then
    for _, lhs in ipairs({
      'zh', 'zl', 'zH', 'zL',
      '<ScrollWheelLeft>', '<ScrollWheelRight>',
      '<S-ScrollWheelLeft>', '<S-ScrollWheelRight>',
    }) do
      pcall(vim.keymap.set, 'n', lhs, '<Nop>', { buffer = buf, nowait = true, silent = true })
    end
    vim.api.nvim_create_autocmd('WinScrolled', {
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
    list._svg_hlock = true
  end

  -- Render the real content (format() now emits filenames + image slots) and
  -- place icons in the SAME pass: list:update writes the buffer lines, then a
  -- synchronous reconcile sends the image placements before we yield, so Neovim
  -- flushes text and icons in one screen update — no pop. (The wrapped render
  -- also schedules an async reconcile; it's a harmless no-op reposition.)
  pcall(function()
    list.dirty = true
    list:update({ force = true })
    handle.reconcile()
  end)
end

---Hook for the explorer's `on_show`. Kicks off async graphics detection (a
---no-op if already running or resolved) and attaches once support is known.
---While detection is pending, format() holds the lines blank, so the explorer's
---first visible content is text + icons together rather than text then a pop-in.
---@param picker snacks.Picker
function M.on_show(picker)
  engine.detect()
  engine.on_resolved(function()
    if picker and picker.list then
      attach(picker)
    end
  end)
end

return M
