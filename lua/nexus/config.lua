local M = {}

-- Default configuration
local default_config = {
  show_claude_conversations = false, -- Disabled by default
  show_dashboard_buttons = true,     -- Show dashboard-style buttons
  show_recent_commits = true,        -- Show git commits section
  recent_commits_count = 3,          -- Number of recent commits to show
  show_git_status = true,            -- Show git status section
  git_status_count = nil,            -- Limit git status files (nil = no limit)
  section_order = {                  -- Order of sections after logo
    "dashboard_buttons",
    "recent_commits", 
    "git_status",
    "claude_conversations"
  },
  logo_selection = "nexus",          -- Logo selection: "neovim", "nexus", or "image" (requires image.nvim plugin)
  logo_color = "String",             -- Highlight group for logo (default: String for green)
  image_logo_path = nil,             -- Custom image path (defaults to plugin's neovim.png if nil)
  image_logo_width = 30,             -- Width of the image in character units
  image_logo_height = 6              -- Height of the image in line units
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
        recent_commits = true,
        git_status = true,
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
  
  -- Handle backward compatibility for use_image_logo and validate logo_selection
  local valid_logo_types = {
    neovim = true,
    nexus = true,
    image = true
  }
  
  -- Handle backward compatibility: if use_image_logo exists, convert to logo_selection
  if config.use_image_logo ~= nil then
    logger.info("CONFIG", "Converting deprecated use_image_logo to logo_selection for backward compatibility")
    
    if type(config.use_image_logo) == "boolean" then
      if config.use_image_logo == true then
        config.logo_selection = "image"
      else
        config.logo_selection = "neovim"
      end
    elseif type(config.use_image_logo) == "string" and valid_logo_types[config.use_image_logo] then
      config.logo_selection = config.use_image_logo
    else
      logger.warn("CONFIG", "Invalid use_image_logo value, defaulting to 'nexus'", {
        provided_value = config.use_image_logo
      })
      config.logo_selection = "nexus"
    end
    
    -- Remove the old config key
    config.use_image_logo = nil
  end
  
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
end

function M.get()
  return config
end

return M