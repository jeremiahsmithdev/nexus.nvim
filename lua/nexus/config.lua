local M = {}

-- Default configuration
local default_config = {
  -- Startup behavior
  open_on_startup = true,            -- Open Nexus automatically on startup (when no files specified)
  keep_open_after_startup = false,   -- Keep Nexus buffer open after opening other files from dashboard
  
  -- Section visibility
  show_claude_conversations = false, -- Disabled by default
  show_dashboard_buttons = true,     -- Show dashboard-style buttons
  show_keyboard_shortcuts = true,    -- Show keyboard shortcuts section
  show_recent_commits = true,        -- Show git commits section
  recent_commits_count = 3,          -- Number of recent commits to show
  show_git_status = true,            -- Show git status section
  git_status_count = nil,            -- Limit git status files (nil = no limit)
  section_order = {                  -- Order of sections after logo
    "dashboard_buttons",
    "keyboard_shortcuts",
    "recent_commits", 
    "git_status",
    "linear_issues",
    "claude_conversations"
  },
  
  -- Logo configuration
  logo_selection = "nexus",          -- Logo selection: "neovim", "nexus", or "image" (requires image.nvim plugin)
  logo_color = "String",             -- Highlight group for logo (default: String for green)
  image_logo_path = nil,             -- Custom image path (defaults to plugin's neovim.png if nil)
  image_logo_width = 30,             -- Width of the image in character units
  image_logo_height = 6,             -- Height of the image in line units
  
  -- Linear integration
  linear = {
    enabled = false,                    -- Enable Linear integration
    api_key = vim.env.LINEAR_API_KEY,   -- Linear API key (prefer env var)
    team_id = nil,                      -- Default team ID for filtering issues
    max_issues = 10,                    -- Maximum issues to show in dashboard
    show_assignee = true,               -- Show assignee information
    show_priority = true,               -- Show priority indicators
    show_estimates = true,              -- Show story point estimates
    show_cycle = true,                  -- Show cycle/sprint information
    auto_refresh = 300,                 -- Auto-refresh interval in seconds (0 to disable)
    
    -- Cache settings
    cache = {
      issues_ttl = 300,                 -- Issues cache TTL (5 minutes)
      teams_ttl = 3600,                 -- Teams cache TTL (1 hour)  
      user_info_ttl = 3600,             -- User info cache TTL (1 hour)
    }
  }
}

local config = vim.deepcopy(default_config)

-- Setup function to allow user configuration
function M.setup(user_config)
  local logger = require('nexus.logger')
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
  
  -- Validate section_order
  if config.section_order ~= nil then
    if type(config.section_order) ~= "table" then
      logger.warn("CONFIG", "section_order must be a table, using default order", {
        provided_value = config.section_order,
        provided_type = type(config.section_order)
      })
      config.section_order = default_config.section_order
    else
      -- Validate that all sections are strings and known
      local known_sections = {
        dashboard_buttons = true,
        keyboard_shortcuts = true,
        recent_commits = true,
        git_status = true,
        linear_issues = true,
        claude_conversations = true
      }
      
      local valid_order = {}
      for i, section in ipairs(config.section_order) do
        if type(section) == "string" and known_sections[section] then
          table.insert(valid_order, section)
        else
          logger.warn("CONFIG", "Unknown section in section_order, skipping", {
            section = section,
            index = i,
            type = type(section)
          })
        end
      end
      
      if #valid_order == 0 then
        logger.warn("CONFIG", "No valid sections in section_order, using default")
        config.section_order = default_config.section_order
      else
        config.section_order = valid_order
      end
    end
  end
  
  -- Validate logo_selection
  local valid_logo_types = {
    neovim = true,
    nexus = true,
    image = true
  }
  
  -- Validate logo_selection
  if config.logo_selection ~= nil then
    if type(config.logo_selection) == "string" then
      if not valid_logo_types[config.logo_selection] then
        logger.warn("CONFIG", "Invalid logo_selection, using default 'nexus'", {
          provided_value = config.logo_selection,
          valid_options = {"neovim", "nexus", "image"}
        })
        config.logo_selection = "nexus"
      end
    else
      logger.warn("CONFIG", "logo_selection must be a string, using default 'nexus'", {
        provided_value = config.logo_selection,
        provided_type = type(config.logo_selection)
      })
      config.logo_selection = "nexus"
    end
  end
  
  -- Validate logo_color
  if config.logo_color ~= nil then
    if type(config.logo_color) ~= "string" then
      logger.warn("CONFIG", "logo_color must be a string, using default 'String'", {
        provided_value = config.logo_color,
        provided_type = type(config.logo_color)
      })
      config.logo_color = "String"
    elseif #config.logo_color == 0 then
      logger.warn("CONFIG", "logo_color cannot be empty, using default 'String'")
      config.logo_color = "String"
    end
  end
  
  -- Validate startup options
  if config.open_on_startup ~= nil then
    if type(config.open_on_startup) ~= "boolean" then
      logger.warn("CONFIG", "open_on_startup must be a boolean, using default true", {
        provided_value = config.open_on_startup,
        provided_type = type(config.open_on_startup)
      })
      config.open_on_startup = true
    end
  end
  
  if config.keep_open_after_startup ~= nil then
    if type(config.keep_open_after_startup) ~= "boolean" then
      logger.warn("CONFIG", "keep_open_after_startup must be a boolean, using default false", {
        provided_value = config.keep_open_after_startup,
        provided_type = type(config.keep_open_after_startup)
      })
      config.keep_open_after_startup = false
    end
  end
end

function M.get()
  return config
end

return M