---
last_updated: 2026-04-16
status: current
tracks:
  - lua/nexus/ui/folding.lua
  - lua/nexus/state/folds.lua
  - lua/nexus/render/components/folding.lua
---

# Folding

## Overview

Every major dashboard section (commits, git status, todos, beads, etc.)
can collapse to a single header line with a line-count indicator. Fold
state persists per-repo to `~/.cache/nexus/fold_state.json` so the user's
preferred layout survives Neovim restarts.

A separate "overflow fold" compresses the tail of long git-status lists
into a single `+ N Untracked files, + M Changes not staged for commit`
summary line.

## How It Works

Folding has three loosely-coupled pieces:

1. **Section folds** — manual folds created during render via
   `setup_section_folds`. State is persisted per-repo in
   `state/folds.lua` keyed by `git_root`.
2. **Overflow fold** — git-status-specific compression triggered by
   `config.git_status_count`. Collapses hidden files into one overflow
   summary line. Lives in `render/components/folding.lua`.
3. **Apply gating** — render avoids re-applying saved fold states on
   idempotent refreshes by hashing `section_ranges`.

### Foldable Sections

`ui/folding.foldable_sections`:

```lua
{
  'dashboard_buttons',
  'todos',
  'recent_commits',
  'git_status',
  'linear_issues',
  'huly_issues',
  'beads_issues',
  'claude_conversations',
}
```

`project_name` and `keyboard_shortcuts` are intentionally excluded — they
are single-line headers, not content containers.

### Persistence

`state/folds.lua` keeps `fold_state_cache[repo_path][section_name] = "open" | "closed"`.
Writes go through `set_section_state`. JSON is serialised via `vim.fn.json_encode`
to `~/.cache/nexus/fold_state.json`.

Default state is **open** — a missing entry means "open", not "unknown".

## Implementation

### Key Components

| File | Purpose |
|------|---------|
| `lua/nexus/ui/folding.lua` | Fold creation, apply, arrow headers, section detection |
| `lua/nexus/state/folds.lua` | Disk persistence of fold state |
| `lua/nexus/render/components/folding.lua` | Git-status overflow fold |

### Key Functions

- `folding.setup_section_folds(buf, section_ranges)` — creates one manual
  fold per entry in `foldable_sections`. Clamps fold end to the line
  before the next section header to prevent overlap.
- `folding.apply_fold_states(buf, section_ranges)` — establishes an
  all-open baseline with `zR`, then walks `foldable_sections`, reads each
  section's saved state, and issues `zc` on the sections that should be
  closed, restoring the saved view at the end.
- `folding.toggle_fold_at_cursor(buf)` — resolves the section under the
  cursor via `section_ranges` in O(1), uses explicit `zo`/`zc` (never
  `za` — see gotcha below), persists the new state.
- `folding.update_section_arrows(buf, section_ranges)` — rewrites the
  `▼`/`▶` glyph in each section header to match the current fold state.
  Uses `string.find(..., 1, true)` for UTF-8-safe plain matching.
- `folding.get_fold_text(fold_start_line, base_text)` — overflow fold's
  custom text; reads the previous line's leading whitespace and reuses it
  as padding so the summary line lines up with its surrounding section.

### Rebuild-Every-Render

Folds are rebuilt unconditionally on every render. `nvim_buf_set_lines`
destroys all manual folds when it rewrites the buffer, so the render path
wipes (`zE`), recreates (`setup_section_folds`), and re-applies saved state
(`apply_fold_states`) as one atomic block inside `nvim_win_call` on the real
Nexus window:

```
render()
  nvim_buf_set_lines(buf, 0, -1, lines)   // destroys existing folds
  nvim_win_call(nexus_win):
      zE                                   // wipe any survivors
      setup_section_folds(buf, ranges)     // recreate (closed by default)
      apply_fold_states(buf, ranges)       // zR baseline, then close saved-closed
      update_section_arrows(buf, ranges)
```

Running all fold ops in a single `nvim_win_call` matters: folds are
window-local, so a refresh fired while the user is focused elsewhere would
otherwise apply to nvim's hidden autocmd window and evaporate, leaving stale
folds over fresh content.

### Window-local Options (Gotcha)

`foldmethod`, `foldenable`, `foldlevel`, `foldtext` are **window-local**
options, not buffer-local. Code uses `vim.wo[0]` **inside**
`nvim_buf_call` to set them on the window displaying the buffer:

```lua
vim.api.nvim_buf_call(buf, function()
  vim.wo[0].foldmethod = 'manual'
  vim.wo[0].foldenable = true
  vim.wo[0].foldlevel = 99
end)
```

The deprecated `nvim_buf_set_option` API does not reliably set
window-local options — it was the source of a class of "folds work
sometimes" bugs before the migration.

`foldopen` / `foldclose` are **global** options; Nexus avoids setting
them to not affect other buffers.

### `za` vs `zo`/`zc`

Use explicit `zo` (open) / `zc` (close) for toggling single folds.
`za` mutates `foldlevel` as a side-effect, which closes every fold at
the same level — catastrophic UX for a dashboard where each section is
independently foldable.

### Git-status Overflow Fold

`render/components/folding.setup_git_status_folding`:

1. Only runs when `config.git_status_count` is set and the file count
   exceeds it.
2. Finds the `Git Status:` header line.
3. Categorises hidden files (`??` → untracked; other → unstaged) and
   builds a single summary line.
4. Creates a manual fold via `:%d,%dfold` and installs a custom
   `foldtext` that mimics the leading whitespace of the line above.

## Configuration

- `config.git_status_count` (nil by default) — threshold above which the
  overflow fold engages. `nil` disables the fold entirely.
- Fold state per-section is user-driven (keymap toggles), not
  configuration — there's no "default closed" setting.

## Usage Examples

Toggle the fold under the cursor:

```lua
require('nexus.ui.folding').toggle_fold_at_cursor(buf)
```

Clear saved fold state for the current repo (reset to all-open):

```lua
require('nexus.state.folds').clear_repo_state()
```

## Related Docs

- [Dashboard Lifecycle](./dashboard-lifecycle.md) — fold apply is part of
  every render pass.
- `../COLLAPSIBLE_SECTIONS.md` — original design note for section
  folding (historical).

## Edge Cases & Limitations

- Folds must end **before** the next section's header line; ranges
  are clamped via `all_section_starts` sort to prevent overlap even when
  section boundaries shift.
- Trailing empty lines are trimmed from fold ranges so the fold label
  doesn't leave a blank strip beneath it.
- `foldclosed()` returning `-1` can mean "not folded" **or** "never
  opened"; the `initialize_folds_to_open` pass resolves this ambiguity.
- Applying fold states moves the cursor by design; we save + restore it,
  but if an autocmd fires on `CursorMoved` it may see the intermediate
  position.
