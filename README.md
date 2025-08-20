- AI is like a bullet train
- Git is like the train track with each commit representing a rung holding that rail up
- Commit often
- Use GBoard to keep you on task with your git commits, giving you a persistent visual reminder

This plugin is built for people who are doing fast iteration with AI pair programming in Neovim.Or indeed anyone who ever finds them self developing faster than they commit and needs a constant visual reminder to commit their changes incrementally. 

# GBoard.nvim

A Neovim plugin that provides a git dashboard interface similar to popular dashboard plugins like alpha.nvim. It opens automatically on startup when no files are specified and displays git information in a clean, centered layout.

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
  "yourusername/GBoard.nvim",
  config = function()
    require("gboard").setup({
      -- Configuration options (all optional)
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "yourusername/GBoard.nvim",
  config = function()
    require("gboard").setup()
  end
}
```

## Configuration

GBoard.nvim works out of the box with sensible defaults. All configuration options are optional:

```lua
require("gboard").setup({
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

GBoard.nvim supports displaying images as logos using the [image.nvim](https://github.com/3rd/image.nvim) plugin.

### Prerequisites

1. Install the [image.nvim](https://github.com/3rd/image.nvim) plugin
2. Ensure your terminal supports image display (Kitty, WezTerm with Kitty Graphics Protocol, or ueberzugpp)

### Configuration Examples

```lua
-- Use default included Neovim logo image
require("gboard").setup({
  use_image_logo = true
})

-- Use custom image with default size
require("gboard").setup({
  use_image_logo = true,
  image_logo_path = vim.fn.expand("~/.config/nvim/my-logo.png")
})

-- Use custom image with custom size
require("gboard").setup({
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

### In GBoard Buffer

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

GBoard automatically opens when:
- Neovim is started without file arguments
- Current directory is a git repository
- No other buffers are loaded

You can also manually open GBoard with `:GBoard`

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

GBoard includes optional integration with Claude Code for conversation management:

```lua
require("gboard").setup({
  show_claude_conversations = true  -- Enable Claude Code integration
})
```

This feature allows resuming Claude Code conversations directly from the dashboard.

## Architecture

GBoard.nvim is built with a modular architecture:

- **Clean separation**: Each component (logo, dashboard, git operations) is a separate module
- **Configurable rendering**: All visual elements can be enabled/disabled independently  
- **Smart centering**: Content adapts to window width and tmux environments
- **Performance focused**: Minimal startup impact, efficient git operations

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## License

MIT License - see LICENSE file for details.
