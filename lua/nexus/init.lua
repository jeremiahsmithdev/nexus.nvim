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
  local files = render.render_git_status(buf, current_config)
  
  local git_utils = require('nexus.git.utils')
  local is_git_repo = git_utils.is_git_repo()
  
  keymaps.setup_keymaps(buf, files, current_config, is_git_repo, function(buf, cached_files)
    render.render_git_status(buf, current_config, cached_files)
  end)
  
  -- Position cursor after logo and buttons, before commits/git status
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local logo_lines = logo.get_neovim_logo(current_config)
  local button_lines = dashboard.get_dashboard_buttons(current_config)
  local cursor_line = math.min(#logo_lines + #button_lines + 3, #lines)
  if cursor_line > 0 and cursor_line <= #lines then
    vim.api.nvim_win_set_cursor(0, {cursor_line, 0})
  end
end

return M