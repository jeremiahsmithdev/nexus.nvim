# ADR 003 — Prefer extmarks over `nvim_buf_add_highlight`

## Status

Accepted — 2026-04-16 (migration committed in `4ac204d`; diff-bar
compression in T10).

## Context

`nvim_buf_add_highlight` is deprecated as of Neovim 0.11 in favour of
`nvim_buf_set_extmark({ end_col = ..., hl_group = ... })`. The two APIs
have different performance characteristics: extmarks accept a range in a
single call, while `add_highlight` requires one call per
single-highlight range.

Nexus had two hotspots that made this matter:

1. **Diff bars.** The git-status section renders `+++---` style bars
   whose length scales with the diff size. Highlighting the green `+`
   run and the red `-` run used a per-character loop:

   ```lua
   for i = 1, #line do
     if line:sub(i, i) == '+' then
       vim.api.nvim_buf_add_highlight(buf, ns, 'DiagnosticOk', row, i-1, i)
     elseif line:sub(i, i) == '-' then ...
   end
   ```

   A 50-character bar meant 50 API calls per file.

2. **General-purpose highlighting** for commits, shortcuts, beads,
   todos, linear, etc. Each section independently called the deprecated
   API, making the codebase a deprecation warning farm under Neovim 0.11+.

## Decision

1. **Migrate every call site** from `nvim_buf_add_highlight` to
   `nvim_buf_set_extmark` with an explicit `end_col` and `hl_group`.
2. **Collapse per-character loops into run-scanning patterns** for
   diff bars:

   ```lua
   local pos = 1
   while pos <= #line_content do
     local s, e = line_content:find('%++', pos)
     if not s then break end
     vim.api.nvim_buf_set_extmark(buf, git_ns, line_num - 1, s - 1, {
       end_col = e,
       hl_group = 'DiagnosticOk',
     })
     pos = e + 1
   end
   ```

   Same structure for `%-+` with `DiagnosticError`. Extmarks handle a
   full contiguous run in one call, so a line with 2 `+` runs and 1 `-`
   run becomes 3 API calls regardless of the run lengths.
3. **Keep per-namespace separation.** Logo, beads, git status, linear,
   todo etc. each own a named namespace so clears/re-applies are
   section-local.

## Alternatives Considered

1. **Leave `nvim_buf_add_highlight` in place.** Rejected: deprecated API
   generates warnings and will eventually be removed. Migration cost is
   low.
2. **Use `matchadd` for syntax-style highlighting.** Rejected: match
   groups are window-local and don't play well with buffer-bound marks
   that survive cursor moves. Extmarks are the right model for
   "annotate this buffer range".
3. **Batch the highlight calls into `nvim_buf_set_extmark` with a list
   of marks.** Not supported — `set_extmark` is a single-mark API. The
   run-scanning approach is the effective batching.

## Consequences

### Positive

- Zero deprecation warnings under Neovim 0.11+.
- Diff-bar highlighting drops from O(line_length) API calls to O(runs
  per line) — typically 2–4 per file instead of 50+.
- Namespace-scoped clears (`nvim_buf_clear_namespace`) mean incremental
  renders only invalidate the specific section's highlights.

### Negative

- Extmark semantics (`end_col` is exclusive) are subtly different from
  `add_highlight` (end col exclusive too, but more often treated as
  inclusive). All call sites were audited but a future regression is
  possible if someone forgets.
- Extmarks survive buffer changes unless cleared, so each render must
  clear its namespace before re-applying. Forgetting this leaves stale
  highlights after a section shrinks.

### Neutral

- Extmarks support additional features (`virt_text`, `sign_text`) that
  open design space for richer annotations later. `apply_beads_highlighting`
  already uses them for issue-status glyphs.
- Diff-bar run scanning uses Lua patterns; for truly huge bars, a
  character-class scan is O(n) and still fast.
