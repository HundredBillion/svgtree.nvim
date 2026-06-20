# svgtree.nvim

A minimal Neovim file explorer that renders **real SVG icons as images** — not font glyphs — using the **Kitty graphics protocol** on a terminal that speaks it.

> Font glyphs are one shape in one color per cell, so they can't show a two-tone icon (e.g. the blue-and-yellow Python logo). Real images can. `svgtree.nvim` is a proof that VSCode-style, full-color, multi-tone file icons are possible in a **terminal** Neovim — no GUI required.

The hard part of putting an image in a text buffer is keeping it welded to its line: absolute screen placement (what [`vim.ui.img`](https://github.com/neovim/neovim/pull/37914) does) isn't anchored to text, so a redraw wipes it and a scroll leaves it behind. svgtree.nvim sidesteps that by rendering through the Kitty graphics protocol's **Unicode-placeholder** mechanism: each icon is transmitted once, then drawn as ordinary buffer cells that the terminal paints the image over. Because the anchor *is* buffer text, the icon scrolls with its line and is repainted on every redraw for free — no fork, no core patch, no scroll/resize bookkeeping. Neovim's `vim.ui.img` is still used, but only as the capability probe that gates on the 0.13+ runtime.

## Status

⚠️ **Experimental.** `vim.ui.img` is itself marked experimental and its API may change. This is a working proof-of-concept, not a neo-tree replacement (yet).

## Requirements

- **Neovim ≥ 0.13** (for `vim.ui.img`; currently nightly)
- A terminal implementing the **Kitty graphics protocol**: [Kitty](https://sw.kovidgoyal.net/kitty/), [Ghostty](https://ghostty.org/), or [WezTerm](https://wezfurlong.org/wezterm/)
- An **SVG → PNG converter**: [`librsvg`](https://gitlab.gnome.org/GNOME/librsvg) (`rsvg-convert`, **recommended** — renders text/fonts reliably) or ImageMagick (`magick`, fine for shape-only packs)
  - macOS: `brew install librsvg` (or `brew install imagemagick`)

When graphics or a converter are unavailable, svgtree falls back to a text tag (`[python] foo.py`) so it stays usable.

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "HundredBillion/svgtree.nvim",
  opts = {},
  cmd = { "SvgTree", "SvgTreeToggle" },
  keys = {
    { "<leader>t", "<cmd>SvgTreeToggle<cr>", desc = "Toggle svgtree" },
  },
}
```

Or call `require("svgtree").setup()` from your config.

## Usage

| Command | Action |
|---|---|
| `:SvgTree [dir]` | Open the tree (defaults to cwd) |
| `:SvgTreeToggle [dir]` | Toggle the tree |

Inside the tree:

| Key | Action |
|---|---|
| `<CR>` / `l` | Expand/collapse a directory, or open a file |
| `h` | Collapse the directory under the cursor |
| `R` | Refresh |
| `q` | Close |

Run `:checkhealth svgtree` to verify your setup.

## Configuration

Defaults:

```lua
require("svgtree").setup({
  pack = nil,            -- nil = bundled set; a name = ~/.local/share/nvim/svgtree/packs/<name>; or an absolute pack dir
  icon = {
    width = 2,           -- icon footprint in cells
    height = 1,
    size_px = 40,        -- rasterized PNG size
    zindex = 50,
  },
  window = { width = 36, side = "left" },
  indent = 2,
  show_hidden = false,
  fallback_text = true,  -- show [id] tags when images are unavailable
})
```

### Using an icon pack

svgtree reads **any VSCode file-icon theme directly** — it ships a small original
starter set and reads a theme's own JSON in place; it stores no pack data.

**Install one (needs `curl` + `unzip`):**

```bash
scripts/install-theme.sh PKief.material-icon-theme material
scripts/install-theme.sh vscode-icons-team.vscode-icons vscode-icons
```

```lua
require("svgtree").setup({ pack = "material" })
```

These download the theme's `.vsix` from [Open VSX](https://open-vsx.org/) and
unpack it to `stdpath('data')/svgtree/packs/<name>/`.

**Bring your own:** point `pack` at any unpacked VSCode icon-theme directory —
including one already installed under `~/.vscode/extensions/`:

```lua
require("svgtree").setup({ pack = "/abs/path/to/an/unpacked/icon-theme" })
```

No import or conversion step — svgtree reads the theme's `iconDefinitions` and
`fileExtensions`/`fileNames`/`folderNames` directly. (It maps by extension, file
name, and folder name; VSCode `languageIds`, light/high-contrast variants, and
font-based icons are not used.)

## Use the icon engine in snacks.nvim / neo-tree

svgtree's icon machinery is a **host-agnostic engine** you can attach to an
existing explorer to get real SVG icons there — no need to switch to svgtree's
own tree. Call `require("svgtree").setup({})` once, then wire an adapter.

### snacks.nvim explorer

The adapter suppresses snacks' own glyph (keeping git/diagnostic decorations)
and overlays an anchored image in its place.

```lua
-- lua/plugins/snacks.lua
opts = {
  picker = {
    sources = {
      explorer = {
        format  = require("svgtree.adapters.snacks").format,
        on_show = require("svgtree.adapters.snacks").on_show,
      },
    },
  },
}
```

### neo-tree.nvim (experimental)

```lua
require("neo-tree").setup({
  default_component_configs = {
    icon = { provider = function(icon)        -- blank neo-tree's glyph, keep width
      icon.text, icon.highlight = "  ", "NeoTreeFileIcon"
    end },
  },
  event_handlers = {
    { event = "after_render", handler = require("svgtree.adapters.neotree").on_render },
  },
})
-- If the icon lands a cell off, tune it:
-- require("svgtree.adapters.neotree").setup({ col_offset = 1 })
```

Both require Neovim ≥ 0.13, a Kitty-graphics terminal, and a converter (see
Requirements). When unavailable, the adapters no-op and the host renders as
usual.

## How it works

1. **Resolve** each file/dir to an icon stem (`icons.lua`).
2. **Rasterize** that stem's SVG to a cached PNG at cell size (`raster.lua`, via rsvg-convert/ImageMagick). Each `(stem, size)` is converted at most once and reused from disk.
3. **Transmit + place** (`kitty.lua`): send each unique icon's PNG to the terminal once (by file path) and create a *virtual* Unicode-placeholder placement for it — an image id carried in a highlight's foreground color, the placement id in its underline color.
4. **Anchor** (`engine.lua`): for each visible line, draw the icon as an overlay extmark whose virtual text is Kitty placeholder cells (U+10EEEE) referencing that placement. The terminal paints the image over those cells. Since the cells are buffer text, the icon moves and repaints on its own — the engine just re-emits placeholder cells on a structural change. This engine is shared by svgtree's own tree (`render.lua`) and the snacks/neo-tree adapters (`adapters/`), and a `winlock` seam keeps the tree window from panning sideways so icons never slide off their anchor column.

## Roadmap

- [x] Read any VSCode file-icon theme directly (Material, vscode-icons, … via Open VSX)
- [x] Transmit each icon once and reuse its placement (Kitty Unicode-placeholder engine)
- [ ] Nerd Font glyph fallback (instead of text tags)
- [ ] Git status / diagnostics decorations
- [ ] Upstream: a buffer/extmark-anchored placement option for `vim.ui.img`

## Credits

Born from a deep-dive into whether VSCode-style SVG icons are possible in terminal Neovim. Built on [`vim.ui.img`](https://github.com/neovim/neovim/pull/37914) by [@chipsenkbeil](https://github.com/chipsenkbeil) and the Neovim team.

The Material icon pack is the [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme) by Philipp Kief and contributors ([MIT](https://github.com/material-extensions/vscode-material-icon-theme/blob/main/LICENSE.md)); vscode-icons is by the [vscode-icons team](https://github.com/vscode-icons/vscode-icons) (MIT). svgtree bundles neither — `scripts/install-theme.sh` fetches them from [Open VSX](https://open-vsx.org/) on demand and reads each theme in place.

## License

MIT © David Lee
