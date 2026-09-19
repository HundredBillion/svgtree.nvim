# Linux native Explorer captures

These are actual Sprite screenshots at display scale 2 from an isolated opaque
Wayland compositor. Source revisions: Sprite host `146d1eaf`, Sprite Neovim API
`b34271f`, svgtree `3896017`. Both launch paths use the public
`scripts/native-demo-init.lua` and an explicit temporary fixture, with no
changes to the user's normal Neovim configuration.

`ordinary/` is `sprite -e nvim`; `grid/` is
`sprite -e /path/to/sprite.nvim/bin/sprite-nvim`. Each PNG is a 290-logical-pixel
Explorer crop except `narrow/` and `wide/`. Its adjacent JSON records the
actual tree state and row projection at capture time. `initial/` has root,
expanded, selected, and hovered views. `final/` has Unicode/empty-directory,
unfocused-selection, and search views. The width variants show truncation and
layout at narrow and wide sizes. These states were set programmatically for
repeatability; pointer hover was real. They do not constitute manual keyboard
acceptance.

`physical-ordinary.json` and `physical-grid.json` each record 12 checks made
with actual Wayland input, including divider drag, header collapse, and
close/reopen restoration. `pixels.json` records exact flat color samples and
bounding boxes against the committed VS Code reference. Reproduce the checks
with `python3 tests/visual/verify_native_pixels.py` from the repository root;
ImageMagick's `magick` must be available. This checks the measured regions, not
every pixel or every interaction state. Antialiased edges need visual review.

`performance-ordinary.json` and `performance-grid.json` are the serial,
optimized-build 10,000-row measurements from the same source revisions.
Their p95 values are conservative input-to-presentation upper bounds and exceed
the 50-ms warm target. `structural-prior-*.json` and `scroll-prior-*.json` are
earlier physical checks made before the final source revisions; they record
external-change and scroll behavior but are not final-source performance proof.

The native tree eagerly discovers compact folder chains; VS Code's initial
`.github` remains un-compacted until expanded. Compare matching expanded states
when assessing row parity. Manual daily-driver and macOS GUI checks are still
pending.
