<img width="449" height="387" alt="Screenshot 2026-09-19 at 2 25 45 PM" src="https://github.com/user-attachments/assets/35682a88-4ec1-4ee7-bee0-bd2e07d98052" />

# svgtree.nvim

**Use VS Code SVG file icons in Sprite's native Explorer or terminal Neovim.**

Sprite opens a native, resizable Explorer beside Neovim. Ordinary Neovim keeps
the terminal tree and its image or text icon fallback. The native tree uses a
pinned Material Icon Theme and Dark Modern colors by default; the terminal tree
keeps the bundled starter icons unless you choose a pack.

## Native Explorer in Sprite

The VS Code-like Explorer is available when Neovim runs inside
[Sprite](https://github.com/HundredBillion/sprite.nvim). Sprite supplies the
native, resizable sidebar; svgtree supplies the VS Code-style layout, system
font, spacing, Material icons, tree state, and navigation. In Ghostty or any
other terminal, the same configuration automatically uses svgtree's terminal
renderer instead.

![VS Code-like svgtree native Explorer](tests/visual/reference/expanded-src.png)



### LazyVim setup

Install [Sprite](https://github.com/HundredBillion/sprite.nvim), then add this
file to your LazyVim configuration. It makes svgtree the only file explorer:
it disables Snacks Explorer's automatic directory view, opens svgtree with
`<leader>e`, and keeps focus navigation working between the editor and
Sprite's native sidebar. With LazyVim's default leader, `<leader>` is Space.

```lua
-- ~/.config/nvim/lua/plugins/svgtree.lua
return {
  -- Keep Snacks' other features, but do not use its Explorer.
  {
    "folke/snacks.nvim",
    opts = { explorer = { enabled = false } },
    keys = {
      { "<leader>e", false },
      { "<leader>E", false },
    },
  },
  {
    "HundredBillion/svgtree.nvim",
    dependencies = { "HundredBillion/sprite.nvim" },
    opts = function()
      local in_sprite = vim.env.SPRITE_SURFACE_SOCKET ~= nil
      return {
        renderer = in_sprite and "sprite" or "terminal",
        pack = in_sprite and nil or "material",
        -- Lets Space, then e close the focused native sidebar.
        native = { mappings = { ["<Space>e"] = "close" } },
      }
    end,
    keys = {
      {
        "<leader>e",
        function() require("svgtree").toggle(LazyVim.root()) end,
        desc = "SVGTree Explorer",
      },
      {
        "<C-h>",
        function()
          local tree = require("svgtree")
          if not tree.focus("left") then vim.cmd("wincmd h") end
        end,
        desc = "Focus left window or SVGTree",
      },
      {
        "<C-l>",
        function()
          local tree = require("svgtree")
          if not tree.focus("right") then vim.cmd("wincmd l") end
        end,
        desc = "Focus right window or SVGTree",
      },
    },
  },
}
```

For the default left sidebar, press `<C-l>` to move from Sprite's Explorer to
the editor and `<C-h>` to return. `<leader>e` opens or closes svgtree from an
editor buffer; Space followed by `e` closes it while the native sidebar has
focus. No Shift is required for Ctrl-H or Ctrl-L.

Install `svgtree.nvim` and put the optional `sprite.nvim` plugin API on
Neovim's runtime path for native Sprite support. Ordinary Neovim needs only
`svgtree.nvim`. Call `require('svgtree').setup({})` and open it with
`:SvgTree [dir]` or `:SvgTreeToggle [dir]`. Sprite chooses the native view when
its dock features are available. `renderer = 'sprite'` requests native and
reports the reason when it must fall back; `renderer = 'terminal'` always uses
the terminal tree. A failed native open preserves the editor's unsaved buffers
and opens the terminal tree for the same root.

For an isolated checkout demo, first materialize the visual fixture and set
explicit checkout paths:

```bash
python3 tests/visual/generate_fixture.py project /tmp/svgtree-visual-project --revision final
export SVGTREE_CHECKOUT="$PWD"
export SVGTREE_API_CHECKOUT=/absolute/path/to/sprite.nvim
export SVGTREE_FIXTURE=/tmp/svgtree-visual-project
sprite -e nvim -u "$SVGTREE_CHECKOUT/scripts/native-demo-init.lua"
# Alternatively, launch with the plugin's own Neovim wrapper:
sprite -e "$SVGTREE_API_CHECKOUT/bin/sprite-nvim" -u "$SVGTREE_CHECKOUT/scripts/native-demo-init.lua"
```

The demo init changes only that Neovim process. The native width is measured in
logical pixels (`native.width = 280` by default); the terminal width is measured
in cells (`window.width = 36`). The demo uses 290 logical pixels to match the
recorded reference; set `SVGTREE_NATIVE_WIDTH` for another capture width. Both
trees show dotfiles by default; set
`show_hidden = false` to hide them, including during search and auto-reveal.
The native tree watches the root and expanded directories, refreshes external
changes, and reveals the active file. It keeps expansion, selection, scroll,
and separate native/terminal widths for a root during the Neovim session.

Native keys: `j`/`k` or arrows move; `h`/`l` collapse and enter; `gg`/`G`
move to the ends; `<C-d>`/`<C-u>` scroll; `/` searches filenames literally;
`n`/`N` move between matches; `.` focuses the selected directory (or a file's
directory); `<BS>` moves the root to its parent; `R` refreshes; `q` or `<Esc>`
closes. `<CR>` opens a file and focuses the editor. For a left sidebar,
`<C-l>`, `<C-w>l`, and `<C-w><C-l>` also focus the editor; use the matching
`h` forms for a right sidebar. A single click opens a file while keeping tree
focus; a double click focuses the editor. Set
`native.mappings` to map a key to an action or `false` to remove it, for
example:

```lua
require('svgtree').setup({ native = { mappings = { ['<Space>'] = 'enter', j = false } } })
```

Because a native sidebar is not a Neovim split, make your editor-side window
mappings call `focus(side)` before falling back to `:wincmd`. This keeps direct
`<C-h>`/`<C-l>` navigation working in both directions:

```lua
local tree = require('svgtree')
local function focus(side, wincmd)
  return function()
    if not tree.focus(side) then vim.cmd('wincmd ' .. wincmd) end
  end
end
vim.keymap.set('n', '<C-h>', focus('left', 'h'))
vim.keymap.set('n', '<C-l>', focus('right', 'l'))
```

To use `<leader>e` to open and close the tree with Space as your leader, bind
it in both places. The native sidebar owns keyboard focus while it is open,
so a Neovim mapping alone cannot receive the second press:

```lua
-- Set vim.g.mapleader = ' ' before loading plugins.
local tree = require('svgtree')
tree.setup({ native = { mappings = { ['<Space>e'] = 'close' } } })
vim.keymap.set('n', '<leader>e', function()
  tree.toggle(vim.uv.cwd())
end, { desc = 'Toggle SVGTree Explorer' })
```

The Neovim mapping opens or closes the terminal tree and opens the native tree;
the native mapping closes the focused native tree. Use the corresponding key
sequence in `native.mappings` if your leader is different.

See [visual acceptance](tests/visual/acceptance.md) for reference captures and
the current platform and manual verification status.

## The problem this solves

I've always been bothered that I can't use my favorite VSCode SVG file icons in Neovim.

Why can't we use svg icons in Neovim? Because terminals can't display SVG. So we're stuck with font glyphs, which can only render a boring one-color icon. The blue-and-yellow Python logo, the colorful Material icons, the whole VSCode look is impossible... until now.

svgtree.nvim fixes that. It renders the **actual SVG icons as real, full-color images**, welded to each line of the tree, using the Kitty graphics protocol. Install it and your VSCode icons show up in Neovim — no GUI required.

#### Before — font glyphs

![Before: flat, single-color font glyphs](assets/screenshots/before.png)

#### After — real SVG icons

![After: full-color SVG file icons](assets/screenshots/after.png)

> The terminal image path uses Neovim's experimental `vim.ui.img` capability probe.

## Install

**Terminal image prerequisites** — the terminal renders image icons when all three are present. Otherwise it uses text tags such as `[python] foo.py`. Sprite's native icons do not need these terminal prerequisites.

- **Neovim ≥ 0.13** — currently nightly. Install it and launch it as `nvim-nightly`.
- **A terminal that speaks the Kitty graphics protocol** — [Ghostty](https://ghostty.org/), [Kitty](https://sw.kovidgoyal.net/kitty/), or [WezTerm](https://wezfurlong.org/wezterm/).
- **An SVG → PNG converter** — `rsvg-convert` (recommended, renders fonts reliably): `brew install librsvg`. ImageMagick (`magick`) also works.

**The plugin** — with [lazy.nvim](https://github.com/folke/lazy.nvim), create a new file at `~/.config/nvim/lua/plugins/svgtree.lua` containing:

```lua
-- ~/.config/nvim/lua/plugins/svgtree.lua
return {
  "HundredBillion/svgtree.nvim",
  opts = {},
  cmd = { "SvgTree", "SvgTreeToggle" },
}
```

(lazy.nvim auto-loads every `.lua` file under `~/.config/nvim/lua/plugins/`, so the filename is up to you — `svgtree.lua` just keeps things tidy.)

No default keymap is set — bind `:SvgTreeToggle` to whatever key you like, e.g. add `keys = { { "<leader>t", "<cmd>SvgTreeToggle<cr>", desc = "Toggle svgtree" } }` to the spec above.

The terminal tree gets the bundled starter set. For a custom theme, see [Icon packs](#icon-packs) below.

## Use it

1. Open a project using the nightly Neovim variant:

   ```bash
   nvim-nightly .
   ```

2. Open the tree:

   ```vim
   :SvgTree
   ```

   Already using the snacks.nvim explorer? You don't need svgtree's tree —
   wire the adapter (see [Use the icon engine in snacks.nvim / neo-tree](#use-the-icon-engine-in-snacksnvim--neo-tree))
   and your icons appear in the explorer you already open (e.g. `<leader>e`).

3. **You should see your icons!**

If you see text tags (`[python] foo.py`) instead of images, run `:checkhealth svgtree` — it tells you exactly which prerequisite above is missing.

Inside the tree:

| Key | Action |
|---|---|
| `<CR>` / `l` | Expand/collapse a directory, or open a file |
| `h` | Collapse the directory under the cursor |
| `R` | Refresh |
| `q` | Close |

Commands: `:SvgTree [dir]` opens the tree (defaults to cwd); `:SvgTreeToggle [dir]` toggles it.

## Icon packs

svgtree reads **VS Code file-icon themes directly**. It bundles the original
terminal starter set and Material Icon Theme 5.38.1 for the native default.
An explicit `pack` selection applies to both renderers. Theme association keys
can match a filename or its immediate parent and filename, case insensitively.

**Install a theme** (needs `curl` + `unzip`):

```bash
scripts/install-theme.sh PKief.material-icon-theme material
scripts/install-theme.sh vscode-icons-team.vscode-icons vscode-icons
```

These fetch the theme's `.vsix` from [Open VSX](https://open-vsx.org/) and unpack it to `stdpath('data')/svgtree/packs/<name>/`. Then select it:

```lua
require("svgtree").setup({ pack = "material" })
```

**Bring your own:** point `pack` at any unpacked VSCode icon-theme directory — including one already under `~/.vscode/extensions/`:

```lua
require("svgtree").setup({ pack = "/abs/path/to/an/unpacked/icon-theme" })
```

No import or conversion step — svgtree reads the theme's `iconDefinitions` plus its `fileExtensions`/`fileNames`/`folderNames` mappings directly. (VSCode `languageIds`, light/high-contrast variants, and font-based icons are not used.)

## Configuration

Defaults:

```lua
require("svgtree").setup({
  pack = nil,            -- nil = native Material / terminal starter; a name or absolute pack path overrides both
  icon = {
    width = 2,           -- icon footprint in cells
    height = 1,
    size_px = 40,        -- rasterized PNG size
    zindex = 50,
  },
  window = { width = 36, side = "left" },
  indent = 2,
  show_hidden = true,   -- show dotfiles; explicit false also applies to search and reveal
  renderer = "auto",    -- auto | sprite | terminal
  native = { width = 280, compact_folders = true, mappings = {} }, -- logical pixels
  fallback_text = true,  -- show [id] tags when images are unavailable
})
```

## Use the icon engine in snacks.nvim / neo-tree / bufferline

svgtree's icon machinery is a **host-agnostic engine** you can attach to an existing explorer — or the bufferline tabline — to get real SVG icons there, no need to switch to svgtree's own tree. Call `require("svgtree").setup({})` once, then wire an adapter.

### snacks.nvim explorer

The adapter suppresses snacks' own glyph (keeping git/diagnostic decorations) and overlays an anchored image in its place.

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

### bufferline.nvim (tabs)

Show each buffer's icon on its tab, matching the explorer. The tabline isn't a buffer, so this adapter doesn't use the overlay engine — it returns the icon as Kitty placeholder text + a highlight whose foreground colour carries the image id, via bufferline's `get_element_icon` hook.

```lua
-- lua/plugins/bufferline.lua
require("svgtree.adapters.bufferline").setup() -- once; pre-warms tab icons
opts = {
  options = {
    -- Required: the image id rides in the icon highlight's fg, so color_icons
    -- must stay on (color_icons = false forces fg = NONE and breaks the icon).
    color_icons = true,
    get_element_icon = function(element)
      -- Returns nil on stable nvim / non-graphics terminals, so bufferline
      -- falls back to its usual glyph (e.g. mini.icons / nvim-web-devicons).
      return require("svgtree.adapters.bufferline").get_element_icon(element)
    end,
  },
}
```

All three require the same prerequisites as the main tree. When they're unavailable, the adapters no-op and the host renders as usual.

## How it works

The hard part of putting an image in a text buffer is keeping it welded to its line: absolute screen placement (what [`vim.ui.img`](https://github.com/neovim/neovim/pull/37914) does) isn't anchored to text, so a redraw wipes it and a scroll leaves it behind. svgtree sidesteps that by drawing through the Kitty graphics protocol's **Unicode-placeholder** mechanism — each icon is transmitted once, then drawn as ordinary buffer cells the terminal paints the image over. Because the anchor *is* buffer text, the icon scrolls with its line and repaints on every redraw for free.

1. **Resolve** each file/dir to an icon stem (`icons.lua`).
2. **Rasterize** that stem's SVG to a cached PNG at cell size (`raster.lua`, via rsvg-convert/ImageMagick). Each `(stem, size)` is converted at most once and reused from disk.
3. **Transmit + place** (`kitty.lua`): send each unique icon's PNG to the terminal once and create a *virtual* Unicode-placeholder placement for it.
4. **Anchor** (`engine.lua`): for each visible line, draw the icon as an overlay extmark whose virtual text is Kitty placeholder cells (U+10EEEE). The terminal paints the image over those cells; since they're buffer text, the icon moves and repaints on its own. This engine is shared by svgtree's own tree (`render.lua`) and the snacks/neo-tree adapters, with a `winlock` seam keeping the window from panning sideways so icons never slide off their anchor column.

`vim.ui.img` is still used — but only as the capability probe that gates on the 0.13+ runtime.


## Credits

Born from a deep-dive into whether VSCode-style SVG icons are possible in terminal Neovim. Built on [`vim.ui.img`](https://github.com/neovim/neovim/pull/37914) by [@chipsenkbeil](https://github.com/chipsenkbeil) and the Neovim team.

The bundled Material icons are [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme) 5.38.1 by Philipp Kief and contributors ([MIT](https://github.com/material-extensions/vscode-material-icon-theme/blob/main/LICENSE.md)). [vscode-icons](https://github.com/vscode-icons/vscode-icons) is by the vscode-icons team (MIT); `scripts/install-theme.sh` can fetch custom packs from [Open VSX](https://open-vsx.org/).

The native disclosure chevrons are adapted from Microsoft's [Codicons](https://github.com/microsoft/vscode-codicons) ([CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)); see [source and changes](assets/CODICONS-NOTICE.md).

## License

MIT © David Lee
