local M = {}

-- Default configuration
local default_config = {
  show_claude_conversations = false, -- Disabled by default
  show_dashboard_buttons = true,     -- Show dashboard-style buttons
  show_recent_commits = true,        -- Show git commits section
  recent_commits_count = 3,          -- Number of recent commits to show
  show_git_status = true             -- Show git status section
}

local config = vim.deepcopy(default_config)

-- Setup function to allow user configuration
function M.setup(user_config)
  config = vim.tbl_deep_extend('force', default_config, user_config or {})
end

function M.get()
  return config
end

return M