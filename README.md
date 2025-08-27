This plugin is built for people who are doing fast iteration with AI pair programming in Neovim.Or indeed anyone who ever finds them self developing faster than they commit and needs a constant visual reminder to commit their changes incrementally. 

## Why?
This plugin is especially designed for Neovim developers who are rapidly iterating and prototyping with AI code generation and may have multiple projects on the go at any one time.

What problem does this solve?
- Context switching between git and AI pair programming is a common challenge for developers.
- Context switching between the terminal/editor and project management tools is a common challenge for developers

- For example if you have two terminals open, one with Neovim for reviewing and editing code, and another with Claude Code for your AI pair programming,
  - Nexus.nvim gives you quick access to git and project management software to help you stay on task without needing to leave Neovim or your terminal
  - No need to open another pane/window. Stay in deep focus mode and continuously iterate with git and Linear

I always wanted a central location in Neovim to see what is happening in my project so I finally created Nexus.nvim to serve this purpose.
It shows my favourite git information in a clean, centered layout. No more continously running "git status" and "git log" and then forgetting how many features I have added since the last commit. This plugin has become an invaluable tool to curb bad git habits and hold me accountable with a constant visual reminder of where I am at and what I am working on.

Commit first, commit often.

- AI is like a bullet train
- Git is like the train tracks with each commit a sleeper holidng the track up.
- Use Nexus to keep you on task with your git commits, giving you a persistent visual reminder

# Nexus.nvim

A highly configurable Neovim plugin that provides a git dashboard interface similar to popular dashboard plugins. It can open automatically on startup or just when called with :Nexus depending on user preferneces.

Nexus includes many configurable sections each of which can be enabled/disabled and reordered.
Each section has its own keyboard shortcuts which are dynamically shown as subtle hints when your cursor is in that section.

Sections included:
- standard startup dashboard buttons
  - new file, find file, find word, etc.
- Git sections **(primary feature)**
  - Recent commits
  - Git status
- Linear issues
  - Create and update issues directly from Nexus

Planned Sections:
- Github Issues
- Todo List
- Todoist

## Features

- 🎨 **Neovim ASCII art logo** (centered, inspired by alpha.nvim)
- 🖼️ **Optional image logo support** via image.nvim plugin
- 🔧 **Dashboard buttons** for common actions (optional, configurable)
- 📝 **Recent git commits** (last 3 with colors and branch info)
- 📊 **Git status** with diff statistics similar to `git diff --stat`
- ⚡ **Fast git operations** (stage, unstage, commit with keybindings)
- 🔄 **Tmux integration** for Claude Code conversation resuming
- 🎯 **Smart centering** that works in full windows and tmux splits

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "yourusername/Nexus.nvim",
  config = function()
    require("nexus").setup({
      -- Configuration options (all optional)
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "yourusername/Nexus.nvim",
  config = function()
    require("nexus").setup()
  end
}
```

## Configuration

Nexus.nvim works out of the box with sensible defaults. All configuration options are optional:

```lua
require("nexus").setup({
  -- Dashboard sections
  show_dashboard_buttons = true,  -- Show dashboard-style buttons with icons
  show_recent_commits = true,     -- Show git commits section
  show_git_status = true,         -- Show git status section
  recent_commits_count = 3,       -- Number of recent commits to show
  
  -- Logo configuration
  use_image_logo = false,         -- Use image.nvim for logo (requires image.nvim plugin)
  image_logo_path = nil,          -- Custom image path (defaults to plugin's neovim.png)
  image_logo_width = 30,          -- Width of the image in character units
  image_logo_height = 6,          -- Height of the image in line units
  
  -- Advanced options
  show_claude_conversations = false, -- Show Claude Code conversations (disabled by default)
})
```

## Image Logo Support

Nexus.nvim supports displaying images as logos using the [image.nvim](https://github.com/3rd/image.nvim) plugin.

### Prerequisites

1. Install the [image.nvim](https://github.com/3rd/image.nvim) plugin
2. Ensure your terminal supports image display (Kitty, WezTerm with Kitty Graphics Protocol, or ueberzugpp)

### Configuration Examples

```lua
-- Use default included Neovim logo image
require("nexus").setup({
  use_image_logo = true
})

-- Use custom image with default size
require("nexus").setup({
  use_image_logo = true,
  image_logo_path = vim.fn.expand("~/.config/nvim/my-logo.png")
})

-- Use custom image with custom size
require("nexus").setup({
  use_image_logo = true,
  image_logo_path = "/path/to/your/logo.png",
  image_logo_width = 40,    -- Wider image
  image_logo_height = 8     -- Taller image
})
```

### ⚠️ Testing Note

**Image logo support is experimental and depends on your terminal's image rendering capabilities:**

- **Best compatibility**: Kitty terminal with native image support
- **Good compatibility**: WezTerm with Kitty Graphics Protocol enabled
- **Limited compatibility**: Other terminals with ueberzugpp backend

If you experience positioning issues or images not displaying correctly, please:
1. Test with Kitty terminal first to verify functionality
2. Ensure image.nvim is properly configured for your terminal
3. Try different image sizes with `image_logo_width` and `image_logo_height`
4. Check that your image file is readable and in a supported format (PNG, JPG, etc.)

The plugin will automatically fall back to the ASCII logo if image rendering fails.

## Keybindings

### In Nexus Buffer

| Key | Action |
|-----|--------|
| `<Enter>` | Open file (on git status lines) or activate button |
| `a` | Stage file under cursor |
| `u` | Unstage file under cursor |
| `c` | Open commit window |
| `r` | Refresh git status |
| `<leader>g` | Open git command window |
| `q` / `<Esc>` | Smart quit (close buffer or exit Neovim) |

### Global Shortcuts (Dashboard Buttons)

| Key | Action |
|-----|--------|
| `<leader>f` | Find file (Telescope) |
| `<leader>r` | Recently opened files |
| `<leader>w` | Find word (live grep) |
| `<leader>n` | New file |
| `<leader>b` | Bookmarks |
| `<leader>s` | Restore session |

## Auto-open Behavior

Nexus automatically opens when:
- Neovim is started without file arguments
- Current directory is a git repository
- No other buffers are loaded

You can also manually open Nexus with `:Nexus`

## Git Integration

### Git Status Display
- Shows modified, added, deleted, and untracked files
- Visual diff statistics with `+`/`-` indicators
- Color-coded status indicators
- Quick staging/unstaging with `a`/`u` keys

### Recent Commits
- Displays last 3 commits by default (configurable)
- Shows commit hashes, branch decorations, and messages
- Syntax highlighting for HEAD pointer and branch names

### Git Operations
- **Stage files**: Press `a` on any git status line
- **Unstage files**: Press `u` on any git status line  
- **Commit**: Press `c` to open commit message window
- **Advanced git**: Press `<leader>g` for git command interface

## Claude Code Integration

Nexus includes optional integration with Claude Code for conversation management:

```lua
require("nexus").setup({
  show_claude_conversations = true  -- Enable Claude Code integration
})
```

This feature allows resuming Claude Code conversations directly from the dashboard.

## Architecture

Nexus.nvim is built with a modular architecture:

- **Clean separation**: Each component (logo, dashboard, git operations) is a separate module
- **Configurable rendering**: All visual elements can be enabled/disabled independently  
- **Smart centering**: Content adapts to window width and tmux environments
- **Performance focused**: Minimal startup impact, efficient git operations

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

MIT License - see LICENSE file for details.
