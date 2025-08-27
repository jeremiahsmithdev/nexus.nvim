--- Navigation utilities for Nexus buffer
--- Handles cursor movement and section navigation with intelligent line detection
--- Only moves between actionable lines, skipping logos, headers, and empty lines
---@module nexus.navigation

local M = {}

--- Check if a line is actionable (can be interacted with)
---@param line string The line content
---@param line_num number The line number (1-indexed)
---@param logo_end_line number The last line of the logo section
---@param section_ranges table|nil Section ranges for skipping non-actionable sections
---@return boolean true if the line is actionable
function M.is_actionable_line(line, line_num, logo_end_line, section_ranges)
  -- Skip logo section completely
  if line_num <= logo_end_line then
    return false
  end
  
  -- Skip keyboard shortcuts section completely
  if section_ranges and section_ranges.keyboard_shortcuts then
    local shortcuts_range = section_ranges.keyboard_shortcuts
    if line_num >= shortcuts_range.start_line and line_num <= shortcuts_range.end_line then
      return false
    end
  end
  
  -- Skip empty lines
  if line:match("^%s*$") then
    return false
  end
  
  -- Skip section titles (lines ending with colon)
  if line:match(":$") then
    return false
  end
  
  return true
end

--- Move cursor to the next actionable line in specified direction
---@param direction number 1 for forward, -1 for backward
---@param logo_end_line number The last line of the logo section
---@param section_ranges table|nil Section ranges for skipping non-actionable sections
function M.move_to_next_actionable(direction, logo_end_line, section_ranges)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local step = direction > 0 and 1 or -1
  
  for i = current_line + step, direction > 0 and #lines or 1, step do
    if lines[i] then
      if M.is_actionable_line(lines[i], i, logo_end_line, section_ranges) then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return
      end
    end
  end
end

--- Find the first actionable line after the logo
---@param logo_end_line number The last line of the logo section
---@param section_ranges table|nil Section ranges for skipping non-actionable sections
---@return number|nil line_num The line number of the first actionable line, or nil if none found
function M.find_first_actionable_line(logo_end_line, section_ranges)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  
  for i = logo_end_line + 1, #lines do
    if lines[i] then
      if M.is_actionable_line(lines[i], i, logo_end_line, section_ranges) then
        return i
      end
    end
  end
  
  return nil
end

--- Navigate to the first actionable line of the previous section
---@param get_current_section function Function to determine current section
---@param config table Nexus configuration
---@param logo_end_line number The last line of the logo section
---@param section_ranges table|nil Section ranges for skipping non-actionable sections
function M.navigate_to_previous_section(get_current_section, config, logo_end_line, section_ranges)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local current_section = get_current_section(lines, current_line, config)
  
  -- Find previous section header
  for i = current_line - 1, 1, -1 do
    local line = lines[i]
    if line and line:match("^%s*[^%s].*:%s*$") then
      local section = get_current_section(lines, i, config)
      if section ~= current_section then
        -- Found different section, move to its first actionable line
        vim.api.nvim_win_set_cursor(0, {i + 1, 0})
        M.move_to_next_actionable(1, logo_end_line, section_ranges)
        return
      end
    end
  end
  
  -- No previous section, go to top
  vim.cmd('normal! gg')
end

--- Navigate to the first actionable line of the next section
---@param get_current_section function Function to determine current section
---@param config table Nexus configuration
---@param logo_end_line number The last line of the logo section
---@param section_ranges table|nil Section ranges for skipping non-actionable sections
function M.navigate_to_next_section(get_current_section, config, logo_end_line, section_ranges)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local current_section = get_current_section(lines, current_line, config)
  
  -- Find next section header
  for i = current_line + 1, #lines do
    local line = lines[i]
    if line and line:match("^%s*[^%s].*:%s*$") then
      local section = get_current_section(lines, i, config)
      if section ~= current_section then
        -- Found different section, move to its first actionable line
        vim.api.nvim_win_set_cursor(0, {i + 1, 0})
        M.move_to_next_actionable(1, logo_end_line, section_ranges)
        return
      end
    end
  end
  
  -- No next section, go to end
  vim.cmd('normal! G')
end

--- Go to first actionable line while keeping logo visible in viewport
---@param logo_end_line number The last line of the logo section
---@param section_ranges table|nil Section ranges for skipping non-actionable sections
function M.go_to_first_actionable(logo_end_line, section_ranges)
  local target_line = M.find_first_actionable_line(logo_end_line, section_ranges)
  
  if target_line then
    -- First, scroll to show the top of the buffer (logo)
    vim.cmd('normal! gg')
    -- Then set cursor to the actionable line
    vim.api.nvim_win_set_cursor(0, {target_line, 0})
  else
    -- Fallback: just go to top if no actionable line found
    vim.cmd('normal! gg')
  end
end

return M