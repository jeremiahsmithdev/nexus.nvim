local M = {}

local state = require('nexus.state')

-- UI state management
function M.update_section_ranges(section_ranges)
  local old_ranges = state.get('ui', 'section_ranges')
  state.set('ui', 'section_ranges', section_ranges or {})
  
  -- Emit event for reactive updates
  state.notify('ui', 'section_ranges_updated', section_ranges, old_ranges)
end

-- Get current section ranges
function M.get_section_ranges()
  return state.get('ui', 'section_ranges') or {}
end

-- Update current section based on cursor position
function M.update_current_section(section_name)
  local old_section = state.get('ui', 'current_section')
  state.set('ui', 'current_section', section_name or 'unknown')
  
  -- Emit event for reactive updates if section changed
  if old_section ~= section_name then
    state.notify('ui', 'current_section_changed', section_name, old_section)
  end
end

-- Get current section
function M.get_current_section()
  return state.get('ui', 'current_section') or 'unknown'
end

-- Update configuration
function M.update_config(config)
  local old_config = state.get('ui', 'config')
  state.set('ui', 'config', config or {})
  
  -- Emit event for reactive updates
  state.notify('ui', 'config_updated', config, old_config)
end

-- Get current configuration
function M.get_config()
  return state.get('ui', 'config') or {}
end

-- Update buffer information
function M.update_buffer_info(buf, buffer_info)
  local buffers = state.get('ui', 'buffers') or {}
  buffers[buf] = buffer_info
  state.set('ui', 'buffers', buffers)
  
  -- Emit event for reactive updates
  state.notify('ui', 'buffer_updated', {buf = buf, info = buffer_info}, nil)
end

-- Get buffer information
function M.get_buffer_info(buf)
  local buffers = state.get('ui', 'buffers') or {}
  return buffers[buf]
end

-- Get all buffers
function M.get_all_buffers()
  return state.get('ui', 'buffers') or {}
end

-- Update window dimensions
function M.update_window_dimensions(width, height)
  local old_dims = state.get('ui', 'window_dimensions')
  local new_dims = {width = width, height = height}
  state.set('ui', 'window_dimensions', new_dims)
  
  -- Emit event for reactive updates if dimensions changed
  if not old_dims or old_dims.width ~= width or old_dims.height ~= height then
    state.notify('ui', 'window_resized', new_dims, old_dims)
  end
end

-- Get window dimensions
function M.get_window_dimensions()
  return state.get('ui', 'window_dimensions') or {width = 80, height = 24}
end

-- Update logo section info
function M.update_logo_section(logo_section)
  state.set('ui', 'logo_section', logo_section)
  state.notify('ui', 'logo_updated', logo_section, nil)
end

-- Get logo section info
function M.get_logo_section()
  return state.get('ui', 'logo_section')
end

-- Subscribe to UI state changes
function M.subscribe_to_ui_changes(callback)
  return state.subscribe('ui', callback)
end

-- Clear UI state for a specific buffer
function M.clear_buffer_state(buf)
  local buffers = state.get('ui', 'buffers') or {}
  buffers[buf] = nil
  state.set('ui', 'buffers', buffers)
  
  state.notify('ui', 'buffer_cleared', {buf = buf}, nil)
end

-- Get section information based on cursor position (extracted from cursor.lua logic)
function M.get_current_section_info(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return {section = "unknown", line_number = 0, line_content = "", is_actionable = false}
  end
  
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local section_ranges = M.get_section_ranges()
  
  -- Check each section range first
  for section_name, range in pairs(section_ranges) do
    if range.start_line and range.end_line then
      if line_num >= range.start_line and line_num <= range.end_line then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local current_line = lines[line_num]
        
        return {
          section = section_name,
          line_number = line_num,
          line_content = current_line or "",
          is_actionable = M.is_actionable_line(section_name, current_line)
        }
      end
    end
  end
  
  -- Fallback to content-based detection
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num] or ""
  local section = M.detect_section_by_content(current_line)
  
  return {
    section = section,
    line_number = line_num,
    line_content = current_line,
    is_actionable = M.is_actionable_line(section, current_line)
  }
end

-- Detect section by line content
function M.detect_section_by_content(line_content)
  if not line_content then
    return "unknown"
  end
  
  -- Check for dashboard buttons
  if line_content:match("Find file") or line_content:match("Recently opened") or 
     line_content:match("Find word") or line_content:match("New file") or 
     line_content:match("Bookmarks") or line_content:match("Restore session") then
    return "dashboard_buttons"
  end
  
  -- Check for git status files
  if line_content:match("%s*  [MADRCU?][MADRCU?]? ") then
    return "git_status"
  end
  
  -- Check for commits
  if line_content:match("%s+[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+") then
    return "recent_commits"
  end
  
  -- Check for Claude conversations
  if line_content:match("^ %d+%.") then
    return "claude_conversations"
  end
  
  -- Check for section headers
  if line_content:match("Recent Commits:") then
    return "recent_commits_header"
  elseif line_content:match("Git Status:") then
    return "git_status_header"  
  elseif line_content:match("Claude Conversations:") then
    return "claude_conversations_header"
  end
  
  return "logo"
end

-- Check if line is actionable
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

-- Initialize UI state
function M.init()
  state.update('ui', {
    section_ranges = {},
    current_section = 'unknown',
    config = {},
    buffers = {},
    window_dimensions = {width = 80, height = 24},
    logo_section = nil
  })
end

return M