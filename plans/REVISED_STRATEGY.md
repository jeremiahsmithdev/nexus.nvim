# Revised Optimization Strategy

Track progress and next steps. Checkboxes reflect code merged in this branch.

## Phase 0 — Baseline & Flags
- [x] Add performance flags: `prefer_cache_on_startup`, `async_git`, `use_batch_git`, `use_fast_render`, `lightweight_initial_render`, `enable_logging_on_startup`.
- [ ] Document profiling workflow with example commands.

## Phase 1 — Lazy Initialization
- [x] Remove duplicate/global early init; defer expensive work until first open.
- [x] Lazy global keymaps: initialize in `nexus.open()` only once.
- [x] Logger opt‑out on startup (`enable_logging_on_startup=false`).

## Phase 2 — Cache‑First Data Path
- [x] Add `git/provider.lua` with cache → batch → naive strategy.
- [x] Prime state from `.nexus/cache` for instant paint when available.
- [x] Async refresh after first paint; re‑render on completion.
- [x] Avoid forced refresh in render path; render from state only.

## Phase 3 — Startup Fast Path
- [x] Lightweight initial render (logo/buttons + placeholders) when no cache.
- [x] Quick `.git` detection (fs scan), fallback to `git rev-parse` only if needed.
- [x] Use precomputed diff stats from provider to avoid per‑file `git diff` on first paint.

## Phase 4 — Rendering/Events Efficiency
- [x] Debounce `CursorMoved` shortcuts/highlights to reduce runtime overhead.
- [ ] Optionally wire `render/fast.lua` behind `use_fast_render` flag.

## Phase 5 — Cache Consolidation
- [x] Delegate `cache.lua` to `unified_cache.lua` while preserving public API + TTLs.
- [x] Ensure invalidation on git actions covers all related keys.

## Phase 6 — Shell/IO Hardening
- [x] Prefer `vim.system` with `{ text = true }` over `io.popen` where available; fallback cleanly.
- [x] Centralize command exec/trim/UTF‑8 handling.

## Phase 7 — Profiling & Benchmarks
- [ ] Gate profiler by flag/env only; add lightweight report helper.
- [ ] Capture before/after timings for startup, first paint, full render.

## Phase 8 — Tests & Rollout
- [ ] Unit: provider fallbacks, cache priming, invalidation.
- [ ] Integration: async path renders placeholders then final data.
- [ ] Roll flags to defaults after benchmarks validate.

Hotfixes
- [x] Ensure Recent Commits render by falling back to `update_git_commits()` when state is empty.
- [x] Normalize decoration formatting to avoid double parentheses.

Notes
- Goal: instant startup via cache‑first and lightweight initial render. First run (no cache) still avoids git I/O before paint and refreshes in background.
- No user‑visible behavior regressions; git actions trigger cache invalidation and refresh.
