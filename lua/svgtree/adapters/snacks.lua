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
local capability = require('svgtree.capability')
local icons = require('svgtree.icons')
local text = require('svgtree.text')

local M = {}

-- Minimal local descriptions of the snacks.nvim picker shapes this adapter
-- reads from and writes to. svgtree only *optionally* integrates with snacks, so
-- its real types aren't available to the language server; these document exactly
-- the fields we touch -- including the `_svg_*` fields we inject ourselves.

---@class svgtree.snacks.Item
---@field file string
---@field dir? boolean
---@field open? boolean
---@field label? string
---@field parent? any
---@field status? any
---@field severity? any
---@field _svg_icon_col? integer injected by M.format for the engine to read

---@class svgtree.snacks.ListWin
---@field win integer
---@field buf integer

---@class svgtree.snacks.List
---@field win svgtree.snacks.ListWin
---@field visible svgtree.snacks.Item[]
---@field dirty boolean
---@field render function
---@field update function
---@field _svg_wrapped? boolean injected: render() wrapped once
---@field _svg_hlock? boolean injected: horizontal-scroll lock installed

---@class svgtree.snacks.PickerOpts
---@field formatters? table
---@field icons table

---@class svgtree.snacks.Picker
---@field list? svgtree.snacks.List
---@field opts svgtree.snacks.PickerOpts

-- picker -> engine handle (weak, so closed pickers get collected)
local attached = setmetatable({}, { __mode = 'k' })
-- picker -> true once attach() is ready to render text + icons together. format()
-- holds its lines blank until this flips, so the explorer's first visible
-- content already has icons (no text-then-icon pop). Keyed weakly by picker.
local ready = setmetatable({}, { __mode = 'k' })

---@param item svgtree.snacks.Item
---@return string? stem
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
---@param item svgtree.snacks.Item
---@param picker svgtree.snacks.Picker
function M.format(item, picker)
  -- Never probe here: this runs inside snacks' render loop, where a blocking
  -- probe would corrupt the write. Decide purely from cached state:
  --   * image-capable, not yet known-unsupported, and this picker isn't ready
  --     to draw icons -> HOLD: render a blank line. Showing filenames now and
  --     dropping icons in a moment later is the "pop" we're avoiding. attach()
  --     flips `ready` and re-renders, placing text + icons in one pass. (Held
  --     before requiring snacks: the blank line needs nothing from it.)
  --   * determined unsupported (or not capable) -> snacks' default glyphs.
  --   * ready + supported -> build the image line below.
  local determined_unsupported = capability.probed() and not capability.supported_cached()
  if capability.capable() and not determined_unsupported and not ready[picker] then
    return { { '' } }
  end
  local F = require('snacks.picker.format')
  if not capability.supported_cached() then
    return F.file(item, picker)
  end
  local ret = {} ---@type table[]
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
  -- column screenpos() can resolve (virtual text has none). The trailing space
  -- sits past the icon's `w` cells, so it reads as a gap between icon and
  -- filename (mirrors render.lua's own-tree slot) for VSCode-style breathing room.
  local w = ((picker.opts.formatters or {}).file or {}).icon_width or 2
  item._svg_icon_col = col
  add({ { string.rep(' ', w) .. ' ' } })

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
        return { { text.truncate(name, math.max(avail - 1, 1)), hl, field = 'file' } }
      end
      break
    end
  end
  add(fn)

  return ret
end

-- Attach the placement engine for this explorer. Called from on_show via
-- capability.on_resolved — i.e. only once support has been determined, so no
-- blocking probe happens here. For the auto-open case format() held the lines
-- blank until now; this renders the real content and places icons in the SAME
-- synchronous pass, so they appear together (no pop).
---@param picker svgtree.snacks.Picker
local function attach(picker)
  local ok = capability.supported_cached()
  local list = picker.list
  -- Need the list's window+buffer handles to attach; bail (format() falls back)
  -- if absent. Inlining the check narrows `list` to non-nil for the rest.
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
  if not config.options.resolved then
    config.setup({})
  end
  -- Window+buffer handles (guaranteed present by the guard above).
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
  -- re-anchor icons after every line rewrite it performs. Reconcile
  -- SYNCHRONOUSLY here (not via the debounced schedule): snacks "scrolls" by
  -- rewriting the buffer lines, and the icons ARE buffer cells now, so they must
  -- be re-emitted in the same pass — before the redraw that follows this render.
  -- A deferred reconcile would lag one frame behind every scroll step, blinking
  -- the icons off then back on. The reconcile is cheap (clear ns + set extmarks),
  -- so doing it inline is fine.
  if not list._svg_wrapped then
    local orig = list.render
    list.render = function(self, ...)
      local r = orig(self, ...)
      if attached[picker] then
        attached[picker].reconcile()
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
    require('svgtree.winlock').lock_horizontal(win, buf)
    list._svg_hlock = true
  end

  -- Render the real content (format() now emits filenames + image slots) and
  -- place icons in the SAME pass: flip `ready` so format stops holding, write
  -- the buffer lines, then a synchronous reconcile sends the image placements
  -- before we yield, so Neovim flushes text and icons in one screen update — no
  -- pop. (The wrapped render also schedules an async reconcile; harmless no-op.)
  ready[picker] = true
  pcall(function()
    list.dirty = true
    list:update({ force = true })
    handle.reconcile()
  end)
end

-- Run fn once the editor is past startup. The explorer's first show can happen
-- mid-startup, and placing a burst of images THEN is unreliable: while Neovim is
-- still painting the UI, the terminal drops most of the placements (only a few
-- stick) — which is exactly why icons appeared only after a manual reopen. A
-- reopen runs post-startup against an idle terminal, so the same burst sticks.
-- Deferring attach to here makes the first open behave like that reliable
-- reopen. On reopen vim_did_enter is already set, so this is just the next tick.
local function when_entered(fn)
  if vim.v.vim_did_enter == 1 then
    vim.schedule(fn)
  else
    vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function()
      vim.schedule(fn)
    end })
  end
end

---Hook for the explorer's `on_show`. Kicks off graphics detection (instant for
---known terminals; a no-op if already running), then attaches once BOTH startup
---is done and support is determined. format() holds the lines blank until attach
---flips `ready`, so the first visible content is text + icons together.
---@param picker svgtree.snacks.Picker
function M.on_show(picker)
  capability.detect()
  when_entered(function()
    capability.on_resolved(function()
      if picker and picker.list then
        attach(picker)
      end
    end)
  end)
end

return M
