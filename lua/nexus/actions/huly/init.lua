--- DORMANT MODULE: Huly integration is currently disabled.
--- Provider implementation is broken (assumes GraphQL; Huly uses WebSocket via Node client).
--- Awaiting Node bridge implementation. See HULY_INTEGRATION_STATUS.md.
---@module nexus.actions.huly
local M = {}

local huly_state = require('nexus.state.huly')
local logger = require('nexus.logger')

-- Action classes for Huly operations

---@class HulyAction
---@field name string Action name
---@field description string Action description
local HulyAction = {}
HulyAction.__index = HulyAction

---Create new Huly action
---@param name string
---@param description string
---@return HulyAction
function HulyAction:new(name, description)
  local instance = setmetatable({}, self)
  instance.name = name
  instance.description = description
  return instance
end

---Execute the action
---@param context table Action context
---@return boolean success
---@return string|nil error_message
function HulyAction:execute(context)
  error("HulyAction:execute() must be implemented by subclass")
end

---@class HulyBrowseAction : HulyAction
local BrowseAction = setmetatable({}, { __index = HulyAction })

---Create browse action
---@return HulyBrowseAction
function BrowseAction:new()
  local instance = setmetatable({}, self)
  instance.name = "huly.browse"
  instance.description = "Browse Huly issue in browser"
  return instance
end

---Execute browse action
---@param context table Action context
---@return boolean success
---@return string|nil error_message
function BrowseAction:execute(context)
  local issue_identifier = context.issue_identifier
  if not issue_identifier then
    return false, "No issue identifier provided"
  end

  logger.info('HULY', 'Browse action executing', { identifier = issue_identifier })

  -- Get issue data to construct URL
  local issues = huly_state.get_issues()
  local target_issue = nil

  for _, issue in ipairs(issues) do
    if issue.identifier == issue_identifier then
      target_issue = issue
      break
    end
  end

  if not target_issue then
    return false, "Issue not found: " .. issue_identifier
  end

  -- Construct URL (example structure - may need adjustment)
  local url = nil
  if target_issue.workspace and target_issue.identifier then
    url = string.format("https://huly.app/workspace/%s/tracker/issue/%s",
      target_issue.workspace.name or "default", target_issue.identifier)
  end

  if url then
    vim.ui.open(url)
    logger.info('HULY', 'Opened issue in browser', { url = url })
    return true
  else
    return false, "Could not construct URL for issue"
  end
end

---@class HulyRefreshAction : HulyAction
local RefreshAction = setmetatable({}, { __index = HulyAction })

---Create refresh action
---@return HulyRefreshAction
function RefreshAction:new()
  local instance = setmetatable({}, self)
  instance.name = "huly.refresh"
  instance.description = "Refresh Huly issues"
  return instance
end

---Execute refresh action
---@param context table Action context
---@return boolean success
---@return string|nil error_message
function RefreshAction:execute(context)
  local config = context.config
  local callback = context.callback

  if not config then
    return false, "No configuration provided"
  end

  logger.info('HULY', 'Refresh action executing')

  huly_state.refresh_data(config, function(success, error)
    if success then
      logger.info('HULY', 'Refresh completed successfully')
    else
      logger.error('HULY', 'Refresh failed', { error = error })
    end

    if callback then
      callback(success, error)
    end
  end)

  -- Return immediately since refresh is async
  return true
end

---@class HulyCreateAction : HulyAction
local CreateAction = setmetatable({}, { __index = HulyAction })

---Create create action
---@return HulyCreateAction
function CreateAction:new()
  local instance = setmetatable({}, self)
  instance.name = "huly.create"
  instance.description = "Create new Huly issue"
  return instance
end

---Execute create action
---@param context table Action context
---@return boolean success
---@return string|nil error_message
function CreateAction:execute(context)
  local config = context.config
  local issue_data = context.issue_data
  local callback = context.callback

  if not config then
    return false, "No configuration provided"
  end

  if not issue_data or not issue_data.title then
    return false, "Issue title is required"
  end

  logger.info('HULY', 'Create action executing', { title = issue_data.title })

  huly_state.create_issue(issue_data, function(issue, error)
    if error then
      logger.error('HULY', 'Create failed', { error = error })
    else
      logger.info('HULY', 'Issue created successfully', {
        id = issue.id,
        identifier = issue.identifier
      })
    end

    if callback then
      callback(issue, error)
    end
  end)

  -- Return immediately since creation is async
  return true
end

---@class HulyUpdateAction : HulyAction
local UpdateAction = setmetatable({}, { __index = HulyAction })

---Create update action
---@return HulyUpdateAction
function UpdateAction:new()
  local instance = setmetatable({}, self)
  instance.name = "huly.update"
  instance.description = "Update Huly issue"
  return instance
end

---Execute update action
---@param context table Action context
---@return boolean success
---@return string|nil error_message
function UpdateAction:execute(context)
  local config = context.config
  local issue_id = context.issue_id
  local update_data = context.update_data
  local callback = context.callback

  if not config then
    return false, "No configuration provided"
  end

  if not issue_id then
    return false, "Issue ID is required"
  end

  if not update_data or vim.tbl_isempty(update_data) then
    return false, "No update data provided"
  end

  logger.info('HULY', 'Update action executing', { id = issue_id, data = update_data })

  huly_state.update_issue(issue_id, update_data, function(issue, error)
    if error then
      logger.error('HULY', 'Update failed', { error = error })
    else
      logger.info('HULY', 'Issue updated successfully', {
        id = issue.id,
        identifier = issue.identifier
      })
    end

    if callback then
      callback(issue, error)
    end
  end)

  -- Return immediately since update is async
  return true
end

---Create action by name
---@param action_name string
---@return HulyAction|nil
function M.create_action(action_name)
  if action_name == "huly.browse" then
    return BrowseAction:new()
  elseif action_name == "huly.refresh" then
    return RefreshAction:new()
  elseif action_name == "huly.create" then
    return CreateAction:new()
  elseif action_name == "huly.update" then
    return UpdateAction:new()
  else
    logger.warn('HULY', 'Unknown action name', { action = action_name })
    return nil
  end
end

---Get all available Huly actions
---@return HulyAction[]
function M.get_all_actions()
  return {
    BrowseAction:new(),
    RefreshAction:new(),
    CreateAction:new(),
    UpdateAction:new()
  }
end

---Execute action by name
---@param action_name string
---@param context table Action context
---@return boolean success
---@return string|nil error_message
function M.execute_action(action_name, context)
  local action = M.create_action(action_name)
  if not action then
    return false, "Unknown action: " .. action_name
  end

  return action:execute(context)
end

return M