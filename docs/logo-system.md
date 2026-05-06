---
last_updated: 2026-04-16
status: current
tracks:
  - lua/nexus/ui/logo.lua
  - lua/nexus/ui/logos/neovim.lua
  - lua/nexus/ui/logos/nexus.lua
  - lua/nexus/ui/logos/alphabet.lua
---

# Logo System

## Overview

The dashboard banner supports four distinct logo strategies selectable
via `config.logo_selection`:

- `"nexus"` — the Nexus ASCII banner (default)
- `"neovim"` — the alpha.nvim-style Neovim logo
- `"project"` — the current project name rendered in a block-letter
  alphabet
- `"image"` — a PNG rendered via `image.nvim`, with tmux-pane isolation

Art data is split out of the dispatcher (`ui/logo.lua`) into
`ui/logos/*.lua` so each variant is lazy-loaded only on selection; the
dispatcher file itself stays small and the ~200-line alphabet doesn't
pay a load cost for users who never pick `"project"`.

## How It Works

### Dispatcher

`logo.get_neovim_logo(config)` branches on `logo_selection` and delegates
to the matching builder:

| Selection | Builder | Art source |
|-----------|---------|------------|
| `nexus` | `get_nexus_ascii_logo()` | `require('nexus.ui.logos.nexus')` |
| `neovim` | `get_ascii_logo()` | `require('nexus.ui.logos.neovim')` |
| `project` | `get_project_logo()` | `require('nexus.ui.logos.alphabet')` |
| `image` | `get_image_logo(config)` | PNG via `image.nvim` |

All builders return a flat list of strings (lines). Centering is done
later by `ui/center.lua`.

### Project Logo

`get_project_logo` reads the project name from `git.root` and the
current branch, converts to uppercase, filters to characters in the
alphabet map, and concatenates each character's 6-line pattern
horizontally with a space separator. Falls back to the Nexus banner if
no characters match.

The block-letter alphabet in `logos/alphabet.lua` covers A–Z and a few
symbols; lowercase is normalised via `string.upper`.

### Image Logo

`get_image_logo` returns placeholder empty lines (to reserve buffer
space); the actual PNG is rendered by `render_image_logo`, which runs
**after** the buffer content is set so the image overlays the right
region.

Tmux-pane isolation prevents the image from leaking across panes when
the user switches windows:

- `_get_tmux_pane_info()` captures `pane_id,left,top,width,height,active`
  in a single `tmux display-message` call.
- `should_show_image_in_current_pane()` refuses to render if the current
  pane differs from the stored `_current_tmux_pane`.
- `refresh_image` + `cleanup_image` validate the pane before touching
  `image:render()` / `image:clear()`.

Without this guarding, `image.nvim` paints at absolute terminal
coordinates and would overlay unrelated content in adjacent panes.

## Implementation

### Key Components

| File | Purpose |
|------|---------|
| `lua/nexus/ui/logo.lua` | Dispatcher, project-name resolution, image render + tmux isolation |
| `lua/nexus/ui/logos/nexus.lua` | Nexus ASCII art (static table) |
| `lua/nexus/ui/logos/neovim.lua` | Alpha.nvim-style Neovim art |
| `lua/nexus/ui/logos/alphabet.lua` | A–Z block-letter patterns (6 lines each) |

### Key Functions

- `logo.get_neovim_logo(config)` — top-level dispatcher.
- `logo._get_project_name()` — returns `"<name> on  <branch>"` using
  the git root + `git.commits.get_current_branch`. Falls back to cwd
  basename when outside a repo.
- `logo.render_image_logo(buf, config, start_line, x_offset)` — creates
  and renders the `image.nvim` handle, stores it in `_current_image`
  for later cleanup.
- `logo.cleanup_image()` — clears the image and stops the isolation
  timer if one is running.

### Why the Split (T17)

Before T17, all ASCII art lived as literal tables inside `ui/logo.lua`,
which meant:

1. The dispatcher file was hundreds of lines of static data, hard to
   diff and review.
2. Every `require('nexus.ui.logo')` paid the full cost of parsing all
   three alphabets + two banners, even when only one was selected.

After the split, the dispatcher is ~380 lines of logic and each variant
pays its load cost only when `logo_selection` points at it.

## Configuration

```lua
{
  logo_selection = "nexus",    -- nexus | neovim | project | image
  logo_color     = "String",   -- highlight group
  image_logo_path   = nil,     -- defaults to assets/neovim.png
  image_logo_width  = 30,      -- character units
  image_logo_height = 6,       -- line units
}
```

Project logo has no extra config — it derives everything from git state.

## Usage Examples

```lua
-- Switch at runtime
require('nexus.config').set({ logo_selection = 'project' })
require('nexus').open(true)  -- re-render with new logo
```

## Related Docs

- [Dashboard Lifecycle](./dashboard-lifecycle.md) — logo is painted in
  Phase 1 before any git data is ready.

## Edge Cases & Limitations

- `image.nvim` is an optional dependency; if `pcall(require, 'image')`
  fails, the dispatcher silently falls back to the Neovim ASCII logo.
- In tmux, `_current_tmux_pane` is captured the first time an image
  renders. If the plugin loads outside tmux and tmux starts mid-session,
  subsequent renders proceed without pane checks.
- The project logo only supports characters present in the alphabet
  table; unknown characters are silently dropped. Branches like
  `feat/very-long-name` rendered as block letters get very wide.
- `refresh_image` avoids re-rendering when the current pane differs from
  the stored pane, so image-mode dashboards will not auto-redraw after
  switching panes and returning.
