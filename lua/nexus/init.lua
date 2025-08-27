local M = {}

-- Load critical components immediately
local config = require('nexus.config')
local logger = require('nexus.logger')
local buffer_mod = require('nexus.buffer')

-- Setup function to allow user configuration
function M.setup(user_config)
  -- Initialize essential components only
  logger.init()
  config.setup(user_config)
  
  -- Defer non-critical initialization
  vim.defer_fn(function()
    -- Initialize state management
    local git_state = require('nexus.state.git')
    git_state.init()
    
    local linear_state = require('nexus.state.linear')
    linear_state.init()
    
    local todo_state = require('nexus.state.todo')
    todo_state.init()
    
    -- Initialize action system  
    local actions = require('nexus.actions')
    actions.init()
    
    -- Set up global keymaps for dashboard shortcuts
    local global_keymaps = require('nexus.global_keymaps')
    global_keymaps.setup()
  end, 0)
end

function M.open(is_manual_open)
  -- Check if Nexus buffer already exists and is loaded
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match('Nexus$') then
        -- Found existing loaded Nexus buffer, just switch to it
        logger.info('NEXUS', 'Switching to existing Nexus buffer')
        buffer_mod.open_buffer(buf, is_manual_open)
        return
      end
    end
  end
  
  -- Lazy-load actions system if needed
  local actions = require('nexus.actions')
  if vim.tbl_isempty(actions.list_actions()) then
    actions.init()
  end
  
  logger.info('NEXUS', 'Opening new Nexus dashboard, manual=' .. tostring(is_manual_open))
  
  -- Check if we should treat auto-open as persistent due to keep_open_after_startup
  local current_config = config.get()
  local should_be_persistent = is_manual_open or current_config.keep_open_after_startup
  
  local buf = buffer_mod.create_nexus_buffer(should_be_persistent)
  vim.api.nvim_buf_set_name(buf, 'Nexus')
  
  buffer_mod.open_buffer(buf, is_manual_open)
  
  -- Lazy-load render system
  local render = require('nexus.render')
  local files, section_ranges = render.render_git_status(buf, current_config)
  
  local git_state = require('nexus.state.git')
  local is_git_repo = git_state.is_git_repo()
  
  -- Lazy-load keymaps system
  local keymaps = require('nexus.keymaps')
  keymaps.setup_keymaps(buf, files, current_config, is_git_repo, function(buf, cached_files)
    render.render_git_status(buf, current_config, cached_files)
  end, section_ranges)
  
  -- Position cursor on first actionable line (dashboard buttons)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local logo = require('nexus.ui.logo')
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
  local render = require('nexus.render')
  local files, section_ranges = render.render_git_status(buf, current_config)
  
  local git_state = require('nexus.state.git')
  local is_git_repo = git_state.is_git_repo()
  
  local keymaps = require('nexus.keymaps')
  keymaps.setup_keymaps(buf, files, current_config, is_git_repo, function(buf, cached_files)
    render.render_git_status(buf, current_config, cached_files)
  end, section_ranges)
end

return M