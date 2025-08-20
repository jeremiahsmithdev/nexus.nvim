local Command = require('nexus.commands.base')
local state = require('nexus.state')
local logger = require('nexus.logger')

---@class RefreshCommand : Command
local RefreshCommand = {}
RefreshCommand.__index = RefreshCommand
setmetatable(RefreshCommand, { __index = Command })

function RefreshCommand:new()
  local instance = Command:new({
    name = "ui.refresh",
    description = "Refresh the dashboard content",
    can_undo = false -- Refresh operations don't need undo
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate refresh arguments
---@param args table Command arguments (optional)
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function RefreshCommand:validate(args)
  -- Refresh command accepts any arguments or none
  return true, nil
end

---Execute refresh command
---@param args table Command arguments (optional 'force' and 'sections')
---@return boolean success Whether execution succeeded
function RefreshCommand:_execute(args)
  args = args or {}
  
  -- Store context
  self.context.force = args.force or false
  self.context.sections = args.sections or nil
  
  local success = true
  
  if args.sections then
    -- Refresh specific sections
    for _, section in ipairs(args.sections) do
      if section == 'git_status' then
        state:notify_observers('git_status_changed', {})
      elseif section == 'git_commits' then
        state:notify_observers('git_commits_changed', {})
      elseif section == 'providers' then
        state:notify_observers('providers_changed', {})
      else
        logger.warn('REFRESH_CMD', string.format('Unknown section for refresh: %s', section))
      end
    end
  else
    -- Full refresh - notify all relevant observers
    state:notify_observers('git_status_changed', {})
    state:notify_observers('git_commits_changed', {})
    state:notify_observers('providers_changed', {})
    state:notify_observers('ui_refresh_requested', { force = args.force })
  end
  
  if success then
    local scope = args.sections and table.concat(args.sections, ', ') or 'all'
    logger.info('REFRESH_CMD', string.format('Successfully refreshed: %s', scope))
  else
    logger.error('REFRESH_CMD', 'Failed to refresh dashboard')
  end
  
  return success
end

return RefreshCommand