---@module nexus.actions
---Action registry and dispatcher for the action pattern implementation

local logger = require('nexus.logger')

-- Action registry
local M = {
  actions = {},
  history = {},
  history_index = 0,
  max_history = 50,
  categories = {}
}

---Register an action
---@param action Action The action to register
---@return boolean success Whether registration succeeded
function M.register(action)
  if not action or not action.name then
    logger.error('ACTION_REGISTRY', 'Cannot register action without name')
    return false
  end
  
  if M.actions[action.name] then
    logger.warn('ACTION_REGISTRY', string.format('Overriding existing action: %s', action.name))
  end
  
  M.actions[action.name] = action
  
  -- Track categories
  if action.category and not M.categories[action.category] then
    M.categories[action.category] = {}
  end
  if action.category then
    M.categories[action.category][action.name] = action
  end
  
  logger.debug('ACTION_REGISTRY', string.format('Registered action: %s (category: %s)', 
    action.name, action.category or 'general'))
  return true
end

---Unregister an action
---@param name string The action name to unregister
---@return boolean success Whether unregistration succeeded
function M.unregister(name)
  local action = M.actions[name]
  if not action then
    logger.warn('ACTION_REGISTRY', string.format('Action not found for unregistration: %s', name))
    return false
  end
  
  -- Remove from category
  if action.category and M.categories[action.category] then
    M.categories[action.category][name] = nil
  end
  
  M.actions[name] = nil
  logger.debug('ACTION_REGISTRY', string.format('Unregistered action: %s', name))
  return true
end

---Execute an action by name
---@param name string The action name
---@param args table Action arguments
---@return boolean success Whether execution succeeded
---@return string? error_msg Error message if failed
function M.execute(name, args)
  local action = M.actions[name]
  if not action then
    local msg = string.format('Action not found: %s', name)
    logger.error('ACTION_REGISTRY', msg)
    return false, msg
  end
  
  local success, error_msg = action:execute(args)
  
  -- Add to history if execution succeeded and action supports undo
  if success and action.can_undo then
    M._add_to_history(action)
  end
  
  return success, error_msg
end

---Undo the last executed action
---@return boolean success Whether undo succeeded
---@return string? error_msg Error message if failed
function M.undo()
  if M.history_index <= 0 then
    local msg = 'No actions to undo'
    logger.info('ACTION_REGISTRY', msg)
    return false, msg
  end
  
  local action = M.history[M.history_index]
  local success, error_msg = action:undo()
  
  if success then
    M.history_index = M.history_index - 1
    logger.info('ACTION_REGISTRY', string.format('Undid action: %s', action.name))
  end
  
  return success, error_msg
end

---Redo the next action in history
---@return boolean success Whether redo succeeded
---@return string? error_msg Error message if failed
function M.redo()
  if M.history_index >= #M.history then
    local msg = 'No actions to redo'
    logger.info('ACTION_REGISTRY', msg)
    return false, msg
  end
  
  local action = M.history[M.history_index + 1]
  local success, error_msg = action:execute(action.context.args or {})
  
  if success then
    M.history_index = M.history_index + 1
    logger.info('ACTION_REGISTRY', string.format('Redid action: %s', action.name))
  end
  
  return success, error_msg
end

---Get list of registered actions
---@param category string? Optional category filter
---@return table<string, table> Action information by name
function M.list_actions(category)
  local action_list = {}
  
  if category then
    if M.categories[category] then
      for name, action in pairs(M.categories[category]) do
        action_list[name] = action:get_info()
      end
    end
  else
    for name, action in pairs(M.actions) do
      action_list[name] = action:get_info()
    end
  end
  
  return action_list
end

---Get available categories
---@return table<string> List of categories
function M.get_categories()
  local cats = {}
  for category, _ in pairs(M.categories) do
    table.insert(cats, category)
  end
  table.sort(cats)
  return cats
end

---Get action history
---@return table history Action execution history
function M.get_history()
  local history = {}
  for i, action in ipairs(M.history) do
    table.insert(history, {
      index = i,
      action = action:get_info(),
      is_current = i == M.history_index
    })
  end
  return history
end

---Clear action history
function M.clear_history()
  M.history = {}
  M.history_index = 0
  logger.debug('ACTION_REGISTRY', 'Action history cleared')
end

---Check if an action exists
---@param name string The action name
---@return boolean exists Whether the action exists
function M.has_action(name)
  return M.actions[name] ~= nil
end

---Get an action by name
---@param name string The action name
---@return Action? action The action or nil if not found
function M.get_action(name)
  return M.actions[name]
end

---Dispatch action with context validation
---@param name string The action name
---@param args table Action arguments
---@param context table? Additional context information
---@return boolean success Whether dispatch succeeded
---@return string? error_msg Error message if failed
function M.dispatch(name, args, context)
  local action = M.actions[name]
  if not action then
    local msg = string.format('Action not found for dispatch: %s', name)
    logger.error('ACTION_REGISTRY', msg)
    return false, msg
  end
  
  -- Check if action can be executed in current context
  local can_execute, reason = action:can_execute(args)
  if not can_execute then
    logger.warn('ACTION_REGISTRY', string.format('Action %s cannot be executed: %s', name, reason))
    return false, reason
  end
  
  -- Add context information
  if context then
    args = args or {}
    args._context = context
  end
  
  return M.execute(name, args)
end

---Initialize the action system and register core actions
function M.init()
  logger.debug('ACTION_REGISTRY', 'Initializing action system')
  
  -- Import and register git actions
  local GitAddAction = require('nexus.actions.git.add')
  local GitUnstageAction = require('nexus.actions.git.unstage')
  local GitCommitAction = require('nexus.actions.git.commit')
  local GitDiffAction = require('nexus.actions.git.diff')
  
  -- Import and register navigation actions
  local OpenFileAction = require('nexus.actions.navigation.open_file')
  local RefreshAction = require('nexus.actions.navigation.refresh')
  
  -- Import and register github actions
  local GitHubBrowseAction = require('nexus.actions.github.browse')
  
  -- Register actions with error handling
  local actions_to_register = {
    { GitAddAction, 'git.add' },
    { GitUnstageAction, 'git.unstage' },
    { GitCommitAction, 'git.commit' },
    { GitDiffAction, 'git.diff' },
    { OpenFileAction, 'navigation.open_file' },
    { RefreshAction, 'navigation.refresh' },
    { GitHubBrowseAction, 'github.browse' }
  }
  
  local registered_count = 0
  for _, action_info in ipairs(actions_to_register) do
    local ActionClass, expected_name = action_info[1], action_info[2]
    local success, err = pcall(function()
      local action_instance = ActionClass:new()
      M.register(action_instance)
      registered_count = registered_count + 1
    end)
    
    if not success then
      logger.error('ACTION_REGISTRY', string.format('Failed to register action %s: %s', 
        expected_name, tostring(err)))
    end
  end
  
  logger.info('ACTION_REGISTRY', string.format('Registered %d actions across %d categories', 
    registered_count, vim.tbl_count(M.categories)))
end

---Add action to history (internal)
---@param action Action The action to add
function M._add_to_history(action)
  -- Remove any history after current position (for new branching)
  for i = M.history_index + 1, #M.history do
    M.history[i] = nil
  end
  
  -- Add new action
  table.insert(M.history, action)
  M.history_index = #M.history
  
  -- Trim history if it exceeds max size
  if #M.history > M.max_history then
    table.remove(M.history, 1)
    M.history_index = M.history_index - 1
  end
  
  logger.debug('ACTION_REGISTRY', string.format('Added to history: %s (position %d)', 
    action.name, M.history_index))
end

return M