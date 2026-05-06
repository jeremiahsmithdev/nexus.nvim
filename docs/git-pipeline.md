---
last_updated: 2026-04-16
status: current
tracks:
  - lua/nexus/async_loader.lua
  - lua/nexus/git/commits.lua
  - lua/nexus/git/batch.lua
  - lua/nexus/git/status.lua
  - lua/nexus/state/git.lua
  - lua/nexus/render/components/highlighting.lua
---

# Git Pipeline

## Overview

All git data needed for the initial dashboard paint — repo check, status,
recent commits, diff stats, and per-commit review notes — comes from a
**single subprocess**. The output is chunked with sentinel lines and
parsed by `async_loader.parse_async_git_output`, which also exposes diff
stats so downstream consumers (folding, highlighting) never re-fork git.

The previous layout fired 4+ separate git processes plus one
`git notes show` per visible commit. This pipeline collapses all of that
into one.

## How It Works

```
sh -c '
  git rev-parse --is-inside-work-tree && echo "---STATUS---" &&
  git status --porcelain=v1             && echo "---COMMITS---" &&
  git log --oneline --decorate -N --notes && echo "---DIFFSTAT---" &&
  git diff --numstat
'
```

The parser walks output in order, switches sections on sentinels, and:

1. **Parses diffstats first** so each status entry can embed its `added`
   / `deleted` counts directly — `render/components/folding.process_git_files`
   reads `item.added` without a fallback subprocess in the common path.
2. **Parses commits with inline notes**: lines indented 4 spaces are notes
   attached to the preceding commit. The commit's `review_status` is
   derived by lowercasing the note block and matching on
   `needs attention` or `reviewed`. This replaces the per-commit
   `git notes show` calls (T11).

The repo-existence signal (`rev-parse` outputting `true`) is captured
from the pre-sentinel chunk and flows through as `is_git_repo`.

## Implementation

### Architecture

| File | Role |
|------|------|
| `lua/nexus/async_loader.lua` | Builds the batched command, parses output |
| `lua/nexus/git/commits.lua` | Sync variant (same parser, uses `io.popen`) |
| `lua/nexus/git/batch.lua` | Legacy batched command via `io.popen` + cache |
| `lua/nexus/git/status.lua` | Status icon & color group mapping, sync diffstat fallback |
| `lua/nexus/state/git.lua` | Exposes parsed data + `diff_stats` map |
| `lua/nexus/render/components/folding.lua` | Consumer; reads embedded stats |

`async_loader` is the canonical path on cold open. `git/commits.lua` and
`git/batch.lua` exist for manual refresh paths and legacy callers.

### Key Functions

- `async_loader.load_git_data_async(buf, config, callback)` — spawns
  the batched `sh -c` job, buffers stdout, schedules the parser.
- `async_loader.parse_async_git_output(output)` — returns
  `{files, commits, is_git_repo, diff_stats}`. `diff_stats` is a map of
  `file → {added, deleted}` that `state.git` caches for folding to read.
- `async_loader.parse_diffstats_async(lines)` — tab-delimited
  `added\tdeleted\tfile`; `-` is emitted by git for binaries, so
  `tonumber()` may return nil and defaults to 0.
- `git.commits.parse_review_status_from_notes(text)` — shared between
  sync and async paths so review-status semantics stay identical.
- `render/components/folding.process_git_files(files, limit)` — uses
  the pre-fetched `state.diff_stats` map; only falls back to
  `git.status.get_diff_stats` for files that arrived outside the async
  load (e.g. explicit sync refresh).

### Diff Bar Highlighting (T10)

`render/components/highlighting.apply_git_status_highlighting` used to
emit one `nvim_buf_add_highlight` per `+` / `-` character — O(line_length)
API calls per status line. It now scans for contiguous runs:

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

This drops the per-line call count from ~50+ to 2–4. The same scan is
repeated for `-` with `DiagnosticError`. Extmark's `end_col` parameter is
what makes the compression possible — `nvim_buf_add_highlight` required
one call per byte range.

### Status-letter Colouring

`MM` (staged + modified) gets special handling: first `M` is
`DiagnosticOk` (green, staged), second `M` is `DiagnosticError` (red,
unstaged). All other statuses route through `git.status.get_status_color`.

## Configuration

- `config.recent_commits_count` — how many commits the batched `git log`
  pulls (default `3`). Controls fold width as well.
- `config.show_commit_review` — when false, notes are ignored and all
  commits show `unreviewed`.
- `config.git_status_count` — limit on visible files before the overflow
  fold kicks in (`render/components/folding`).

## Usage Examples

```lua
-- Cold-open data path (fires once per dashboard open)
require('nexus.async_loader').load_git_data_async(buf, config, function(data)
  -- data = { files, commits, is_git_repo, diff_stats }
  require('nexus.render').render_git_status(buf, config, data.files, data.commits)
end)

-- Manual 'r' refresh — reuses the same parser via git.commits
local commits = require('nexus.git.commits').get_git_log(config)
```

## Related Docs

- [Dashboard Lifecycle](./dashboard-lifecycle.md)
- [Folding](./folding.md) — consumer of `diff_stats`.
- [ADR 003](./decisions/003-extmark-over-nvim-buf-add-highlight.md)

## Edge Cases & Limitations

- The batched command uses `&&`, so a failure in any step short-circuits
  the rest. In practice only `rev-parse` fails outside a repo; the fold
  handler short-circuits to `is_git_repo = false` and the dashboard
  renders the non-git layout.
- Empty `git diff --numstat` output is normal (clean tree); the parser
  handles it and leaves every file with `added = 0, deleted = 0`.
- Binary files produce `-\t-\tfile`; `tonumber("-")` → nil → stored as 0.
- Note parsing lowercases the whole note block before pattern-matching,
  so `Needs Attention`, `NEEDS ATTENTION`, etc. all resolve correctly.
