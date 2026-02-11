--- Action to toggle a todo item's important flag
local Action = require('nexus.actions.base')
local todo_state = require('nexus.state.todo')
local logger = require('nexus.logger')

---@class TodoImportantAction : Action
local TodoImportantAction = {}
TodoImportantAction.__index = TodoImportantAction
setmetatable(TodoImportantAction, { __index = Action })

function TodoImportantAction:new()
  local instance = Action:new({
    name = "todo.important",
    description = "Toggle a todo item's important flag",
    category = "todo",
    can_undo = false
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate toggle important arguments
---@param args table Action arguments with 'id' field
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function TodoImportantAction:validate(args)
  if not args then
    return false, "Arguments required"
  end

  if not args.id then
    return false, "Todo ID is required"
  end

  if type(args.id) ~= "string" then
    return false, "Todo ID must be a string"
  end

  local todo = todo_state.get_todo_by_id(args.id)
  if not todo then
    return false, string.format("Todo with ID '%s' not found", args.id)
  end

  return true, nil
end

---Execute toggle important action
---@param args table Action arguments with 'id' field
---@return boolean success Whether execution succeeded
function TodoImportantAction:_execute(args)
  local id = args.id

  local original_todo = todo_state.get_todo_by_id(id)
  self.context.original_todo = vim.deepcopy(original_todo)
  self.context.id = id

  local updated_todo, error_msg = todo_state.toggle_important(id)
  if not updated_todo then
    logger.error('TODO_IMPORTANT_ACTION', string.format('Failed to toggle importance: %s', error_msg or 'unknown error'))
    return false, error_msg
  end

  self.context.updated_todo = updated_todo

  local status_label = updated_todo.important and "marked as important" or "unmarked as important"
  logger.info('TODO_IMPORTANT_ACTION', 'Toggled todo importance', {
    id = id,
    text = updated_todo.text,
    important = updated_todo.important
  })

  vim.notify(string.format("Todo %s: %s", status_label, updated_todo.text), vim.log.levels.INFO)

  return true
end

return TodoImportantAction
