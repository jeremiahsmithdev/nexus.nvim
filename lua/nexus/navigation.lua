--- Navigation utilities for Nexus buffer
--- Handles cursor movement and section navigation with intelligent line detection
--- Only moves between actionable lines, skipping logos, headers, and empty lines
---@module nexus.navigation

local M = {}

--- Check if a line is actionable (can be interacted with).
--- Thin wrapper around cursor_guard.is_forbidden_line — the guard is the
--- single source of truth for forbidden-zone rules. Kept for callers that
--- already have line content + logo_end_line in hand.
---@param line string The line content (unused — guard reads buffer directly)
---@param line_num number The line number (1-indexed)
---@param logo_end_line number Unused — guard derives from section_ranges
---@param section_ranges table|nil Unused — guard reads vim.b[buf]
---@return boolean true if the line is actionable
function M.is_actionable_line(line, line_num, logo_end_line, section_ranges)
  local cursor_guard = require('nexus.cursor_guard')
  return not cursor_guard.is_forbidden_line(0, line_num)
end

--- Move cursor to the next actionable line in specified direction
---@param direction number 1 for forward, -1 for backward
---@param logo_end_line number The last line of the logo section
---@param section_ranges table|nil Section ranges for skipping non-actionable sections
function M.move_to_next_actionable(direction, logo_end_line, section_ranges)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local step = direction > 0 and 1 or -1

  -- If we're currently on a hidden line inside a fold, move to the visible fold line first
  local current_fold = vim.fn.foldclosed(current_line)
  if current_fold ~= -1 and current_fold ~= current_line then
    -- We're on a hidden line, move to the fold start (the visible line)
    current_line = current_fold
  end

  -- If we're currently on a fold line going forward, skip past it
  if direction > 0 and current_fold ~= -1 then
    local fold_end = vim.fn.foldclosedend(current_line)
    current_line = fold_end
  end

  -- Now search for next actionable line
  local i = current_line + step

  while (direction > 0 and i <= #lines) or (direction < 0 and i >= 1) do
    -- Check if this line is in a fold
    local fold_start = vim.fn.foldclosed(i)

    if fold_start ~= -1 then
      -- We hit a fold - the fold start line is the visible line representing the entire fold
      -- Treat this as a single actionable line and stop here
      vim.api.nvim_win_set_cursor(0, {fold_start, 0})
      return
    end

    -- Check if this line is actionable
    if lines[i] and M.is_actionable_line(lines[i], i, logo_end_line, section_ranges) then
      vim.api.nvim_win_set_cursor(0, {i, 0})
      return
    end

    i = i + step
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
  local current_section = get_current_section(current_line, section_ranges)

  -- Find previous section header
  for i = current_line - 1, 1, -1 do
    local line = lines[i]
    if line and line:match("^%s*[^%s].*:%s*$") then
      local section = get_current_section(i, section_ranges)
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
  local current_section = get_current_section(current_line, section_ranges)

  -- Find next section header
  for i = current_line + 1, #lines do
    local line = lines[i]
    if line and line:match("^%s*[^%s].*:%s*$") then
      local section = get_current_section(i, section_ranges)
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