local M = {}

-- Use centralized state management
local ui_state = require('nexus.state.ui')

-- Update section ranges (called from render.lua) - now delegates to state
function M.update_section_ranges(ranges)
  ui_state.update_section_ranges(ranges)
end

-- Get current section based on cursor position - now uses centralized state
function M.get_current_section(buf)
  local section_info = ui_state.get_current_section_info(buf)
  local section_name = section_info.section
  
  -- Update current section in state
  ui_state.update_current_section(section_name)
  
  return section_name
end

-- Get section-specific information - now delegates to state
function M.get_section_info(buf, section_name)
  if section_name then
    -- If section_name is provided, create info for that specific section
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line_num = cursor[1]
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local current_line = lines[line_num]
    
    return {
      section = section_name,
      line_number = line_num,
      line_content = current_line,
      is_actionable = ui_state.is_actionable_line(section_name, current_line)
    }
  else
    -- Get current section info from state
    return ui_state.get_current_section_info(buf)
  end
end

-- Legacy function - now delegates to state
function M.is_actionable_line(section_name, line_content)
  return ui_state.is_actionable_line(section_name, line_content)
end

return M