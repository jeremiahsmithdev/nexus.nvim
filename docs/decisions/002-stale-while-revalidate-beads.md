# ADR 002 — Stale-While-Revalidate for Beads CLI

## Status

Accepted — 2026-04-16 (implemented in T5, T7, T8, T9).

## Context

The beads section reads from a CLI (`br` / `bd`) that takes 15–60 ms per
invocation for `list`/`ready` queries, depending on issue count and
filesystem cache. Before this change, `state/beads.lua` called the CLI
synchronously on every render trigger:

- Dashboard open
- `r`-refresh
- Any section edit (status cycle, close, priority change)
- Window resize → re-render

Each of those blocked the main thread for the CLI duration. Worse, when
two sections needed beads data in the same render (issues + epics
tables), two independent subprocesses fired.

The render component also deepcopied + resorted the issues list on every
build even when the underlying data hadn't changed, making the "no-op
refresh" path cost more than necessary.

## Decision

Replace every CLI entry point with an async variant and layer
stale-while-revalidate semantics on top:

1. **All CLI calls go through `run_cli_command_async` (`vim.system`)**
   and always `vim.schedule` their callback so consumers can safely call
   Neovim APIs inside.
2. **Sync public functions return the in-memory cache only.** They no
   longer block; callers that need fresh data use the `*_async` variant.
   Deprecated sync write paths (`create_issue`, `update_issue`,
   `close_issue`) now return an error and log a warning.
3. **Cache TTL + freshness check in `get_issues_async`:** returns cache
   instantly when fresh; otherwise fires CLI and invokes the callback
   from `on_exit`.
4. **In-flight coalescing via `_inflight[cmd_args]`:** concurrent callers
   for the same CLI invocation queue their callback behind the original
   job rather than spawning duplicates. Keyed on the canonical argument
   string (`'ready --json'`, `'list --type epic --json'`, etc.).
5. **Combined fetch (`fetch_issues_and_epics_async`):** for non-`ready`
   filters, one `br list --json` subprocess populates both issues and
   epics caches via Lua-side partition. For `ready`, two concurrent
   subprocesses run in parallel and a join counter triggers the callback
   when both return.
6. **Skip-on-identical-payload (T5):** the async handler hashes the
   incoming issue list; when it matches the previous hash, the sort +
   deepcopy in render is skipped entirely.
7. **Optimistic updates (T9):** edit keymaps mutate the cached issue,
   call `render.render_section(buf, 'beads_issues')` to repaint only the
   beads block (shifting downstream `section_ranges` by the delta), and
   fire the CLI in the background. On CLI failure, a forced re-fetch
   corrects the drift.

## Alternatives Considered

1. **Keep synchronous CLI, cache more aggressively.** Rejected: cache
   freshness is hard to reason about when mutations happen both in the
   dashboard and in the user's shell. Even aggressive caching still has
   to validate on render.
2. **Background refresh loop on a timer.** Rejected: wastes work when
   the dashboard isn't visible, and doesn't help edit latency — the
   user's action still has to wait for the next tick.
3. **Pub-sub with `state.notify` to trigger renders.** Rejected and
   removed in T16: observer pattern was unused in practice and added
   indirection. Direct callbacks from the async layer are simpler and
   easier to trace.
4. **Full render on every edit.** Rejected: full renders re-apply folds
   and move the cursor, creating visible flicker. Per-section render
   via `render.render_section` is ~30× faster and doesn't touch
   unrelated sections.

## Consequences

### Positive

- Zero blocking CLI calls on the main thread.
- Concurrent consumers share one subprocess (important when multiple
  sections awaken on refresh).
- Edit actions feel instant (optimistic) while remaining correct
  (CLI runs in background, error path repairs drift).
- Single-subprocess `list --json` partitioning replaces two calls.

### Negative

- Two parallel public APIs (sync + async) — callers must know to use
  `*_async` for fresh data. Mitigated by deprecated-stub warnings and
  inline comments.
- Optimistic updates can briefly show state that the CLI later rejects.
  In practice rejections are rare (invalid ID, locked tracker) and the
  error path full-refreshes to correct.
- `_inflight` entries are not time-bounded — a hung CLI call keeps new
  callers waiting on the original job indefinitely. Acceptable because
  `br` calls complete in milliseconds and a genuine hang is a bug
  worth surfacing.

### Neutral

- The API surface is larger; docs now clearly flag which variant to use
  ([beads-integration.md](../beads-integration.md)).
- `run_cli_command` (synchronous) is gone. If a future feature needs
  blocking CLI (e.g. a migration script), it must reintroduce it.
