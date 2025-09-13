# Nexus.nvim Performance Opportunities

Purpose: make startup, navigation, git, and section rendering blazingly fast. Each item is atomic, with a practical fix and expected gains.

## Startup & Module Load
- Disable default logging I/O: Turn logging off by default and remove tmux lookups per log call (`lua/nexus/logger.lua`). Approach: gate with env/config; memoize pane/window once; no file writes unless debug. Expected: -20–60ms at startup; -0.3–1.5ms per log call.
- Remove eager requires on load: Move `require('nexus.global_keymaps').setup()` out of `plugin/nexus.lua` top-level; call inside `setup()` only. Expected: -3–8ms startup.
- Defer repo check on VimEnter: Replace `vim.fn.system('git rev-parse …')` with `vim.loop.fs_stat('.git')`, and wrap in `vim.defer_fn(100)`. Expected: -15–40ms on startup path.
- Lazy state init: Stop `M.init()` side-effects on `require('nexus.state.git')` and `state.linear` (module tails). Initialize on first use. Expected: -10–25ms.
- Enable Lua bytecode loader: `vim.loader.enable()` once. Expected: -3–10ms on cold start.

## Git Operations
- Batch diff stats: Replace per-file `git diff --numstat` in `ui/folding.lua`/`git/status.lua` with `git/batch.lua` (single command). Expected: 10–50× faster on 50–200 files (e.g., 1200ms → 20–80ms).
- Unify shelling: Replace `io.popen`/`vim.fn.system` with `nexus.git.shell.exec` (uses `vim.system` when available). Expected: eliminate UI stalls; per call -2–15ms.
- Respect TTL; remove force refresh: `render.lua` calls `git_state.force_refresh()` on every render. Use cached status/commits with TTL; add manual refresh key as already provided. Expected: repeated renders 0–5ms vs 50–200ms.
- Async initial load: Integrate `lua/nexus/async_loader.lua` to render placeholders and fetch git data via `jobstart`. Expected: non-blocking render; perceived time <10ms.

## Rendering & Sections
- Swap to fast renderer: Use `lua/nexus/render/fast.lua` for batched highlights and single `set_lines`. Expected: 2–4× faster render (e.g., 40ms → 10–20ms).
- Avoid per-resize git work: In `buffer.lua` resize path, pass cached files to render and skip git refresh; increase debounce to 150ms; no re-render if width unchanged. Expected: resize cost <5ms (down from 30–150ms).
- Highlight in ranges: In `components/highlighting.lua`, avoid char-by-char +/- loops; compute contiguous runs and set a single extmark per run. Expected: -2–6ms on large diffs.

## Navigation & UI Events
- Throttle CursorMoved work: In `components/events.lua`, run updates at 50–100ms throttle and only when the section changes. Expected: ~10× less CPU during movement.
- Remove tmux calls on movement: `ui/shortcuts.update_contextual_shortcuts()` calls `tmux display-message` per move. Use `winwidth(0)`; recalc pane size only on `WinResized`. Expected: 5–20ms → <0.1ms per move.

## TMUX & Logo
- Cache tmux context: Centralize tmux queries in `lua/nexus/tmux.lua`, cache pane/window for session, refresh on `FocusGained/WinEnter`. Replace all direct `vim.fn.system('tmux …')`. Expected: -5–30ms per event that previously hit tmux.
- Make image logo strictly opt-in: Default `logo_selection` to ASCII; skip tmux/image work unless explicitly enabled. Expected: -5–15ms on open.

## Linear Provider
- Strictly lazy network: Ensure no HTTP in startup/render paths; only fetch on explicit action (e.g., `r`). Reduce GraphQL fields and page sizes. Expected: eliminate startup/network stalls; fetch paths 2–3× faster.

## Measurement Targets (post-fix)
- Startup path: <10ms added by plugin; no blocking git calls.
- Open Nexus: <25ms with cache; <120ms cold in large repos.
- Navigation: CursorMoved handlers <0.1ms average.
- Git status (200 files): <80ms batched; <20ms cached.
- Resize: <5ms per event.

Next steps: apply items top-down. Each change is isolated and testable with `scripts/profile-startup.sh`, `scripts/time-open.sh`, and `tests/performance/startup_performance_spec.lua`.

