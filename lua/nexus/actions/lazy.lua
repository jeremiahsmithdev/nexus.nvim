local M = {}

local logger = require('nexus.logger')

-- Lazy action registry with on-demand loading
local action_registry = {}
local action_metadata = {}
local loaded_actions = {}

-- Action module mapping for lazy loading
local ACTION_MODULES = {
  -- Git actions
  git_add = 'nexus.actions.git.add',
  git_commit = 'nexus.actions.git.commit', 
  git_diff = 'nexus.actions.git.diff',
  git_unstage = 'nexus.actions.git.unstage',
  
  -- Navigation actions
  open_file = 'nexus.actions.navigation.open_file',
  refresh = 'nexus.actions.navigation.refresh',
  
  -- GitHub actions
  github_browse = 'nexus.actions.github.browse',
  
  -- Linear actions
  linear_browse = 'nexus.actions.linear.browse',
  linear_refresh = 'nexus.actions.linear.refresh',
  
  -- Todo actions
  todo_create = 'nexus.actions.todo.create',
  todo_edit = 'nexus.actions.todo.edit',
  todo_done = 'nexus.actions.todo.done',
  todo_delete = 'nexus.actions.todo.delete'
}

-- Register action metadata without loading the module
function M.register_metadata(name, metadata)
  action_metadata[name] = metadata
  logger.debug('ACTION_LAZY', string.format('Registered action metadata: %s', name))
end

-- Get action lazily - load only when needed
function M.get_action(name)
  -- Return from cache if already loaded
  if loaded_actions[name] then
    return loaded_actions[name]
  end
  
  -- Check if we have a module mapping for this action
  local module_path = ACTION_MODULES[name]
  if not module_path then
    logger.warn('ACTION_LAZY', string.format('No module mapping for action: %s', name))
    return nil
  end
  
  -- Load the action module
  local ok, action_module = pcall(require, module_path)
  if not ok then
    logger.error('ACTION_LAZY', string.format('Failed to load action module: %s - %s', module_path, action_module))
    return nil
  end
  
  -- Create action instance
  local action = action_module:new()
  if not action then
    logger.error('ACTION_LAZY', string.format('Failed to create action instance: %s', name))
    return nil
  end
  
  -- Cache the loaded action
  loaded_actions[name] = action
  logger.debug('ACTION_LAZY', string.format('Lazy loaded action: %s', name))
  
  return action
end

-- Execute action by name with lazy loading
function M.execute(name, args)
  local action = M.get_action(name)
  if not action then
    local msg = string.format('Action not found: %s', name)
    logger.error('ACTION_LAZY', msg)
    return false, msg
  end
  
  -- Execute the action
  local success, error_msg = action:execute(args)
  
  -- Add to history if execution succeeded and action supports undo
  if success and action.can_undo then
    M._add_to_history(action)
  end
  
  return success, error_msg
end

-- List available actions (metadata only)
function M.list_actions()
  local actions = {}
  for name, metadata in pairs(action_metadata) do
    actions[name] = metadata
  end
  return actions
end

-- Get actions by category without loading them
function M.get_actions_by_category(category)
  local actions = {}
  for name, metadata in pairs(action_metadata) do
    if metadata.category == category then
      actions[name] = metadata
    end
  end
  return actions
end

-- Check if action is loaded
function M.is_loaded(name)
  return loaded_actions[name] ~= nil
end

-- Unload action from cache to free memory
function M.unload_action(name)
  if loaded_actions[name] then
    loaded_actions[name] = nil
    logger.debug('ACTION_LAZY', string.format('Unloaded action: %s', name))
    return true
  end
  return false
end

-- Preload commonly used actions
function M.preload_common_actions()
  local common_actions = {'refresh', 'open_file'}
  
  for _, action_name in ipairs(common_actions) do
    M.get_action(action_name)
  end
  
  logger.debug('ACTION_LAZY', string.format('Preloaded %d common actions', #common_actions))
end

-- Get action statistics
function M.get_stats()
  local total_actions = 0
  local loaded_count = 0
  
  for _ in pairs(action_metadata) do
    total_actions = total_actions + 1
  end
  
  for _ in pairs(loaded_actions) do
    loaded_count = loaded_count + 1
  end
  
  return {
    total_actions = total_actions,
    loaded_actions = loaded_count,
    unloaded_actions = total_actions - loaded_count,
    load_ratio = total_actions > 0 and (loaded_count / total_actions) * 100 or 0
  }
end

-- Initialize lazy action system
function M.init()
  -- Register action metadata for all available actions
  local metadata_map = {
    git_add = { category = 'git', description = 'Add files to git staging', can_undo = true },
    git_commit = { category = 'git', description = 'Commit staged changes', can_undo = false },
    git_diff = { category = 'git', description = 'Show git diff', can_undo = false },
    git_unstage = { category = 'git', description = 'Unstage files', can_undo = true },
    open_file = { category = 'navigation', description = 'Open file', can_undo = false },
    refresh = { category = 'navigation', description = 'Refresh dashboard', can_undo = false },
    github_browse = { category = 'external', description = 'Browse on GitHub', can_undo = false },
    linear_browse = { category = 'external', description = 'Browse on Linear', can_undo = false },
    linear_refresh = { category = 'external', description = 'Refresh Linear data', can_undo = false },
    todo_create = { category = 'todo', description = 'Create todo item', can_undo = true },
    todo_edit = { category = 'todo', description = 'Edit todo item', can_undo = true },
    todo_done = { category = 'todo', description = 'Mark todo as done', can_undo = true },
    todo_delete = { category = 'todo', description = 'Delete todo item', can_undo = true }
  }
  
  for name, metadata in pairs(metadata_map) do
    M.register_metadata(name, metadata)
  end
  
  logger.debug('ACTION_LAZY', string.format('Initialized lazy action system with %d actions', 
    vim.tbl_count(metadata_map)))
end

-- History management (simplified)
local action_history = {}
local history_index = 0
local max_history = 20

function M._add_to_history(action)
  -- Remove any actions beyond current index
  for i = history_index + 1, #action_history do
    action_history[i] = nil
  end
  
  -- Add new action
  table.insert(action_history, action)
  history_index = #action_history
  
  -- Enforce max history
  while #action_history > max_history do
    table.remove(action_history, 1)
    history_index = history_index - 1
  end
end

function M.undo()
  if history_index <= 0 then
    return false, 'No actions to undo'
  end
  
  local action = action_history[history_index]
  local success, error_msg = action:undo()
  
  if success then
    history_index = history_index - 1
    logger.debug('ACTION_LAZY', 'Undid action: ' .. (action.name or 'unknown'))
  end
  
  return success, error_msg
end

function M.redo()
  if history_index >= #action_history then
    return false, 'No actions to redo'
  end
  
  history_index = history_index + 1
  local action = action_history[history_index]
  local success, error_msg = action:execute()
  
  if success then
    logger.debug('ACTION_LAZY', 'Redid action: ' .. (action.name or 'unknown'))
  else
    history_index = history_index - 1
  end
  
  return success, error_msg
end

return M