---
last_updated: 2026-04-16
status: current
tracks:
  - plugin/nexus.lua
  - lua/nexus/init.lua
  - lua/nexus/async_loader.lua
  - lua/nexus/render.lua
  - lua/nexus/git/root.lua
  - lua/nexus/state/folds.lua
---

# Dashboard Lifecycle

## Overview

The Nexus dashboard paints in two phases so the user sees a usable screen
before any git subprocess completes. Phase 1 is synchronous but does no
I/O; Phase 2 runs git in the background and re-renders when data arrives.

This split matters because `VimEnter` runs on the main thread — any
blocking call there measurably delays the first paint, and Nexus can open
automatically at startup.

## How It Works

```
VimEnter
 ├── plugin/nexus.lua
 │    └── vim.system('git rev-parse --is-inside-work-tree')   [async]
 │          └── on success → vim.schedule(require('nexus').open)
 │
 └── nexus.open()
      ├── Phase 1 (sync, no git I/O):
      │    async_loader.render_immediate_ui()
      │      → logo + buttons + "Loading..." placeholders
      │      → minimal keymaps (q, <Esc>)
      │
      └── Phase 2 (async):
           async_loader.load_git_data_async(buf, config, cb)
             └── single subprocess:
                   git rev-parse ... &&
                   git status --porcelain &&
                   git log --oneline --decorate -N --notes &&
                   git diff --numstat
             → vim.schedule(parse_async_git_output)
             → callback (render.render_git_status):
                 full sections, highlighting, folds, full keymaps
```

## Implementation

### Architecture

The lifecycle is split across three layers:

| Layer | File | Role |
|-------|------|------|
| Plugin entry | `plugin/nexus.lua` | Async repo check, user command |
| Orchestration | `lua/nexus/init.lua` | `M.open()` — Phase 1 then Phase 2 |
| Async I/O | `lua/nexus/async_loader.lua` | Immediate UI + background git job |
| Render | `lua/nexus/render.lua` | Full render on data arrival |
| Helpers | `lua/nexus/git/root.lua` | Memoized repo-root resolver |

### Key Functions

- `async_loader.render_immediate_ui(buf, config)` — paints logo + centered
  loading placeholders; applies a `Comment` highlight to `Loading...` lines so
  they read as pending rather than real data.
- `async_loader.load_git_data_async(buf, config, callback)` — builds one
  `sh -c` command that joins `git rev-parse && ... && git log --notes && ...`
  with `---STATUS---` / `---COMMITS---` / `---DIFFSTAT---` sentinels; parses
  the concatenated output in `parse_async_git_output`.
- `async_loader.parse_async_git_output(output)` — splits on sentinels, parses
  diffstats first (so file entries can carry per-file `added`/`deleted`
  inline), and extracts review status from the `--notes` 4-space-indented
  block without a second subprocess.
- `render.render_git_status(buf, config, cached_files, cached_commits)` —
  single renderer shared by cold open and `r`-refresh. Accepts pre-fetched
  data from the async path so it never re-forks git.
- `render.render_section(buf, section_name)` — **per-section incremental
  render**. Used by optimistic beads updates (T9) to replace only the
  `beads_issues` lines and shift downstream `section_ranges` by the delta,
  avoiding full-buffer rewrites.

### Git Root Memoization

`git/root.lua` caches `git rev-parse --show-toplevel` per-cwd. Required
because many call-sites need the root — logo, claude scanner, fold state
keying, beads detector — and without memoisation each would re-fork git.
The cache is keyed on `vim.fn.getcwd()` so `:cd`-ing into another repo
auto-invalidates.

A `nil`-marker is cached as `false` to avoid retrying on every call when
the cwd is not a git repo.

### Fold-apply Gating

`state/folds.lua` maintains `_dirty` + `_last_ranges_hash`. `render.lua`
calls `folding.compute_ranges_hash(section_ranges)` and only re-runs
`initialize_folds_to_open` + `apply_fold_states` when either:

1. fold state changed (`set_section_state → mark_dirty`), **or**
2. section layout shifted (different ranges hash).

This removes the cursor-jump flicker on idempotent `r`-refreshes where
nothing actually changed.

## Configuration

- `config.open_on_startup` (default `true`) — VimEnter auto-open.
- `config.recent_commits_count` (default `3`) — number of commits the
  batched `git log` pulls.
- `config.show_commit_review` — controls whether note parsing populates
  `commit.review_status`.

## Usage Examples

```lua
-- Manual open from user command
:Nexus

-- Programmatic (matches what plugin/nexus.lua does)
require('nexus').open(true)  -- true = manual open

-- Incremental re-render of one section
require('nexus.render').render_section(buf, 'beads_issues')
```

## Related Docs

- [Git Pipeline](./git-pipeline.md) — the batched subprocess and inline
  notes parsing.
- [Beads Integration](./beads-integration.md) — uses `render_section` for
  optimistic updates.
- [Folding](./folding.md) — dirty tracking and persistence.
- [ADR 001](./decisions/001-async-startup-two-phase-render.md) — why two
  phases.

## Edge Cases & Limitations

- The `VimEnter` autocmd only opens automatically when `argc() == 0`; if
  the user passes any file argument, Nexus stays inert until `:Nexus`.
- `load_git_data_async` cancels any in-flight job for the same buffer
  before starting a new one (see `loading_jobs` table), so rapid
  re-renders do not stack.
- `render_section` falls back to a full render if the requested section
  is not yet in `section_ranges` (i.e. the first paint hasn't completed).
