local Action = require('nexus.actions.base')
local todo_state = require('nexus.state.todo')
local logger = require('nexus.logger')

---@class TodoDoneAction : Action
local TodoDoneAction = {}
TodoDoneAction.__index = TodoDoneAction
setmetatable(TodoDoneAction, { __index = Action })

function TodoDoneAction:new()
  local instance = Action:new({
    name = "todo.done",
    description = "Mark a todo item as completed",
    category = "todo",
    can_undo = false
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate done todo arguments
---@param args table Action arguments with 'id' field
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function TodoDoneAction:validate(args)
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
  
  -- Check if already completed
  if todo.completed then
    return false, "Todo is already completed"
  end
  
  return true, nil
end

---Execute done todo action
---@param args table Action arguments with 'id' field
---@return boolean success Whether execution succeeded
function TodoDoneAction:_execute(args)
  local id = args.id
  
  -- Store original todo for context
  local original_todo = todo_state.get_todo_by_id(id)
  self.context.original_todo = vim.deepcopy(original_todo)
  self.context.id = id
  
  local completed_todo, error_msg = todo_state.mark_todo_done(id)
  if not completed_todo then
    logger.error('TODO_DONE_ACTION', string.format('Failed to mark todo as done: %s', error_msg or 'unknown error'))
    return false, error_msg
  end
  
  self.context.completed_todo = completed_todo
  
  logger.info('TODO_DONE_ACTION', string.format('Successfully marked todo as done'), {
    id = id,
    text = completed_todo.text
  })
  
  -- Show user feedback
  vim.notify(string.format("Completed todo: %s", completed_todo.text), vim.log.levels.INFO)
  
  return true
end

return TodoDoneAction