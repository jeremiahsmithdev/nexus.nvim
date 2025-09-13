local M = {}

-- Component imports
local layout = require('nexus.render.layout')
local sections_component = require('nexus.render.components.sections')
local highlighting = require('nexus.render.components.highlighting')
local events = require('nexus.render.components.events')

-- State management imports
local git_state = require('nexus.state.git')
local ui_state = require('nexus.state.ui')

-- Legacy imports still needed
local logo = require('nexus.ui.logo')

function M.render_git_status(buf, config, cached_files)
  -- Update configuration in state
  ui_state.update_config(config or {})
  
  -- Check if we're in a git repository and update state using BATCH operations (PERFORMANCE OPTIMIZATION)
  local git_state = require('nexus.state.git')
  local files, commits = git_state.update_git_data_batch(config, true) -- Use batch operations
  local is_git_repo = git_state.is_git_repo()
  files = cached_files or files
  
  -- Get display width
  local width = layout.get_display_width()
  
  -- Build sections using component (pass commits data from batch operation)
  local sections = sections_component.build_sections(config, is_git_repo, files, commits)
  
  -- Layout sections using component
  local lines, section_ranges, logo_section = layout.layout_sections(sections, config, width)
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Render image logo if enabled (after buffer content is set)
  if config.logo_selection == "image" then
    logo.render_image_logo(buf, config, 0, 0)
  end
  
  -- Set up folding for git status overflow
  sections_component.setup_folding(buf, lines, config, files)
  
  -- Update state with section ranges and logo info
  ui_state.update_section_ranges(section_ranges)
  ui_state.update_logo_section(logo_section)
  
  -- Add syntax highlighting using component
  highlighting.apply_highlighting(buf, lines, config, is_git_repo, files, logo_section, section_ranges)
  
  -- Update UI state with section ranges for dynamic shortcuts
  ui_state.update_section_ranges(section_ranges)
  
  -- Set up dynamic shortcut updating on cursor movement (only if shortcuts are enabled)
  if config.show_keyboard_shortcuts then
    events.setup_dynamic_shortcuts(buf, config, is_git_repo, section_ranges)
  end
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  return files, section_ranges
end


return M