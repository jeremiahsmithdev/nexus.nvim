# ADR 001 — Two-Phase Async Startup Render

## Status

Accepted — 2026-04-16 (implemented in T1, T3, T6, T7, T11).

## Context

Nexus opens automatically on `VimEnter` when the user starts Neovim in a
git repository with no file arguments. Before this change, the open path
performed several synchronous git subprocesses during that event:

1. `git rev-parse --is-inside-work-tree` (repo check)
2. `git status --porcelain`
3. `git log --oneline --decorate -N`
4. `git diff --numstat`
5. `git notes show <sha>` — one call **per commit** to determine review
   status.

On a laptop with a warm disk cache, steps 1–4 added ~20–40 ms. Step 5
added 20–30 ms per commit, so the default three-commit view cost another
60–90 ms. All of it ran before the first paint — a visibly delayed
startup.

Rendering the dashboard after the main-thread had been pinned for
100–150 ms also meant any `BufReadPost`-triggered autocmds from other
plugins queued behind us, compounding user-visible lag.

## Decision

Split the dashboard open into two phases:

1. **Phase 1 (synchronous, no git I/O):** `render_immediate_ui` paints
   the logo, dashboard buttons, and `Loading…` placeholders with minimal
   keymaps (`q`, `<Esc>`). This runs on the main thread but forks no
   subprocesses.
2. **Phase 2 (async):** `load_git_data_async` runs a single `sh -c`
   command that chains `rev-parse && status && log --notes && diff
   --numstat` with sentinel lines. On completion, `render_git_status`
   replaces the placeholders and installs full keymaps.

The `VimEnter` repo check itself is moved to `vim.system` so
`plugin/nexus.lua` never blocks either.

Commits (T11) inline their review status from `git log --notes` 4-space
indented output instead of a per-commit `git notes show`, eliminating
the N+1 subprocess pattern.

## Alternatives Considered

1. **Cache all git data on disk and show that first, refresh in
   background.** Rejected: invalidation complexity and the risk of users
   staring at stale state were both worse than a sub-second loading
   placeholder. Claude conversation scanning *does* use disk cache (T6),
   but that's a slow fs walk, not git state.
2. **Defer the dashboard render until first idle
   (`vim.defer_fn(..., 0)`)**. Rejected: still synchronous once fired,
   and pushing the paint to the next tick doesn't help if the git calls
   then block. Async + two-phase gives a real first paint immediately.
3. **Use `jobstart` instead of `vim.system`.** Rejected: `vim.system`
   (0.10+) is simpler, has a saner API, and text-mode buffering matches
   our parsing needs. We already target Neovim ≥ 0.10 elsewhere.

## Consequences

### Positive

- First paint renders immediately after `VimEnter`; no main-thread git
  blocking at any point during startup.
- Per-commit subprocess calls for review notes are eliminated
  (previously ~60 ms / 3 commits on warm cache).
- The async-parse path is shared by `r`-refresh, so no duplicate parser.
- `render.render_git_status` accepts `cached_files` / `cached_commits`,
  keeping one renderer for cold-open and refresh.

### Negative

- Two-phase paint introduces a brief "Loading…" placeholder which is
  itself visible at startup; centering and `Comment` highlight make it
  clearly pending.
- Neovim ≥ 0.10 is hard-required (`vim.system` has no polyfill).
- Race handling: rapid re-renders can overlap; `loading_jobs` cancels
  stale jobs but adds state to reason about.

### Neutral

- The legacy `git/batch.lua` (io.popen) path is retained for sync
  callers that haven't migrated; should be re-evaluated once all
  consumers go through `state.git`.
