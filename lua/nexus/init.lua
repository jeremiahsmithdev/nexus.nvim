local M = {}

-- Load modular components
local config = require('nexus.config')
local logger = require('nexus.logger')
local buffer_mod = require('nexus.buffer')
local render = require('nexus.render')
local keymaps = require('nexus.keymaps')
local logo = require('nexus.ui.logo')
local dashboard = require('nexus.ui.dashboard')
local global_keymaps = require('nexus.global_keymaps')

-- Setup function to allow user configuration
function M.setup(user_config)
  -- Initialize logger first
  logger.init()
  
  config.setup(user_config)
  
  -- Set up global keymaps for dashboard shortcuts
  global_keymaps.setup()
end

function M.open(is_manual_open)
  logger.info('NEXUS', 'Opening Nexus dashboard, manual=' .. tostring(is_manual_open))
  
  local buf = buffer_mod.create_nexus_buffer(is_manual_open)
  vim.api.nvim_buf_set_name(buf, 'Nexus')
  
  buffer_mod.open_buffer(buf, is_manual_open)
  
  -- NOW the buffer is in the window, so we can get the correct window width
  local current_config = config.get()
  local files, section_ranges = render.render_git_status(buf, current_config)
  
  local git_utils = require('nexus.git.utils')
  local is_git_repo = git_utils.is_git_repo()
  
  keymaps.setup_keymaps(buf, files, current_config, is_git_repo, function(buf, cached_files)
    render.render_git_status(buf, current_config, cached_files)
  end, section_ranges)
  
  -- Position cursor on first actionable line (dashboard buttons)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local logo_lines = logo.get_neovim_logo(current_config)
  local logo_end_line = #logo_lines  -- Logo only
  
  -- Find first actionable line (should be first dashboard button)
  for i = logo_end_line + 1, #lines do
    if lines[i] then
      -- Skip keyboard shortcuts section
      if section_ranges and section_ranges.keyboard_shortcuts then
        local shortcuts_range = section_ranges.keyboard_shortcuts
        if i >= shortcuts_range.start_line and i <= shortcuts_range.end_line then
          goto continue
        end
      end
      
      -- Skip empty lines
      if lines[i]:match("^%s*$") then
        goto continue
      end
      
      -- Skip section titles (lines ending with colon)
      if lines[i]:match(":$") then
        goto continue
      end
      
      -- This is an actionable line
      vim.api.nvim_win_set_cursor(0, {i, 0})
      break
    end
    ::continue::
  end
end

-- Function to refresh an existing Nexus buffer
function M.refresh_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  -- Check if this is actually a Nexus buffer
  local buf_name = vim.api.nvim_buf_get_name(buf)
  if not buf_name:match('Nexus$') then
    return
  end
  
  local current_config = config.get()
  local files, section_ranges = render.render_git_status(buf, current_config)
  
  local git_utils = require('nexus.git.utils')
  local is_git_repo = git_utils.is_git_repo()
  
  keymaps.setup_keymaps(buf, files, current_config, is_git_repo, function(buf, cached_files)
    render.render_git_status(buf, current_config, cached_files)
  end, section_ranges)
end

return M