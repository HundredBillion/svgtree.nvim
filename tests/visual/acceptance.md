# Native Explorer acceptance

The baseline is [reference.json](reference.json) and its VS Code screenshots
under [reference/](reference/). Those captures are reference input, not Sprite
parity evidence. The fixture can be materialized with
`python3 tests/visual/generate_fixture.py project DEST --revision final`.
The isolated launch recipe is in the root README and
`scripts/native-demo-init.lua`.

## Evidence status

| Gate | Status | Evidence or next check |
| --- | --- | --- |
| Unit and headless integration | Passed on Linux | Minimum and stable core suites; Neovim 0.13 full suite, including terminal graphics and converter checks |
| Ordinary Neovim, foot plain text | Passed on Linux | Physical terminal run; 11 rows and dotfiles visible |
| Ordinary Neovim, Ghostty graphics | Passed on Linux | Physical terminal run; raster icons visible |
| Sprite with ordinary `nvim` | Partial | Physical direct native harness passed 9 checks; public demo launch pending |
| Sprite with `sprite-nvim` wrapper | Partial | Physical direct native harness passed 9 checks; public demo launch pending |
| LazyVim daily-driver sequence | Partial | Automated ordinary and native wrapper paths passed seven checks each; by-hand sequence pending |
| VS Code visual parity | Pending | Capture matching states in opacity-free display, compare geometry and flat colors |
| Key/click-to-paint p95, structural updates, cold open | Pending | Record separate timings and compare warm p95 to 50 ms target |
| Asset upload and bounded rows | Pending | Record uploads per distinct icon per handle and row update counts |
| macOS GUI | Pending | Requires a macOS Sprite run |

The Linux physical evidence was captured outside the repository during
integration and will be imported with exact paths and conditions after the
final public demo run. Do not treat the direct harness checks as proof that
either documented launch path has passed.

## Manual matrix still to record

Run both native launch paths. Exercise absent Sprite API, failed initialization,
an occupied dock, plugin disconnect, search, external file changes, active-file
reveal, explicit `show_hidden = false`, close/reopen state, pane resize, divider
drag, and ordinary-editor suspend/resume. For failed opens, confirm an unsaved
editor buffer survives unchanged. Repeat the complete daily-driver sequence
using the real LazyVim setup, then record Linux and macOS GUI results separately.

Visual comparisons use the same fixture revision and state, scale 2, and an
opaque capture. Check geometry within one logical pixel, flat colors exactly,
and antialiased edges by eye. VS Code initially leaves `.github` un-compacted
until it is expanded; the native model discovers compact chains eagerly. Align
the expanded states before comparing rows.
