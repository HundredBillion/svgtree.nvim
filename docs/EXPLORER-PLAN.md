# A differentiated Neovim file explorer — design plan

> Status: design draft. This is the plan for a *full* explorer, distinct from
> the `svgtree` proof-of-concept and the reusable icon engine in `lua/svgtree/`.

## Why build at all (the demand finding)

Research into neo-tree, snacks, and community sentiment landed on an
uncomfortable but clarifying conclusion:

- There is **no demand for a generic "best of both" explorer.** The ecosystem
  is consolidating onto snacks; the category is saturated with low-traction
  clones; "we have enough file trees" is a real sentiment.
- New explorers that win do so by **changing the paradigm** (oil.nvim: the
  filesystem as an editable buffer — ~6.6k stars, no clone fatigue).
- The one **unsolved, maintainer-acknowledged gap** is **fast + accurate git
  status on large / monorepo repositories.** Wanted everywhere, solved nowhere.
- SVG image icons are a genuine **novelty** but not a top community demand —
  they're a *signature*, not a *reason to switch*.

So a defensible product stands on three legs, none sufficient alone:

| Leg | Role | Source of the idea |
|---|---|---|
| **Git-correct on monorepos** | the *demand* — a reason to switch | acknowledged gap |
| **A sharper interaction model** | the *adoption hook* | oil.nvim's lesson |
| **Real SVG icons** | the *signature* — instantly recognizable | our engine |

## The git problem, precisely

Every explorer colors filenames by git state and rolls counts onto folders.
They all do it the same way: shell out to `git status --porcelain` for the
**whole repo**, parse it into a `path → status` map, and re-run on save/focus/
timer. That design fails on big repos three ways:

1. **Whole-repo, not what's visible.** Cost scales with repo size, not the
   handful of lines on screen. On a monorepo `git status` alone is 100s of ms
   to seconds; running it per save/focus thrashes.
2. **Staleness.** Commit/stash/checkout in an external terminal and the cache
   lies — files show "modified" that you already committed. The plugin only
   knows about changes it caused.
3. **The fixes fight.** "Refresh more often" cures staleness but reintroduces
   lag. Nobody has threaded the needle.

### What "solved" looks like

- Treat git state as a **watched data source**, not a polled command. Put a
  filesystem watcher on `.git/` (index, `HEAD`, refs); update on any change,
  including external terminal commits. Kills staleness without polling.
- Compute **incrementally and lazily**: decorate only visible nodes; update
  only changed paths; roll folder badges up incrementally.
- Lean on git's fast paths: `--porcelain=v2 -z`, the untracked-cache, and
  especially the **fsmonitor daemon** (Watchman / built-in) — the machinery
  that makes `git status` instant at monorepo scale.

This is a **systems problem** (fs watching, git plumbing, cache invalidation,
correctness under submodules/worktrees/sparse-checkout) and is the bulk of the
work. It is largely orthogonal to the icon engine.

## Architecture

```
            ┌────────────────────────────────────────────┐
            │                 UI / view                    │
            │  buffer model · keymaps · interaction model   │
            └───────────────┬───────────────┬──────────────┘
                            │               │
              ┌─────────────▼───┐   ┌───────▼────────────┐
              │  git engine      │   │  icon engine       │
              │ (watched/incr.)  │   │ (svgtree.engine +  │
              │  status·diff·    │   │  raster·icons)     │
              │  fsmonitor       │   │  REUSED AS-IS      │
              └─────────────┬───┘   └───────┬────────────┘
                            │               │
                       ┌────▼───────────────▼────┐
                       │  fs model: scan · watch   │
                       │  (libuv fs_event)         │
                       └───────────────────────────┘
```

- **Icon engine: reuse what exists.** `svgtree.engine` (anchored `vim.ui.img`
  placement), `raster` (SVG→PNG cache), `icons` (resolver) drop in unchanged.
  This is the payoff of extracting them as a library first.
- **Git engine: the new, hard core.** Build standalone and testable in
  isolation (feed it a repo path, assert the status map and that an external
  commit invalidates correctly). Could itself become a reusable library.
- **fs model:** lazy scan + libuv `fs_event` watches on expanded dirs only.

## The interaction-model decision (make this deliberately)

This is the adoption hook and must be chosen before writing UI. Options:

- **A. Classic sidebar tree** (neo-tree/snacks shape). Familiar, lowest risk,
  weakest differentiation. The git+icons legs carry it.
- **B. Editable-buffer (oil-style)** but *tree-shaped* and git-aware. Higher
  risk, strongest "reason to exist," composes with Vim motions.
- **C. Hybrid:** classic tree for navigation, an editable "staging" buffer for
  bulk file ops and git add/restore — turning the git engine into an
  interactive surface, not just decoration.

Recommendation: **C** — it makes the git engine *do something* beyond coloring,
which is the differentiator. Decide before Phase 2.

## Phases

- **Phase 0 — done.** `vim.ui.img` anchoring proven; icon engine extracted;
  snacks/neo-tree adapters validate the engine is host-agnostic.
- **Phase 1 — git engine spike (make-or-break).** Standalone module: scan a
  repo, build the status map via `--porcelain=v2`, watch `.git/`, prove an
  external `git commit` updates the map within one event with no polling.
  Benchmark on a large repo (e.g. a checkout with 100k+ files). *Gate: is it
  instant and correct? If not, the thesis is dead — stop here.*
- **Phase 2 — minimal explorer.** fs model + classic tree + icon engine + the
  git engine's decorations. Ship something usable.
- **Phase 3 — the interaction model** (option C): editable staging surface,
  bulk ops, git add/restore from the tree.
- **Phase 4 — fsmonitor / Watchman integration** for true monorepo scale.
- **Phase 5 — polish:** sessions, diagnostics, search integration, docs.

## Risks & honest checks

- **The git engine is most of the work and the only thing that creates demand.**
  If Phase 1 doesn't beat neo-tree/snacks on a real monorepo, do not proceed —
  fall back to shipping the icon engine as a library and `svgtree` as a demo.
- **`vim.ui.img` is experimental.** Anchoring is a Lua shim today; API may move.
- **Maintenance.** A full explorer is a long-term commitment; the icon-engine
  library is not. Be sure before Phase 2.

## Naming

Working name TBD — not `svgtree` (that's the icon PoC). The explorer's identity
is "git-correct + editable + image icons," so lead with the git/interaction
angle in the name, not the icons.
