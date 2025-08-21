local BaseAction = require('nexus.actions.base')
local logger = require('nexus.logger')

---@class LinearRefreshAction : BaseAction
local LinearRefreshAction = {}

function LinearRefreshAction.new()
  local instance = BaseAction:new({
    category = "linear",
    name = "linear.refresh",
    description = "Refresh Linear issues from API",
    can_undo = false
  })
  setmetatable(instance, { __index = LinearRefreshAction })
  return instance
end

---Execute refresh action
---@param context table Action context with config and refresh callback
---@return boolean success
---@return string? error_message
function LinearRefreshAction:execute(context)
  logger.debug("LINEAR_ACTION", "Executing refresh action", { context = context })
  
  if not context or not context.config then
    return false, "No config provided"
  end
  
  local config = context.config
  if not config.linear or not config.linear.enabled then
    return false, "Linear integration is not enabled"
  end
  
  logger.info("LINEAR_ACTION", "Refreshing Linear issues")
  vim.notify("Refreshing Linear issues...", vim.log.levels.INFO)
  
  local linear_state = require('nexus.state.linear')
  linear_state.refresh_data(config)
  
  -- Call refresh callback if provided
  if context.refresh_callback then
    context.refresh_callback()
  end
  
  return true, "Linear issues refreshed"
end

return LinearRefreshAction