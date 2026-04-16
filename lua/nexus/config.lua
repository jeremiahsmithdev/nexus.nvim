local M = {}

-- Load persisted config from .nexus/config.lua if it exists
local function load_persisted_config()
  local git_root = require('nexus.git.root').get()
  if not git_root then
    return nil
  end
  local config_path = git_root .. "/.nexus/config.lua"
  if vim.fn.filereadable(config_path) == 0 then
    return nil
  end
  local ok, loaded = pcall(dofile, config_path)
  if ok and type(loaded) == "table" then
    return loaded
  end
  return nil
end

-- Default configuration
local default_config = {
  -- Startup behavior
  open_on_startup = true,            -- Open Nexus automatically on startup (when no files specified)
  keep_open_after_startup = false,   -- Keep Nexus buffer open after opening other files from dashboard
  
  -- Section configuration (sections are enabled by being in section_order)
  recent_commits_count = 3,          -- Number of recent commits to show
  show_commit_review = true,         -- Show commit review status indicators
  git_status_count = nil,            -- Limit git status files (nil = no limit)
  max_todos = 10,                    -- Maximum todos to show (nil = no limit)
  section_order = {                  -- Order of sections after logo (only sections in this list are enabled)
    "dashboard_buttons",
    "keyboard_shortcuts",
    "todos",
    "recent_commits",
    "git_status",
    -- "linear_issues",  -- Disabled by default; enable with linear.enabled = true
    -- "huly_issues",    -- Disabled by default; enable with huly.enabled = true
  },
  
  -- Logo configuration
  logo_selection = "nexus",          -- Logo selection: "neovim", "nexus", "project", or "image" (requires image.nvim plugin)
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
    auto_refresh = 0,                 -- Auto-refresh interval in seconds (0 to disable)
    filter_by_repository = true,        -- Filter issues by current git repository project

    -- Issue ordering and filtering
    issue_order = nil,                  -- Status-based ordering: {"Todo", "In Progress", "Done"} or nil for all

    -- Cache settings
    cache = {
      issues_ttl = 300,                 -- Issues cache TTL (5 minutes)
      teams_ttl = 3600,                 -- Teams cache TTL (1 hour)
      user_info_ttl = 3600,             -- User info cache TTL (1 hour)
    }
  },

  -- Huly integration (requires huly-bridge server: scripts/huly-bridge/)
  huly = {
    enabled = false,                    -- Enable Huly integration
    bridge_url = "http://localhost:8088",  -- Huly bridge server URL
    token = vim.env.HULY_TOKEN,         -- Huly API token (JWT from workspace settings)
    workspace = vim.env.HULY_WORKSPACE, -- Workspace name (required, no default)
    max_issues = 10,                    -- Maximum issues to show in dashboard
    show_assignee = true,               -- Show assignee information
    show_priority = true,               -- Show priority indicators
    show_project = true,                -- Show project information
    auto_refresh = 0,                   -- Auto-refresh interval in seconds (0 to disable)

    -- Issue ordering and filtering
    issue_order = nil,                  -- Status-based ordering: {"todo", "in progress", "done"} or nil for all

    -- Cache settings
    cache = {
      issues_ttl = 300,                 -- Issues cache TTL (5 minutes)
      workspaces_ttl = 3600,            -- Workspaces cache TTL (1 hour)
      projects_ttl = 3600,              -- Projects cache TTL (1 hour)
      provider_ttl = 1800               -- Provider instance cache TTL (30 minutes)
    }
  },

  -- Beads integration (local git-backed issue tracker)
  beads = {
    cli = "br",                         -- CLI binary: "br" (beads_rust) or "bd" (beads)
    enabled = false,                    -- Enable Beads integration
    max_issues = 10,                    -- Maximum issues to show in dashboard
    show_priority = true,               -- Show priority indicators (P0-P4)
    show_status = true,                 -- Show status in parentheses
    show_blocked_by = true,             -- Show blocker information for blocked issues
    filter = "ready",                   -- Issue filter: "ready" (unblocked), "all", "in_progress"

    -- Cache settings
    cache = {
      issues_ttl = 60                   -- Issues cache TTL (1 minute - beads is local)
    }
  }
}

local config = vim.deepcopy(default_config)

-- Setup function to allow user configuration
function M.setup(user_config)
  local logger = require('nexus.logger')

  -- Load persisted config from .nexus/config.lua (project-local settings)
  local persisted_config = load_persisted_config()

  -- Merge order: default < user < persisted (project config has highest priority)
  config = vim.tbl_deep_extend('force', default_config, user_config or {}, persisted_config or {})
  
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
        todos = true,
        recent_commits = true,
        git_status = true,
        linear_issues = true,
        huly_issues = true,
        beads_issues = true,
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
    project = true,
    image = true
  }
  
  -- Validate logo_selection
  if config.logo_selection ~= nil then
    if type(config.logo_selection) == "string" then
      if not valid_logo_types[config.logo_selection] then
        logger.warn("CONFIG", "Invalid logo_selection, using default 'nexus'", {
          provided_value = config.logo_selection,
          valid_options = {"neovim", "nexus", "project", "image"}
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
  
  -- Validate Linear configuration
  if config.linear and config.linear.issue_order ~= nil then
    if type(config.linear.issue_order) ~= "table" then
      logger.warn("CONFIG", "linear.issue_order must be a table, disabling filtering", {
        provided_value = config.linear.issue_order,
        provided_type = type(config.linear.issue_order)
      })
      config.linear.issue_order = nil
    elseif #config.linear.issue_order == 0 then
      logger.warn("CONFIG", "linear.issue_order is empty, disabling filtering")
      config.linear.issue_order = nil
    else
      -- Validate that all items are strings
      local valid_order = {}
      for i, status in ipairs(config.linear.issue_order) do
        if type(status) == "string" and #status > 0 then
          table.insert(valid_order, status)
        else
          logger.warn("CONFIG", "Invalid status in linear.issue_order, skipping", {
            status = status,
            index = i,
            type = type(status)
          })
        end
      end

      if #valid_order == 0 then
        logger.warn("CONFIG", "No valid statuses in linear.issue_order, disabling filtering")
        config.linear.issue_order = nil
      else
        config.linear.issue_order = valid_order
      end
    end
  end

  -- Validate Huly configuration
  if config.huly and config.huly.issue_order ~= nil then
    if type(config.huly.issue_order) ~= "table" then
      logger.warn("CONFIG", "huly.issue_order must be a table, disabling filtering", {
        provided_value = config.huly.issue_order,
        provided_type = type(config.huly.issue_order)
      })
      config.huly.issue_order = nil
    elseif #config.huly.issue_order == 0 then
      logger.warn("CONFIG", "huly.issue_order is empty, disabling filtering")
      config.huly.issue_order = nil
    else
      -- Validate that all items are strings
      local valid_order = {}
      for i, status in ipairs(config.huly.issue_order) do
        if type(status) == "string" and #status > 0 then
          table.insert(valid_order, status)
        else
          logger.warn("CONFIG", "Invalid status in huly.issue_order, skipping", {
            status = status,
            index = i,
            type = type(status)
          })
        end
      end

      if #valid_order == 0 then
        logger.warn("CONFIG", "No valid statuses in huly.issue_order, disabling filtering")
        config.huly.issue_order = nil
      else
        config.huly.issue_order = valid_order
      end
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

-- Check if a section is enabled (based on being in section_order)
function M.is_section_enabled(section_name)
  if not config.section_order then
    return false
  end

  for _, section in ipairs(config.section_order) do
    if section == section_name then
      return true
    end
  end

  return false
end

-- Get the order index of a section (for sorting)
function M.get_section_order_index(section_name)
  if not config.section_order then
    return 999  -- Put at end if no order defined
  end

  for i, section in ipairs(config.section_order) do
    if section == section_name then
      return i
    end
  end

  return 999  -- Put at end if not in order
end

return M
