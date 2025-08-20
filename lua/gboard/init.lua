local M = {}

-- Load modular components
local config = require('gboard.config')
local logger = require('gboard.logger')
local buffer_mod = require('gboard.buffer')
local render = require('gboard.render')
local keymaps = require('gboard.keymaps')
local logo = require('gboard.ui.logo')
local dashboard = require('gboard.ui.dashboard')
local global_keymaps = require('gboard.global_keymaps')

-- Setup function to allow user configuration
function M.setup(user_config)
  -- Initialize logger first
  logger.init()
  
  config.setup(user_config)
  
  -- Set up global keymaps for dashboard shortcuts
  global_keymaps.setup()
end

function M.open(is_manual_open)
  logger.info('GBOARD', 'Opening GBoard dashboard, manual=' .. tostring(is_manual_open))
  
  local buf = buffer_mod.create_gboard_buffer(is_manual_open)
  vim.api.nvim_buf_set_name(buf, 'GBoard')
  
  buffer_mod.open_buffer(buf, is_manual_open)
  
  -- NOW the buffer is in the window, so we can get the correct window width
  local current_config = config.get()
  local files = render.render_git_status(buf, current_config)
  
  local git_utils = require('gboard.git.utils')
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