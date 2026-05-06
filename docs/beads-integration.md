---
last_updated: 2026-04-16
status: current
tracks:
  - lua/nexus/state/beads.lua
  - lua/nexus/render/components/beads.lua
  - lua/nexus/keymaps/beads.lua
---

# Beads Integration

## Overview

Beads is a local, git-backed issue tracker (`br` or `bd` CLI). Nexus
surfaces ready issues, in-progress work, and epic status directly in the
dashboard, with inline editing keymaps that mutate issues without leaving
the buffer.

The integration is entirely async: every CLI call goes through
`vim.system`, results are cached with stale-while-revalidate, and updates
re-render only the beads section to avoid the flicker of a full redraw.

## How It Works

### Sync vs Async Public API

`state/beads.lua` exposes two parallel function sets:

| Sync | Async | Returns |
|------|-------|---------|
| `get_issues(filter)` | `get_issues_async(filter, cb)` | Sync returns the in-memory cache only; async triggers CLI when TTL expired. |
| `get_sorted_epics()` | `get_sorted_epics_async(cb)` | Same. |
| `create_issue/update_issue/close_issue` | `*_async` | Sync variants are deprecated stubs that log a warning. |

Render components always call the sync accessors for cached data
(`get_cached_issues`, `get_cached_epics`) and kick off an async refresh
separately when the TTL is stale. The sync path never blocks.

### Stale-While-Revalidate

```
caller → get_issues_async(filter, cb)
         ├── (cache fresh?) → cb(cached, nil)                      [instant]
         ├── (in-flight?)   → append cb to _inflight[cmd_args]     [coalesce]
         └── (start job)    → vim.system({br, args}, ...)
                                 └── on_exit → for cb in pending: cb(...)
```

`_inflight[cmd_args]` is keyed on the canonical argument string (e.g.
`'ready --json'`). Concurrent callers for the same filter share one
subprocess; divergent filters fire independently.

### Optimistic Updates

Keymaps that mutate a single issue (`s`tatus change, `c`lose, `p`riority,
note append) follow this pattern:

1. Update the in-memory issue in `_cached_issues`.
2. Call `render.render_section(buf, 'beads_issues')` — replaces only that
   section's lines and shifts `section_ranges` for downstream sections.
3. Fire the async CLI call in the background; on failure, re-fetch and
   re-render to correct drift.

This avoids the 30–200 ms wait for `br update` before the UI reflects
the change. If the backend rejects the edit, the full refresh on error
brings the cache back in sync.

## Implementation

### Key Components

| File | Purpose |
|------|---------|
| `lua/nexus/state/beads.lua` | Cache, async CLI wrapper, in-flight coalescing |
| `lua/nexus/render/components/beads.lua` | Section builder, highlighting, line→id mapping |
| `lua/nexus/keymaps/beads.lua` | Edit keymaps, bulk popup editor (`E`), epic navigation |

### Key Functions

**state/beads.lua:**
- `run_cli_command_async(args, callback)` — shell-wraps `br` / `bd`, parses
  JSON, always schedules the callback on the main thread.
- `normalize_issues(result)` — accepts array, `{issues=[...]}`, or single
  object responses so callers don't branch on CLI shape.
- `get_issues_async(filter, cb)` — the main entry; does TTL check,
  in-flight coalescing, and error-fallback to stale cache.
- `fetch_issues_and_epics_async(cb)` *(T8)* — non-`ready` filters use a
  single `br list --json` call and partition results in Lua into
  `_cached_issues` and `_cached_epics`, replacing two subprocesses with
  one. The `ready` filter still fires `br ready --json` plus
  `br list --type epic --json` concurrently (join counter ensures `cb`
  fires once) because `ready` has unblocked-leaf semantics that can't be
  replicated with Lua-side filtering.
- `is_beads_available()` — cheap disk check for `<git_root>/.beads/`;
  used before any async call to fast-fail without forking `sh`.

**render/components/beads.lua:**
- `build_beads_section(config)` — pulls from cached issues/epics, sorts by
  (status, priority, id), produces the lines that render.lua inserts.
- `update_line_mapping(start_line)` — rebuilds `_line_to_issue_map` so
  `<Enter>` / `s` / `c` know which issue is under the cursor.
- `apply_beads_highlighting(buf, start_line)` — priority/status color
  groups applied via extmarks in the `nexus_beads` namespace.

### Skipped Work on Clean Refresh (T5)

`state/beads.lua` tracks a content hash of the last CLI payload. When a
refresh returns the same hash, the sort + deepcopy step is skipped entirely
(`_cached_issues` is reused) because no observable state changed. This is
the difference between a 0-cost `r`-refresh and a full pipeline re-run.

## Configuration

```lua
{
  beads = {
    cli = "br",          -- "br" (beads_rust) or "bd"
    enabled = false,     -- surface beads section in dashboard
    filter = "ready",    -- "ready", "all", "in_progress", "epics"
    cache = {
      issues_ttl = 60,   -- seconds; local tracker → frequent updates
    },
  },
}
```

Config is persisted to `.nexus/config.lua` per-repo (see `config.lua`
`load_persisted_config`), so a project can set `cli = "bd"` or enable
beads without touching global Neovim config.

## Usage Examples

```lua
-- Callers: always use async for fresh data
require('nexus.state.beads').get_issues_async('ready', function(issues, err)
  if err then return end
  -- issues is the normalised list
end)

-- Rendering reads cache only (never blocks)
local issues = require('nexus.state.beads').get_cached_issues()
```

Keymaps (in beads section, cursor on an issue line):

- `<Enter>` — open issue detail popup
- `s` — cycle status (todo → in_progress → done)
- `c` — close issue
- `p` — change priority
- `E` (in popup) — bulk-edit every visible todo
- `[[` / `]]` — jump between epics

## Related Docs

- [Dashboard Lifecycle](./dashboard-lifecycle.md) — `render_section` is
  the mechanism optimistic updates rely on.
- [ADR 002](./decisions/002-stale-while-revalidate-beads.md) — rationale
  for sync/async API split.

## Edge Cases & Limitations

- `vim.system` requires Neovim 0.10+. The async layer does not fall back
  to `jobstart` if unavailable — Nexus assumes modern Neovim.
- The in-flight coalescing table is process-lived; if a CLI call hangs
  for longer than the TTL, new callers still wait on the original job.
- Deprecated sync stubs (`create_issue`, `update_issue`, `close_issue`)
  return `nil, 'Use *_async()'` and log a warning. They are kept so old
  call-sites fail loudly rather than silently.
- The line→id map is rebuilt on every `build_beads_section` call. Cursor
  positions captured before a render are only valid if the map has since
  been updated.
