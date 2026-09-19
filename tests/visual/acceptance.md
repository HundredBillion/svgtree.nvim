# Native Explorer acceptance record

The [VS Code reference](reference.json) was captured at scale 2 with Dark
Modern and Material Icon Theme 5.38.1. The committed
[Linux Sprite captures](native-linux/README.md) bind Sprite host `146d1eaf`,
Sprite Neovim API `b34271f`, and svgtree `3896017`. Both public launch methods
use `scripts/native-demo-init.lua` and a temporary fixture. The fixture command
is `python3 tests/visual/generate_fixture.py project DEST --revision final`.

| Gate | Result and scope |
| --- | --- |
| Minimum/stable core and Neovim 0.13 full suites | Passed on Linux. The full suite exercised terminal converter and graphics tests. |
| Public Sprite launch with ordinary `nvim` | Passed 12 actual Wayland input checks in [physical-ordinary.json](native-linux/physical-ordinary.json). |
| Public Sprite launch with `sprite-nvim` wrapper | Passed the same 12 checks in [physical-grid.json](native-linux/physical-grid.json). |
| Non-Sprite terminal | Passed in [foot](terminal-linux/foot.json) with text tags and no graphics, and [Ghostty](terminal-linux/ghostty.json) with raster icons; both show 11 rows including dotfiles and load no Sprite API. |
| Actual LazyVim configuration | Automated seven-check ordinary and wrapper runs passed, including editor search and picker return. By-hand daily-driver sequence pending. |
| Native visual measurements | Six flat colors in each launch mode match exactly. Selected label, heading, and disclosure-chevron bounding boxes are within one logical pixel of the reference; [pixels.json](native-linux/pixels.json) and `python3 tests/visual/verify_native_pixels.py` reproduce these checks. |
| 10,000-row interaction and uploads | One row upload, 81 state updates, and four distinct icons uploaded once each per handle in each mode. Warm key/click presentation upper-bound p95 exceeded 50 ms; target **not demonstrated**. |
| macOS GUI and manual daily-driver | Pending. |

The 10,000-row measurements used an optimized Sprite build and actual Wayland
input. Their clock starts before input submission and ends at the compositor
presentation timestamp for a pixel-confirmed selection. It includes subprocess
startup and waiting for a capture frame, so the p95 figures are conservative
upper bounds, not the renderer's isolated cost. The serial run measured ordinary
key/click p95 at 56.57/56.79 ms and wrapper key/click p95 at 56.60/56.84 ms,
40 samples each ([ordinary](native-linux/performance-ordinary.json),
[wrapper](native-linux/performance-grid.json)). Results depend on display load;
a concurrent screenshot run had substantially higher upper bounds. A separate
four-key profile after the state-only projection fix measured 9.97 ms total in
controller publishing, 3.67 ms maximum, and zero row/asset projection or
watcher reconfiguration calls. This does not prove the under-50-ms paint goal.

Cold launch-to-ready was observed once at 1806.45 ms ordinary and 452.15 ms
wrapper in the final serial run; an earlier run measured about 402 ms in each
mode. These are observations, not stable limits. A prior 10,000-to-10,001-file
external update reached rows acknowledgement within 327.29/316.65 ms ordinary/
wrapper, including watcher debounce, reprojection, transport, and observer
polling. Those [structural results](native-linux/structural-prior-ordinary.json)
precede the final source revisions and are kept separate from cold opening and
pixel presentation.

The public physical checks cover navigation, clicks, search acceptance, divider
drag, project-header collapse, close, and restored selection/expansion/width.
Earlier real 10,000-row runs covered offscreen `G`, wheel scrolling, independent
scroll/selection restore, and external file creation; see the prior scroll
checks in `native-linux/`. Headless tests cover missing API, failed or occupied
dock fallback, native suspend/resume, active-file reveal, explicit
`show_hidden = false`, and concise unsaved-edit refusal. The final-source
physical refusal check passed for both launch modes; plugin disconnect and
ordinary-editor suspend/resume remain pending.

The screenshots show the actual native states, but full screenshot parity is
not claimed. VS Code initially leaves `.github` un-compacted until expansion;
the native model discovers the compact chain eagerly. The reference also has
Explorer actions and lower Outline/Timeline sections outside the measured
native tree surface. Match expanded states when comparing rows. Antialiased
edges have been inspected visually; the region checks above do not assert every
pixel of every captured state.
