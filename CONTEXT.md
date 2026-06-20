# svgtree.nvim — Domain Glossary

Canonical vocabulary for icon resolution and packs. Glossary only — no
implementation detail. Keep terms here consistent with the code and docs.

## Pack

A named set of file/folder icons a user can select, used **in place**: an
unpacked VSCode icon-theme directory (a theme JSON plus its SVGs). Either the
**bundled starter** (ships in the repo) or an **installed pack** in the user's
data dir, or any absolute path (e.g. an extension already under
`~/.vscode/extensions/`). Selected via the `pack` config value: `nil` = bundled,
a bare name = an installed pack, an absolute path = a pack directory anywhere.

## Bundled starter

svgtree's small, original icon set that ships in the repo (`assets/icons/`),
expressed as a committed VSCode-style **theme** (`icon-theme.json`). Loaded by
the same code as any pack, and the fallback used when a selected pack fails to
load.

## Theme

The VSCode file-icon-theme JSON at the heart of a pack: `iconDefinitions`
(id → SVG path) plus associations (`file`, `folder`, `folderExpanded`,
`fileExtensions`, `fileNames`, `folderNames`, `folderNamesExpanded`). svgtree
reads it directly — there is no svgtree-specific pack format.

## Resolver

The pure logic that turns a filesystem entry (name + dir/file kind + open state)
into an **iconId** from the theme, or into *no icon*. VSCode-faithful: an
expanded-folder default falls back to the folder default; unmatched or
font-only/missing entries resolve to no icon.

## iconId

A key into the theme's `iconDefinitions`. The resolver yields an iconId; the
raster step turns its `iconPath` (resolved against the pack dir) into a cached
image. The engine transmits one image per unique iconId.
