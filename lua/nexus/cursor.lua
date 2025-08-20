local M = {}

-- Store section ranges globally for cursor detection
local section_ranges = {}

-- Update section ranges (called from render.lua)
function M.update_section_ranges(ranges)
  section_ranges = ranges or {}
end

-- Get current section based on cursor position
function M.get_current_section(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return "unknown"
  end
  
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  
  -- Check each section range
  for section_name, range in pairs(section_ranges) do
    if range.start_line and range.end_line then
      if line_num >= range.start_line and line_num <= range.end_line then
        return section_name
      end
    end
  end
  
  -- If not in any tracked section, determine by line content
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  if not current_line then
    return "unknown"
  end
  
  -- Check for dashboard buttons
  if current_line:match("Find file") or current_line:match("Recently opened") or 
     current_line:match("Find word") or current_line:match("New file") or 
     current_line:match("Bookmarks") or current_line:match("Restore session") then
    return "dashboard_buttons"
  end
  
  -- Check for git status files (status characters pattern)
  if current_line:match("%s*  [MADRCU?][MADRCU?]? ") then
    return "git_status"
  end
  
  -- Check for commits (hash pattern)
  if current_line:match("%s+[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+") then
    return "recent_commits"
  end
  
  -- Check for Claude conversations
  if current_line:match("^ %d+%.") then
    return "claude_conversations"
  end
  
  -- Check for section headers
  if current_line:match("Recent Commits:") then
    return "recent_commits_header"
  elseif current_line:match("Git Status:") then
    return "git_status_header"  
  elseif current_line:match("Claude Conversations:") then
    return "claude_conversations_header"
  end
  
  -- Default to logo section if nothing else matches
  return "logo"
end

-- Get section-specific information
function M.get_section_info(buf, section_name)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local current_line = lines[line_num]
  
  return {
    section = section_name,
    line_number = line_num,
    line_content = current_line,
    is_actionable = M.is_actionable_line(section_name, current_line)
  }
end

-- Determine if current line is actionable
function M.is_actionable_line(section_name, line_content)
  if not line_content then
    return false
  end
  
  -- Dashboard buttons are actionable
  if section_name == "dashboard_buttons" then
    return line_content:match("Find file") or line_content:match("Recently opened") or 
           line_content:match("Find word") or line_content:match("New file") or 
           line_content:match("Bookmarks") or line_content:match("Restore session")
  end
  
  -- Git status files are actionable
  if section_name == "git_status" then
    return line_content:match("%s*  [MADRCU?][MADRCU?]? ")
  end
  
  -- Recent commits are actionable
  if section_name == "recent_commits" then
    return line_content:match("%s+[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+")
  end
  
  -- Claude conversations are actionable
  if section_name == "claude_conversations" then
    return line_content:match("^ %d+%.")
  end
  
  return false
end

return M