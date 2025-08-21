local Action = require('nexus.actions.base')
local state = require('nexus.state')
local logger = require('nexus.logger')

---@class RefreshAction : Action
local RefreshAction = {}
RefreshAction.__index = RefreshAction
setmetatable(RefreshAction, { __index = Action })

function RefreshAction:new()
  local instance = Action:new({
    name = "navigation.refresh",
    description = "Refresh the dashboard content",
    category = "navigation",
    can_undo = false -- Refresh operations don't need undo
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate refresh arguments
---@param args table Action arguments (optional)
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function RefreshAction:validate(args)
  -- Refresh action accepts any arguments or none
  if args and args.sections then
    if type(args.sections) ~= "table" then
      return false, "sections must be a table"
    end
    
    -- Validate section names
    local valid_sections = { 'git_status', 'git_commits', 'providers', 'all' }
    for _, section in ipairs(args.sections) do
      if type(section) ~= "string" then
        return false, "section names must be strings"
      end
      
      local valid = false
      for _, valid_section in ipairs(valid_sections) do
        if section == valid_section then
          valid = true
          break
        end
      end
      
      if not valid then
        return false, string.format("invalid section: %s (valid: %s)", 
          section, table.concat(valid_sections, ', '))
      end
    end
  end
  
  return true, nil
end

---Execute refresh action
---@param args table Action arguments (optional 'force', 'sections', 'callback')
---@return boolean success Whether execution succeeded
function RefreshAction:_execute(args)
  args = args or {}
  
  -- Store context
  self.context.force = args.force or false
  self.context.sections = args.sections or nil
  self.context.callback = args.callback
  
  local success = true
  local refreshed_sections = {}
  
  if args.sections then
    -- Refresh specific sections
    for _, section in ipairs(args.sections) do
      if section == 'git_status' then
        state:notify_observers('git_status_changed', { force = args.force })
        table.insert(refreshed_sections, 'git_status')
      elseif section == 'git_commits' then
        state:notify_observers('git_commits_changed', { force = args.force })
        table.insert(refreshed_sections, 'git_commits')
      elseif section == 'providers' then
        state:notify_observers('providers_changed', { force = args.force })
        table.insert(refreshed_sections, 'providers')
      elseif section == 'all' then
        -- Refresh everything
        state:notify_observers('git_status_changed', { force = args.force })
        state:notify_observers('git_commits_changed', { force = args.force })
        state:notify_observers('providers_changed', { force = args.force })
        state:notify_observers('ui_refresh_requested', { force = args.force })
        refreshed_sections = { 'all' }
        break
      else
        logger.warn('REFRESH_ACTION', string.format('Unknown section for refresh: %s', section))
        success = false
      end
    end
  else
    -- Full refresh - notify all relevant observers
    state:notify_observers('git_status_changed', { force = args.force })
    state:notify_observers('git_commits_changed', { force = args.force })
    state:notify_observers('providers_changed', { force = args.force })
    state:notify_observers('ui_refresh_requested', { force = args.force })
    refreshed_sections = { 'all' }
  end
  
  -- Execute callback if provided
  if args.callback and type(args.callback) == "function" then
    local cb_success, cb_error = pcall(args.callback, refreshed_sections)
    if not cb_success then
      logger.error('REFRESH_ACTION', string.format('Refresh callback failed: %s', cb_error))
      success = false
    end
  end
  
  if success then
    local scope = #refreshed_sections > 0 and table.concat(refreshed_sections, ', ') or 'none'
    logger.info('REFRESH_ACTION', string.format('Successfully refreshed: %s', scope))
  else
    logger.error('REFRESH_ACTION', 'Failed to refresh dashboard')
  end
  
  return success
end

return RefreshAction