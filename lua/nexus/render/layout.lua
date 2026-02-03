local M = {}

local center = require('nexus.ui.center')
local logo = require('nexus.ui.logo')

-- Get the actual display width with tmux pane awareness
function M.get_display_width()
  local width = vim.fn.winwidth(0)

  -- If we're in tmux, get the actual pane width for more accurate centering
  if vim.env.TMUX then
    local pane_width = vim.fn.system("tmux display-message -p '#{pane_width}' 2>/dev/null"):gsub('\n', '')
    local tmux_width = tonumber(pane_width)
    if tmux_width and tmux_width > 0 then
      width = tmux_width
    end
  end

  return width
end

-- Layout sections with proper alignment
function M.layout_sections(sections, config, width)
  local lines = {}
  local section_ranges = {}
  
  -- Start with centered logo
  local logo_lines = logo.get_neovim_logo(config)
  local centered_logo = center.center_lines(logo_lines, width)
  
  -- Add centered logo lines to buffer
  for _, line in ipairs(centered_logo) do
    table.insert(lines, line)
  end
  
  -- Store logo section info for highlighting
  local logo_section = {
    start_line = 1,
    end_line = #centered_logo
  }
  
  -- Separate different section types for different alignment
  local button_sections = {}
  local git_sections_data = {}
  local project_name_section = nil

  for _, section_name in ipairs(config.section_order) do
    local section_data = sections[section_name]
    if section_data and #section_data > 0 then
      if section_name == "project_name" then
        project_name_section = section_data
      elseif section_name == "dashboard_buttons" or section_name == "keyboard_shortcuts" then
        table.insert(button_sections, {data = section_data, name = section_name})
      else
        table.insert(git_sections_data, {data = section_data, name = section_name})
      end
    end
  end
  
  -- Add button sections with center alignment
  for i, section_info in ipairs(button_sections) do
    -- Add spacing before section (except first section)
    if i > 1 or #lines > #logo_lines then
      table.insert(lines, "")
    end
    
    local centered_section
    if section_info.name == "keyboard_shortcuts" then
      -- Use individual centering for keyboard shortcuts (each line centered independently)
      centered_section = center.center_lines_individually(section_info.data, width)
    else
      -- Use block centering for other sections (like dashboard buttons)
      centered_section = center.center_lines(section_info.data, width)
    end
    
    local section_start = #lines + 1
    for _, line in ipairs(centered_section) do
      table.insert(lines, line)
    end
    local section_end = #lines
    
    -- Store section ranges for navigation
    section_ranges[section_info.name] = {
      start_line = section_start,
      end_line = section_end
    }
  end
  
  -- Find the longest line across all git sections to calculate common alignment
  local max_git_line_length = 0
  for _, section_info in ipairs(git_sections_data) do
    local section_max = center.longest_line(section_info.data)
    max_git_line_length = math.max(max_git_line_length, section_max)
  end
  
  -- Apply same left padding to all git sections
  if max_git_line_length > 0 then
    local left_padding = math.max(0, math.floor((width - max_git_line_length) / 2))
    local padding_str = string.rep(" ", left_padding)

    for i, section_info in ipairs(git_sections_data) do
      -- Add spacing before section (except first git section if no button sections exist)
      if i > 1 or #button_sections > 0 or #lines > #logo_lines then
        table.insert(lines, "")
      end

      local section_start = #lines + 1
      for _, line in ipairs(section_info.data) do
        table.insert(lines, padding_str .. line)
      end
      local section_end = #lines

      -- Store section ranges for navigation and folding
      section_ranges[section_info.name] = {
        start_line = section_start,
        end_line = section_end
      }
    end
  end
  
  return lines, section_ranges, logo_section
end

return M