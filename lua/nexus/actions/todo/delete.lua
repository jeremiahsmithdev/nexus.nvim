local Action = require('nexus.actions.base')
local todo_state = require('nexus.state.todo')
local logger = require('nexus.logger')

---@class TodoDeleteAction : Action
local TodoDeleteAction = {}
TodoDeleteAction.__index = TodoDeleteAction
setmetatable(TodoDeleteAction, { __index = Action })

function TodoDeleteAction:new()
  local instance = Action:new({
    name = "todo.delete",
    description = "Delete a todo item",
    category = "todo",
    can_undo = false
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate delete todo arguments
---@param args table Action arguments with 'id' field
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function TodoDeleteAction:validate(args)
  if not args then
    return false, "Arguments required"
  end
  
  if not args.id then
    return false, "Todo ID is required"
  end
  
  if type(args.id) ~= "string" then
    return false, "Todo ID must be a string"
  end
  
  -- Check if todo exists
  local todo = todo_state.get_todo_by_id(args.id)
  if not todo then
    return false, string.format("Todo with ID '%s' not found", args.id)
  end
  
  return true, nil
end

---Execute delete todo action
---@param args table Action arguments with 'id' field
---@return boolean success Whether execution succeeded
function TodoDeleteAction:_execute(args)
  local id = args.id
  
  -- Store original todo for context
  local original_todo = todo_state.get_todo_by_id(id)
  self.context.original_todo = vim.deepcopy(original_todo)
  self.context.id = id
  
  local success, error_msg = todo_state.delete_todo(id)
  if not success then
    logger.error('TODO_DELETE_ACTION', string.format('Failed to delete todo: %s', error_msg or 'unknown error'))
    return false, error_msg
  end
  
  logger.info('TODO_DELETE_ACTION', string.format('Successfully deleted todo'), {
    id = id,
    text = original_todo.text
  })
  
  -- Show user feedback
  vim.notify(string.format("Deleted todo: %s", original_todo.text), vim.log.levels.INFO)
  
  return true
end

return TodoDeleteAction