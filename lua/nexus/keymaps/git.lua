--- Git-specific keymap handlers
--- Handles git commit browsing, file operations, and status management
---@module nexus.keymaps.git

local M = {}

local logger = require('nexus.logger')
local commit_popup = require('nexus.ui.popups.commit')
local actions = require('nexus.actions')
local git_command = require('nexus.git.command')
local git_state = require('nexus.state.git')

--- Handle Enter key in commits section
function M.handle_enter_commits(current_line)
  commit_popup.show_commit_details(current_line)
end

--- Handle 'v' key in commits section - open commit in vgit
function M.handle_vgit_commit(current_line)
  -- Extract commit hash from the line (accounting for review icons)
  local hash = current_line:match("%s*[☐✓⚠]?%s*([a-f0-9]+)")
  if not hash then
    vim.notify("Could not extract commit hash from line", vim.log.levels.ERROR)
    return
  end

  -- Check if vgit is available
  local ok, vgit = pcall(require, 'vgit')
  if not ok then
    vim.notify("vgit plugin not found. Please install it first.", vim.log.levels.ERROR)
    return
  end

  -- Open commit in vgit
  vgit.project_diff_preview(hash)
end

--- Handle 'v' key in git status section - open file diff in vgit
function M.handle_vgit_file_diff(current_line)
  -- Extract filename from the git status line
  local filename = current_line:match("^%s*[MADRCU?][MADRCU?]? (.-)%s+%+") or
                  current_line:match("^%s*[MADRCU?][MADRCU?]? (.-)%s+%-") or
                  current_line:match("^%s*[MADRCU?][MADRCU?]? (.+)$")

  if not filename then
    vim.notify("Could not extract filename from line", vim.log.levels.ERROR)
    return
  end

  filename = filename:gsub("^%s+", ""):gsub("%s+$", "")

  -- Check if vgit is available
  local ok, vgit = pcall(require, 'vgit')
  if not ok then
    vim.notify("vgit plugin not found. Please install it first.", vim.log.levels.ERROR)
    return
  end

  -- Get full path
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
  local full_path = git_root and (git_root .. '/' .. filename) or filename

  -- Open file diff in vgit
  vgit.buffer_diff_preview(full_path)
end

--- Handle Enter key in git status section  
function M.handle_enter_git_status(current_line, config)
  local filename = current_line:match("^%s*[MADRCU?][MADRCU?]? (.-)%s+%+") or 
                  current_line:match("^%s*[MADRCU?][MADRCU?]? (.-)%s+%-") or
                  current_line:match("^%s*[MADRCU?][MADRCU?]? (.+)$")
  if filename then
    filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
    
    local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
    local full_path = git_root and (git_root .. '/' .. filename) or filename
    
    local first_line = M.get_first_changed_line(filename)
    local goto_line = first_line and (' | ' .. first_line) or ''
    
    local edit_cmd = 'edit ' .. vim.fn.fnameescape(full_path) .. ' | set number | set signcolumn=yes' .. goto_line
    require('nexus.keymaps.dashboard').handle_action(config, edit_cmd)
  end
end

--- Handle git add operation
function M.handle_add(buf, render_callback)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  
  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  logger.debug('GIT_ADD', string.format('Cursor at line %d: "%s"', line_num, current_line or 'nil'))
  
  -- Check if it's a git status line
  if current_line and current_line:match("%s*  [MADRCU?][MADRCU?]? ") then
    local filename = current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%+") or 
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%-") or
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.+)$")
    if filename then
      filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
      
      -- Use action system
      actions.execute('git.add', {
        filename = filename,
        refresh_callback = function()
          git_state.update_git_status(true) -- force refresh
          local files = git_state.get_git_status()
          render_callback(buf, files)
        end
      })
    end
  end
end

--- Handle git unstage operation
function M.handle_unstage(buf, render_callback)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  
  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  logger.debug('GIT_UNSTAGE', string.format('Cursor at line %d: "%s"', line_num, current_line or 'nil'))
  
  -- Check if it's a git status line
  if current_line and current_line:match("%s*  [MADRCU?][MADRCU?]? ") then
    local filename = current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%+") or 
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%-") or
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.+)$")
    if filename then
      filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
      
      -- Use action system
      actions.execute('git.unstage', {
        filename = filename,
        refresh_callback = function()
          git_state.update_git_status(true) -- force refresh
          local files = git_state.get_git_status()
          render_callback(buf, files)
        end
      })
    end
  end
end

--- Handle git commit operation
function M.handle_commit(buf, render_callback, config)
  actions.execute('git.commit', {
    interactive = true,
    refresh_callback = function()
      render_callback(buf)
    end
  })
end

--- Handle git command window
function M.handle_command_window(buf, render_callback, config)
  git_command.create_git_command_window(function()
    -- Update git status through state system and refresh
    git_state.update_git_status(true) -- force refresh
    local files = git_state.get_git_status()
    render_callback(buf, files)
  end)
end

--- Get the first changed line in a file using git diff
function M.get_first_changed_line(filename)
  if not filename then
    return nil
  end
  
  -- Use git diff to find the first changed line
  local git_output = vim.fn.systemlist('git diff --unified=0 HEAD -- "' .. filename .. '"')
  if vim.v.shell_error ~= 0 then
    -- Try with staged changes
    git_output = vim.fn.systemlist('git diff --unified=0 --staged HEAD -- "' .. filename .. '"')
    if vim.v.shell_error ~= 0 then
      return nil
    end
  end
  
  -- Parse the @@ line to get line number
  for _, line in ipairs(git_output) do
    local line_match = line:match("^@@%s+%-(%d+)")
    if line_match then
      return tonumber(line_match)
    end
    
    local plus_match = line:match("^@@%s+%-?%d*,?%d*%s+%+(%d+)")
    if plus_match then
      return tonumber(plus_match)
    end
  end
  
  return nil
end

return M
