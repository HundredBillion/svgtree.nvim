# VS Code Explorer reference

`reference.json` is the canonical input for native view visual tests. Each state
names a PNG crop, a DOM row snapshot, its pixel and logical dimensions, and the
fixture revision visible in that capture. Colors are effective VS Code colors;
the list foreground entries inherit the sidebar foreground.

The project files are committed under `project/`. Git cannot store an empty
directory, so `generate_fixture.py` creates `empty folder` when materializing
the final or long-empty revision. The same script creates the separate 10,000
file performance fixture at test runtime. Its entries are not committed.

The reference was captured from VS Code 1.133.0 with Dark Modern, Material Icon
Theme 5.38.1, default zoom, a clean temporary profile, and a display scale of
2. The saved DOM measurements and font evidence are in `reference/`. The
`tree-search` capture contains the Explorer sidebar search input; the editor
Find screenshot from the capture session is intentionally excluded.

These captures are source measurements. They make no claim that Sprite matches
the reference yet.
