-- Kitty graphics: Unicode-placeholder backend.
--
-- This is the robust alternative to vim.ui.img's absolute screen placement.
-- Instead of telling the terminal "paint image X at screen row/col" (which is
-- not anchored to text and is wiped by any full redraw, with nothing to
-- re-emit it), we:
--   1. transmit each unique icon's PNG once, keyed by an image id;
--   2. write special Unicode PLACEHOLDER cells (U+10EEEE) into the buffer as
--      extmark virtual text, with the image id carried in the cell's
--      foreground colour and the per-cell position carried as combining
--      diacritics.
-- The terminal then paints the image over those cells. Because the anchor is
-- ordinary buffer text, it moves with the line on scroll AND is repainted on
-- every redraw for free -- the two things the absolute path could not do.
--
-- Mirrors the protocol snacks.image uses on kitty/ghostty/wezterm.

local M = {}

-- The Unicode placeholder code point the kitty protocol reserves.
local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)

-- Combining-diacritic code points the protocol uses to encode a cell's
-- row/column within the image (index 1 == first row/col). Copied from the
-- kitty spec's published list (same set snacks.image uses).
-- stylua: ignore
local DIACRITICS = {
  0x0305,0x030D,0x030E,0x0310,0x0312,0x033D,0x033E,0x033F,0x0346,0x034A,0x034B,0x034C,0x0350,0x0351,0x0352,0x0357,0x035B,0x0363,0x0364,0x0365,0x0366,0x0367,0x0368,0x0369,0x036A,0x036B,0x036C,0x036D,0x036E,0x036F,0x0483,0x0484,0x0485,0x0486,0x0487,0x0592,0x0593,0x0594,0x0595,0x0597,0x0598,0x0599,0x059C,0x059D,0x059E,0x059F,0x05A0,0x05A1,0x05A8,0x05A9,0x05AB,0x05AC,0x05AF,0x05C4,0x0610,0x0611,0x0612,0x0613,0x0614,0x0615,0x0616,0x0617,0x0657,0x0658,0x0659,0x065A,0x065B,0x065D,0x065E,0x06D6,0x06D7,0x06D8,0x06D9,0x06DA,0x06DB,0x06DC,0x06DF,0x06E0,0x06E1,0x06E2,0x06E4,0x06E7,0x06E8,0x06EB,0x06EC,0x0730,0x0732,0x0733,0x0735,0x0736,0x073A,0x073D,0x073F,0x0740,0x0741,0x0743,0x0745,0x0747,0x0749,0x074A,0x07EB,0x07EC,0x07ED,0x07EE,0x07EF,0x07F0,0x07F1,0x07F3,0x0816,0x0817,0x0818,0x0819,0x081B,0x081C,0x081D,0x081E,0x081F,0x0820,0x0821,0x0822,0x0823,0x0825,0x0826,0x0827,0x0829,0x082A,0x082B,0x082C,0x082D,0x0951,0x0953,0x0954,0x0F82,0x0F83,0x0F86,0x0F87,0x135D,0x135E,0x135F,0x17DD,0x193A,0x1A17,0x1A75,0x1A76,0x1A77,0x1A78,0x1A79,0x1A7A,0x1A7B,0x1A7C,0x1B6B,0x1B6D,0x1B6E,0x1B6F,0x1B70,0x1B71,0x1B72,0x1B73,0x1CD0,0x1CD1,0x1CD2,0x1CDA,0x1CDB,0x1CE0,0x1DC0,0x1DC1,0x1DC3,0x1DC4,0x1DC5,0x1DC6,0x1DC7,0x1DC8,0x1DC9,0x1DCB,0x1DCC,0x1DD1,0x1DD2,0x1DD3,0x1DD4,0x1DD5,0x1DD6,0x1DD7,0x1DD8,0x1DD9,0x1DDA,0x1DDB,0x1DDC,0x1DDD,0x1DDE,0x1DDF,0x1DE0,0x1DE1,0x1DE2,0x1DE3,0x1DE4,0x1DE5,0x1DE6,0x1DFE,0x20D0,0x20D1,0x20D4,0x20D5,0x20D6,0x20D7,0x20DB,0x20DC,0x20E1,0x20E7,0x20E9,0x20F0,0x2CEF,0x2CF0,0x2CF1,0x2DE0,0x2DE1,0x2DE2,0x2DE3,0x2DE4,0x2DE5,0x2DE6,0x2DE7,0x2DE8,0x2DE9,0x2DEA,0x2DEB,0x2DEC,0x2DED,0x2DEE,0x2DEF,0x2DF0,0x2DF1,0x2DF2,0x2DF3,0x2DF4,0x2DF5,0x2DF6,0x2DF7,0x2DF8,0x2DF9,0x2DFA,0x2DFB,0x2DFC,0x2DFD,0x2DFE,0x2DFF,0xA66F,0xA67C,0xA67D,0xA6F0,0xA6F1,0xA8E0,0xA8E1,0xA8E2,0xA8E3,0xA8E4,0xA8E5,0xA8E6,0xA8E7,0xA8E8,0xA8E9,0xA8EA,0xA8EB,0xA8EC,0xA8ED,0xA8EE,0xA8EF,0xA8F0,0xA8F1,0xAAB0,0xAAB2,0xAAB3,0xAAB7,0xAAB8,0xAABE,0xAABF,0xAAC1,0xFE20,0xFE21,0xFE22,0xFE23,0xFE24,0xFE25,0xFE26,0x10A0F,0x10A38,0x1D185,0x1D186,0x1D187,0x1D188,0x1D189,0x1D1AA,0x1D1AB,0x1D1AC,0x1D1AD,0x1D242,0x1D243,0x1D244,
}

-- Lazily materialised diacritic chars (index -> string).
local diac = setmetatable({}, {
  __index = function(t, k)
    local cp = DIACRITICS[k]
    if not cp then
      return nil
    end
    t[k] = vim.fn.nr2char(cp)
    return t[k]
  end,
})

-- Image ids: 24-bit so the whole id fits in a cell's RGB foreground colour
-- (the protocol's standard single-byte-id-in-fg encoding; no high-byte
-- diacritic needed). Start above 0 and stay well under 2^24. Placement ids are
-- a separate namespace (carried in the underline colour). Both are plain
-- allocators here — callers cache the returned ids and decide when to (re)send,
-- so re-transmitting (e.g. on explorer reopen) is the caller's choice.
local next_id = 1000
local next_pid = 0
local hl_cache = {} ---@type table<string, string> "img:pid" -> highlight group

local function write(data)
  -- Prefer the UI channel (reaches the controlling terminal even through a
  -- remote/embedded UI); fall back to stdout if no UI is attached.
  if not (vim.api.nvim_ui_send and pcall(vim.api.nvim_ui_send, data)) then
    pcall(function()
      io.stdout:write(data)
    end)
  end
end

-- Build a kitty graphics escape sequence: \e_G<control>;<payload>\e\\
local function seq(control, payload)
  local parts = {}
  for k, v in pairs(control) do
    parts[#parts + 1] = k .. '=' .. v
  end
  local s = '\027_G' .. table.concat(parts, ',')
  if payload and payload ~= '' then
    s = s .. ';' .. payload
  end
  return s .. '\027\\'
end

---Transmit a PNG to the terminal (by file path) under a fresh image id.
---Always sends; the caller caches the returned id and reuses it.
---@param png string absolute path to a PNG file
---@return integer image_id
function M.transmit(png)
  next_id = next_id + 1
  local id = next_id
  -- t=f: transmit by file path (terminal reads the file). f=100: PNG.
  -- q=2: suppress the terminal's acknowledgement reply.
  write(seq({ a = 't', t = 'f', f = 100, i = id, q = 2 }, vim.base64.encode(png)))
  return id
end

---Create a *virtual* unicode-placeholder placement for an image (a=p, U=1).
---This is the step that binds placeholder cells to the transmitted image: a
---virtual placement occupies no screen cell itself; the image renders wherever
---cells referencing (image id, placement id) appear. Idempotent per image — we
---keep one placement and reuse it across every cell/line that shows the icon.
---@param image_id integer
---@param cols integer placement grid width in cells
---@param rows integer placement grid height in cells
---@return integer placement_id
function M.place(image_id, cols, rows)
  next_pid = next_pid + 1
  local pid = next_pid
  -- a=p: create placement. U=1: unicode-placeholder (virtual). C=1: do not
  -- move the cursor. c/r: the cell grid the image is scaled into.
  write(seq({ a = 'p', U = 1, i = image_id, p = pid, C = 1, c = cols, r = rows, q = 2 }))
  return pid
end

---Highlight group that carries the image id in its foreground colour and the
---placement id in its special (underline) colour — the two ids the terminal
---reads off each placeholder cell. Created once per (image, placement).
---@param image_id integer
---@param placement_id integer
---@return string hl_group
function M.hl_group(image_id, placement_id)
  local key = image_id .. ':' .. placement_id
  local name = hl_cache[key]
  if name then
    return name
  end
  name = 'SvgtreeImg' .. image_id .. '_' .. placement_id
  vim.api.nvim_set_hl(0, name, { fg = image_id, sp = placement_id, nocombine = true })
  hl_cache[key] = name
  return name
end

---Build the placeholder virtual-text chunk list for a single-row icon spanning
---`cols` cells of the given image. Each cell is PLACEHOLDER + row-diacritic +
---col-diacritic, all carrying the (image, placement) highlight group. Returns a
---value suitable for an extmark's `virt_text`.
---@param image_id integer
---@param placement_id integer
---@param cols integer number of cells wide
---@param row? integer image row index (1-based; default 1)
---@return table virt_text  -- { { text, hl_group } }
function M.virt_text(image_id, placement_id, cols, row)
  row = row or 1
  local hl = M.hl_group(image_id, placement_id)
  local cells = {}
  for c = 1, cols do
    cells[#cells + 1] = PLACEHOLDER .. (diac[row] or '') .. (diac[c] or '')
  end
  return { { table.concat(cells), hl } }
end

-- ── fg-only mode ───────────────────────────────────────────────────────────
-- For hosts that can't carry the placement id. The standard scheme above puts
-- the placement id in a cell's `sp` (underline) colour, but some hosts rebuild
-- the cell's highlight and copy only `fg` -- e.g. bufferline.nvim's
-- highlights.set_icon_highlight derives a per-tab icon group from the tab
-- background and reapplies `fg` only, dropping `sp`. These variants bind cells
-- to the image's DEFAULT placement (no placement id), so the image id alone --
-- carried in `fg` -- is enough.

---Create the image's *default* virtual placement (no placement id). Cells that
---carry only the image id bind to it. Call once per image, like M.place.
---@param image_id integer
---@param cols integer placement grid width in cells
---@param rows integer placement grid height in cells
function M.place_default(image_id, cols, rows)
  -- a=p, U=1 (unicode placeholder), C=1 (don't move cursor), no p= -> default
  -- placement. c/r: the cell grid the image is scaled into.
  write(seq({ a = 'p', U = 1, i = image_id, C = 1, c = cols, r = rows, q = 2 }))
end

---Highlight group carrying ONLY the image id (in fg); no placement id in sp.
---Pair with M.place_default. Created once per image.
---@param image_id integer
---@return string hl_group
function M.hl_group_fg(image_id)
  local key = 'fg:' .. image_id
  local name = hl_cache[key]
  if name then
    return name
  end
  name = 'SvgtreeImgFg' .. image_id
  vim.api.nvim_set_hl(0, name, { fg = image_id, nocombine = true })
  hl_cache[key] = name
  return name
end

---Placeholder cells for a single-row icon as a PLAIN STRING (not an extmark
---virt_text chunk), for hosts that inject the icon as ordinary text -- e.g. a
---tabline. Carries no sp; pair with place_default + hl_group_fg (apply that hl
---to this string). Each cell is PLACEHOLDER + row-diacritic + col-diacritic.
---@param cols integer number of cells wide
---@param row? integer image row index (1-based; default 1)
---@return string
function M.placeholder_text(cols, row)
  row = row or 1
  local cells = {}
  for c = 1, cols do
    cells[#cells + 1] = PLACEHOLDER .. (diac[row] or '') .. (diac[c] or '')
  end
  return table.concat(cells)
end

---Delete an image from the terminal by id (frees its data + placements).
---@param image_id integer
function M.delete(image_id)
  write(seq({ a = 'd', d = 'i', i = image_id, q = 2 }))
end

return M
