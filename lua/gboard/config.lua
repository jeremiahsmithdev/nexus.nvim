local M = {}

-- Default configuration
local default_config = {
  show_claude_conversations = false, -- Disabled by default
  show_dashboard_buttons = true,     -- Show dashboard-style buttons
  show_recent_commits = true,        -- Show git commits section
  recent_commits_count = 3,          -- Number of recent commits to show
  show_git_status = true,            -- Show git status section
  git_status_count = nil,            -- Limit git status files (nil = no limit)
  use_image_logo = false,            -- Use image.nvim for logo (requires image.nvim plugin)
  image_logo_path = nil,             -- Custom image path (defaults to plugin's neovim.png if nil)
  image_logo_width = 30,             -- Width of the image in character units
  image_logo_height = 6              -- Height of the image in line units
}

local config = vim.deepcopy(default_config)

-- Setup function to allow user configuration
function M.setup(user_config)
  local logger = require('gboard.logger')
  config = vim.tbl_deep_extend('force', default_config, user_config or {})
  
  -- Validate git_status_count
  if config.git_status_count ~= nil then
    if type(config.git_status_count) ~= "number" then
      logger.warn("CONFIG", "git_status_count must be a number, using no limit", {
        provided_value = config.git_status_count,
        provided_type = type(config.git_status_count)
      })
      config.git_status_count = nil
    elseif config.git_status_count < 1 then
      logger.warn("CONFIG", "git_status_count must be >= 1, using no limit", {
        provided_value = config.git_status_count
      })
      config.git_status_count = nil
    elseif config.git_status_count ~= math.floor(config.git_status_count) then
      logger.warn("CONFIG", "git_status_count should be an integer, rounding down", {
        provided_value = config.git_status_count,
        rounded_value = math.floor(config.git_status_count)
      })
      config.git_status_count = math.floor(config.git_status_count)
    end
  end
end

function M.get()
  return config
end

return M