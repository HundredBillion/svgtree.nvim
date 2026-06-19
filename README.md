# svgtree.nvim

A minimal Neovim file explorer that renders **real SVG icons as images** — not font glyphs — using Neovim's native [`vim.ui.img`](https://github.com/neovim/neovim/pull/37914) API and a terminal that speaks the Kitty graphics protocol.

> Font glyphs are one shape in one color per cell, so they can't show a two-tone icon (e.g. the blue-and-yellow Python logo). Real images can. `svgtree.nvim` is a proof that VSCode-style, full-color, multi-tone file icons are possible in a **terminal** Neovim — no GUI required.

https://github.com/neovim/neovim/pull/37914 landed `vim.ui.img` in Neovim 0.13. The catch: it places images at **absolute screen coordinates** with no buffer anchoring, so icons don't follow text when you scroll. svgtree.nvim solves that with a small pure-Lua **anchoring shim** (recompute each visible line's screen position on scroll/resize and reposition its image) — which means no Neovim fork and no core patch are required.

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
  pack = nil,            -- path to an SVG icon pack; nil = bundled set
  icon = {
    width = 2,           -- icon footprint in cells
    height = 1,
    size_px = 40,        -- rasterized PNG size
    zindex = 50,
  },
  window = { width = 36, side = "left" },
  indent = 2,
  show_hidden = false,
  fallback_text = true,  -- show [stem] tags when images are unavailable
})
```

### Using the VSCode Material icon pack

The bundled icons are a small original starter set. To use richer icons, point `pack` at any directory of SVGs named `<stem>.svg` (matching the stems in `lua/svgtree/icons.lua`, e.g. `python.svg`, `typescript.svg`, `directory.svg`). A converter for the [VSCode Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme) pack is on the roadmap.

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
2. **Rasterize** that stem's SVG to a cached PNG at cell size (`raster.lua`, via rsvg-convert/ImageMagick).
3. **Place + anchor** (`engine.lua`): for each visible line, compute the icon's screen position with `screenpos`, draw it with `vim.ui.img.set`, and reposition/cull on scroll & resize. This engine is shared by svgtree's own tree (`render.lua`) and the snacks/neo-tree adapters (`adapters/`).

## Roadmap

- [ ] VSCode Material Icon Theme pack importer
- [ ] Nerd Font glyph fallback (instead of text tags)
- [ ] Transmit-each-icon-once optimization (reuse placements vs re-sending bytes)
- [ ] Git status / diagnostics decorations
- [ ] Upstream: a buffer/extmark-anchored placement option for `vim.ui.img`

## Credits

Born from a deep-dive into whether VSCode-style SVG icons are possible in terminal Neovim. Built on [`vim.ui.img`](https://github.com/neovim/neovim/pull/37914) by [@chipsenkbeil](https://github.com/chipsenkbeil) and the Neovim team.

## License

MIT © David Lee
