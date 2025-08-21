local BaseAction = require('nexus.actions.base')
local logger = require('nexus.logger')

---@class LinearBrowseAction : BaseAction
local LinearBrowseAction = {}

function LinearBrowseAction.new()
  local instance = BaseAction:new({
    category = "linear",
    name = "linear.browse",
    description = "Open Linear issue in browser",
    can_undo = false
  })
  setmetatable(instance, { __index = LinearBrowseAction })
  return instance
end

---Execute browse action
---@param context table Action context with issue data
---@return boolean success
---@return string? error_message
function LinearBrowseAction:execute(context)
  logger.debug("LINEAR_ACTION", "Executing browse action", { context = context })
  
  if not context or not context.issue then
    return false, "No issue data provided"
  end
  
  local issue = context.issue
  if not issue.url then
    return false, "Issue URL not available"
  end
  
  -- Platform-specific URL opening
  local open_cmd
  if vim.fn.has('mac') == 1 then
    open_cmd = 'open'
  elseif vim.fn.has('unix') == 1 then
    open_cmd = 'xdg-open'
  elseif vim.fn.has('win32') == 1 then
    open_cmd = 'start'
  else
    return false, "Unsupported platform for opening URLs"
  end
  
  -- Execute command
  local result = vim.fn.system(string.format('%s "%s"', open_cmd, issue.url))
  local exit_code = vim.v.shell_error
  
  if exit_code == 0 then
    logger.info("LINEAR_ACTION", "Opened issue in browser", { 
      identifier = issue.identifier,
      url = issue.url 
    })
    vim.notify(string.format("Opened %s in browser", issue.identifier), vim.log.levels.INFO)
    return true
  else
    local error_msg = string.format("Failed to open browser: %s", result)
    logger.error("LINEAR_ACTION", error_msg, { exit_code = exit_code })
    return false, error_msg
  end
end

return LinearBrowseAction