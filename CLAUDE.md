# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NEVER lead with "You're absolutely right!" -> be more creative and give more meaningful information instead of trying to simply agree with the user.

GBoard.nvim is a Neovim plugin that provides a git dashboard interface similar to popular dashboard plugins like alpha.nvim. It opens automatically on startup when no files are specified and displays:

1. Neovim ASCII art logo (centered, inspired by alpha.nvim)
2. Dashboard buttons for common actions (optional, configurable)
3. Recent git commits (last 3 with colors and branch info)
4. Git status with diff statistics similar to `git diff --stat`

## Architecture

### Core Components

**Plugin Entry Point** (`plugin/gboard.lua`):
- Registers the `:GBoard` user command
- Sets up auto-open behavior on `VimEnter` (only in git repositories when no files specified)
- Uses standard Neovim plugin loading patterns with `vim.g.loaded_gboard` guard

**Main Module** (`lua/gboard/init.lua`):
- Single-file module with all dashboard functionality
- Key functions:
  - `M.open()`: Main entry point that creates and displays the dashboard
  - `get_claude_conversations()`: Integrates with Claude Code conversation history
  - `render_git_status()`: Displays git status with visual diff stats
  - Tmux integration functions for Claude Code `/resume` functionality

### Key Features

**Dashboard Interface**:
- Neovim ASCII logo from alpha.nvim, centered dynamically based on window width
- Optional dashboard buttons (configurable via `config.show_dashboard_buttons`)
- Buttons integrate with Telescope for file operations
- Color highlighting: logo in `Type` color, button icons in `Keyword`, text in `String`

**Git Integration**:
- Recent commits display using `git log --oneline --decorate -3`
- Syntax highlighting: hashes (`Number`), HEAD (`Title`), branches (`Function`)
- Shows branch decorations and HEAD pointer like real git log

**Claude Code Integration** (disabled by default):
- Reads conversation history from `~/.claude/projects/` directory  
- Encodes project paths with dashes (e.g., `/Users/admin/dev/project` → `-Users-admin-dev-project`)
- Filters conversations by current git branch and repository
- Supports resuming conversations via tmux command sending (similar to diffusion.nvim approach)

**Git Status Display**:
- Uses `git status --porcelain=v1` for file status
- Uses `git diff --numstat` for diff statistics  
- Displays visual bars (`+++---`) similar to `git diff --stat`
- Color coding: staged files (green), unstaged/untracked (red)
- Status symbols: `??` (untracked), `M` (modified), `A` (added), etc.

**Buffer Management**:
- Creates scratch buffer (`buftype=nofile`) named "GBoard"
- Smart startup behavior: replaces empty startup buffer or opens in new tab
- Quit behavior: `q`/`<Esc>` exits Neovim if GBoard is the only buffer, otherwise just closes the buffer

### Navigation and Keymaps

**In GBoard buffer**:
- `<Enter>`: 
  - On conversation lines (format ` N. ...`): Sends `/resume <session_id>` to Claude via tmux
  - On git status lines: Opens the file in editor with proper path resolution
- `q` / `<Esc>`: Smart quit (close buffer or exit Neovim)
- `r`: Refresh git status

**File Path Resolution**:
- Uses `git rev-parse --show-toplevel` to get repository root
- Constructs full paths for reliable file opening from any directory

### Tmux Integration

The plugin includes tmux command sending functionality for Claude Code integration:
- Finds Claude processes in current tmux window by looking for "claude" or "node" commands
- Sends commands using `tmux send-keys` with proper timing and error clearing
- Based on patterns from diffusion.nvim plugin

## Development Notes

**Testing**: No formal test framework - manual testing in git repositories with various file states

**Dependencies**: Pure Neovim Lua - no external dependencies beyond standard git commands

**Debugging**: GBoard includes comprehensive logging to `/tmp/gboard-debug.log` with structured output including timestamps, PID, categories, and tmux context. Enable console output with `require('gboard.logger').set_console_output(true)` for real-time debugging.

**Claude Code Conversation Format**: 
- Conversations stored as `.jsonl` files with session metadata
- First line contains session info including `sessionId`, `cwd`, `gitBranch`
- Conversation summaries extracted from first meaningful user message (skipping system messages)
