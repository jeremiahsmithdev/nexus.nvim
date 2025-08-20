local M = {}

local cursor = require('nexus.cursor')
local shortcuts_registry = require('nexus.shortcuts_registry')

function M.get_keyboard_shortcuts(config, is_git_repo)
  if not config.show_keyboard_shortcuts then
    return {}
  end
  
  local global_line = "r -> refresh, q/esc -> quit" .. (is_git_repo and ", c -> commit" or "")
  
  return {
    global_line,
    "" -- This will be populated dynamically based on cursor position
  }
end

-- Get current contextual shortcuts based on cursor position
function M.get_current_contextual_shortcuts(buf, config, is_git_repo)
  if not config.show_keyboard_shortcuts then
    return ""
  end
  
  -- Get current section from cursor position
  local current_section = cursor.get_current_section(buf)
  
  -- Get section info to determine if we're on an actionable line
  local section_info = cursor.get_section_info(buf, current_section)
  
  -- Only show contextual shortcuts if we're on an actionable line
  if not section_info.is_actionable then
    return ""
  end
  
  -- Get formatted shortcuts for the current section
  return shortcuts_registry.get_formatted_section_shortcuts(current_section)
end

-- Update the contextual shortcuts line in the buffer
function M.update_contextual_shortcuts(buf, config, is_git_repo, section_ranges)
  if not config.show_keyboard_shortcuts or not section_ranges.keyboard_shortcuts then
    return
  end
  
  -- Get current contextual shortcuts
  local contextual_line = M.get_current_contextual_shortcuts(buf, config, is_git_repo)
  
  -- Get the line number for the second line of keyboard shortcuts
  local shortcuts_range = section_ranges.keyboard_shortcuts
  local contextual_line_num = shortcuts_range.start_line + 1 -- Second line of shortcuts section
  
  if contextual_line_num > shortcuts_range.end_line then
    return -- Safety check
  end
  
  -- Update the buffer with new contextual shortcuts
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  
  -- Get window width for centering calculation
  local width = vim.fn.winwidth(0)
  if vim.env.TMUX then
    local pane_width = vim.fn.system("tmux display-message -p '#{pane_width}'"):gsub('\n', '')
    local tmux_width = tonumber(pane_width)
    if tmux_width then
      width = tmux_width
    end
  end
  
  -- Center the contextual line individually
  local center = require('nexus.ui.center')
  local centered_lines = center.center_lines_individually({contextual_line}, width)
  local new_line = centered_lines[1]
  
  vim.api.nvim_buf_set_lines(buf, contextual_line_num - 1, contextual_line_num, false, {new_line})
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
end


return M