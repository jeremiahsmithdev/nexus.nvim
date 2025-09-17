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
  
  -- Check if we're in a git repository and update state
  local git_state = require('nexus.state.git')
  git_state.force_refresh(config) -- Ensure git data is current
  local is_git_repo = git_state.is_git_repo()
  local files = cached_files or git_state.get_git_status()
  
  -- Get display width
  local width = layout.get_display_width()
  
  -- Build sections using component
  local sections = sections_component.build_sections(config, is_git_repo, files)
  
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
  local config_module = require('nexus.config')
  if config_module.is_section_enabled("keyboard_shortcuts") then
    events.setup_dynamic_shortcuts(buf, config, is_git_repo, section_ranges)
  end
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  return files, section_ranges
end


return M