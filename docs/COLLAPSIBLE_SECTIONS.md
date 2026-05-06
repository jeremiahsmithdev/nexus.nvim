# Collapsible Sections

Nexus dashboard sections can be collapsed and expanded using fold indicators, similar to a table of contents or file tree. This feature allows you to focus on relevant sections while hiding others, with your preferences persisted across sessions.

## Overview

Each section in the Nexus dashboard displays a fold indicator in its header:
- **▼** - Section is expanded (contents visible)
- **▶** - Section is collapsed (contents hidden)

The section header remains visible when collapsed, with only the content hidden underneath. When collapsed, the fold text shows the number of hidden lines:
```
▼ Git Status:           # Expanded - header and content visible

  M  src/main.lua
  A  src/config.lua

▶ Git Status (15 lines) # Collapsed - only header visible, content hidden
```

## Foldable Sections

The following sections support collapsing/expanding:
- **Dashboard Buttons** - Quick action buttons
- **Todo** - Todo list items
- **Recent Commits** - Git commit history
- **Git Status** - Working directory changes
- **Linear Issues** - Linear issue tracker integration
- **Huly Issues** - Huly project management integration

**Note**: The project name and keyboard shortcuts sections are not collapsible as they provide essential navigation context.

## Usage

### Toggling Sections

Place your cursor **anywhere within a section** and press any of the following keys:

| Keybinding | Description |
|------------|-------------|
| `za` | Standard Vim fold toggle |
| `<Tab>` | Quick fold toggle |
| `<Space>` | Quick fold toggle |

All three keybindings perform the same action - use whichever feels most natural.

### Examples

**Collapse Recent Commits:**
1. Move cursor to any line in the "Recent Commits" section
2. Press `za`, `Tab`, or `Space`
3. The section collapses, showing: `▶ Recent Commits (5 lines)`

**Expand Git Status:**
1. Move cursor to the collapsed "Git Status" header
2. Press `za`, `Tab`, or `Space`
3. The section expands, showing all file changes

**Focus on Specific Work:**
```
# Common workflow: Hide distractions
1. Collapse "Dashboard Buttons" (Tab)
2. Collapse "Recent Commits" (Tab)
3. Keep "Git Status" and "Todo" expanded
4. Work with focused view
```

## Persistence

### Automatic State Saving

Fold states are automatically saved and restored:
- **Saved per repository** - Each git repository remembers its own fold preferences
- **Saved on toggle** - State is written immediately when you collapse/expand a section
- **Restored on open** - Your last fold configuration loads automatically when opening Nexus

### Storage Location

Fold states are stored in:
```
~/.cache/nexus/fold_state.json
```

The file uses a repository-keyed structure:
```json
{
  "/Users/name/projects/myapp": {
    "git_status": "closed",
    "recent_commits": "open",
    "todos": "open",
    "linear_issues": "closed"
  }
}
```

### Default Behavior

- **First open**: All sections start expanded
- **After toggling**: Your preferences are remembered
- **New repository**: Starts with all sections expanded
- **Missing state**: Any section without saved state defaults to expanded

### Clearing State

To reset fold preferences for the current repository:
```lua
-- In Neovim command line
:lua require('nexus.state.folds').clear_repo_state()
```

This will restore all sections to their default expanded state on the next Nexus open.

## Technical Details

### Architecture

The collapsible sections feature consists of four main components:

#### 1. State Management (`lua/nexus/state/folds.lua`)
- Loads and saves fold state to disk
- Manages per-repository state
- Provides API for querying and updating fold preferences

#### 2. Folding System (`lua/nexus/ui/folding.lua`)
- Creates Neovim folds for each section
- Applies saved fold states after rendering
- Handles fold toggling with state persistence
- Generates custom fold text with arrows and line counts

#### 3. Section Rendering (`lua/nexus/render/components/sections.lua`)
- Adds `▼` indicators to section headers
- Maintains section header format for fold detection

#### 4. Layout Tracking (`lua/nexus/render/layout.lua`)
- Tracks line ranges for each section
- Provides `section_ranges` data for fold creation
- Enables cursor-based section detection

### Implementation Notes

**Fold Method**: Uses Neovim's `manual` fold method for precise control over fold boundaries.

**Fold Range**: Folds start after the section header and empty line, keeping the header visible:
- Header line: Always visible (e.g., "▼ Git Status:")
- Empty line: Always visible
- Content lines: Folded/unfolded based on state
- This ensures section headers remain navigable even when collapsed

**Fold Text**: Custom `foldtext` function displays:
- `▶` arrow indicating collapsed state
- Section name (extracted from header)
- Line count of hidden content

**Section Detection**: Fold toggle works anywhere in a section by:
1. Getting cursor line number
2. Looking up line in `section_ranges`
3. Toggling fold at the content start line (header + 2)

**Performance Optimization**:
- Native Vim fold speed - no custom rendering or blocking operations
- Asynchronous state persistence using `vim.schedule()` - doesn't block the UI
- Minimal cursor movement - instant visual feedback
- No excessive logging during toggle operations

**State Persistence**: Uses JSON serialization with repository path as key, allowing different fold preferences per project. State is saved asynchronously after fold toggle completes.

## Troubleshooting

### Folds Not Working

**Check section ranges are being tracked:**
```lua
-- In Nexus buffer
:lua print(vim.inspect(require('nexus.state.ui').get_section_ranges()))
```

Should show ranges like:
```lua
{
  todos = { start_line = 15, end_line = 23 },
  git_status = { start_line = 25, end_line = 45 },
  ...
}
```

**Check fold creation:**
```bash
# Watch debug log
tail -f /tmp/nexus-debug.log

# Look for lines like:
# [FOLD] Successfully created fold: section=git_status, start=25, end=45
```

**Check buffer folding is enabled:**
```vim
" In Nexus buffer
:set foldmethod?  " Should show 'manual'
:set foldenable?  " Should show 'foldenable'
```

### Keybindings Not Responding

**Verify keymaps are set:**
```lua
-- In Nexus buffer
:lua print(vim.inspect(vim.api.nvim_buf_get_keymap(0, 'n')))
```

Look for entries with `za`, `<Tab>`, and `<Space>` callbacks.

**Check for keymap conflicts:**
Some plugins override `<Tab>` or `<Space>`. If this occurs:
- Use `za` (less likely to conflict)
- Check your keymap configuration for conflicts
- Bind a different key if needed

### State Not Persisting

**Verify cache directory exists:**
```bash
ls -la ~/.cache/nexus/
# Should show fold_state.json
```

**Check file permissions:**
```bash
ls -la ~/.cache/nexus/fold_state.json
# Should be readable/writable
```

**Manually inspect state:**
```bash
cat ~/.cache/nexus/fold_state.json | jq
```

### Sections Always Start Expanded

This is expected behavior if:
- First time opening Nexus in this repository
- No fold state saved yet (toggle any section to create state)
- State file was cleared or deleted

**To verify state is saving:**
1. Open Nexus
2. Collapse a section (press `Tab`)
3. Close Nexus (`:bd`)
4. Reopen Nexus
5. Section should remain collapsed

## Configuration

### Disabling Collapsible Sections

If you prefer sections to always be visible (no folding):

```lua
-- In your Nexus setup
require('nexus').setup({
  -- Current config...
})

-- Disable fold keymaps (remove from keymap setup)
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'Nexus',
  callback = function(args)
    local buf = args.buf
    -- Unmap fold keys if needed
    vim.api.nvim_buf_del_keymap(buf, 'n', 'za')
    vim.api.nvim_buf_del_keymap(buf, 'n', '<Tab>')
    vim.api.nvim_buf_del_keymap(buf, 'n', '<Space>')
  end
})
```

### Custom Fold Keybindings

To use different keys for toggling:

```lua
-- Example: Use 'zf' instead of Tab/Space
vim.api.nvim_create_autocmd('BufEnter', {
  pattern = 'Nexus',
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    local folding = require('nexus.ui.folding')

    -- Remove default keymaps
    pcall(vim.api.nvim_buf_del_keymap, buf, 'n', '<Tab>')
    pcall(vim.api.nvim_buf_del_keymap, buf, 'n', '<Space>')

    -- Add custom keymap
    vim.api.nvim_buf_set_keymap(buf, 'n', 'zf', '', {
      noremap = true,
      silent = true,
      callback = function()
        folding.toggle_fold_at_cursor(buf)
      end
    })
  end
})
```

## Related Features

- **Section Navigation** (`{` and `}`) - Jump between sections
- **Git Status Folding** - Automatically folds overflow files when `git_status_count` is set
- **Section Order** - Configure which sections appear via `config.section_order`

## API Reference

### `nexus.state.folds`

```lua
local folds = require('nexus.state.folds')

-- Check if section is open (returns boolean)
folds.is_section_open('git_status')

-- Set section state explicitly
folds.set_section_state('todos', false)  -- Close todos
folds.set_section_state('todos', true)   -- Open todos

-- Toggle section state (returns new state)
local is_now_open = folds.toggle_section_state('recent_commits')

-- Clear all fold state for current repo
folds.clear_repo_state()

-- Get complete state for current repo
local state = folds.get_repo_state()
-- Returns: { git_status = "open", todos = "closed", ... }
```

### `nexus.ui.folding`

```lua
local folding = require('nexus.ui.folding')

-- Setup folds for all sections
folding.setup_section_folds(buf, section_ranges)

-- Apply saved fold states
folding.apply_fold_states(buf, section_ranges)

-- Toggle fold at cursor position
folding.toggle_fold_at_cursor(buf)

-- Get section name from line number
local section = folding.get_section_at_line(line_num, section_ranges)
```

## Implementation History

**Version**: Added in v2.0.0 (2025-09-27)

**Changes**:
- Added fold indicators (`▼`/`▶`) to all section headers
- Implemented persistent fold state storage per repository
- Added three keybindings (`za`, `Tab`, `Space`) for toggling
- Extended layout system to track section line ranges
- Created custom fold text generation for collapsed sections
- Integrated fold creation into main render pipeline

**Architecture Decisions**:
- **Manual folds** over automatic folding for precise control
- **Per-repository state** to support different workflows per project
- **JSON persistence** for human-readable, debuggable state files
- **Multiple keybindings** to accommodate different user preferences
- **Anywhere-in-section toggling** for improved UX (no need to jump to header)

## See Also

- [Git Commands](./git-commands.md) - Git integration features
- [Performance Analysis](./PERFORMANCE_ANALYSIS.md) - Rendering optimization details
- [Technical Specifications](./TECHNICAL_SPECIFICATIONS.md) - Overall architecture
