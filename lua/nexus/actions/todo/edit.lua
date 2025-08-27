local Action = require('nexus.actions.base')
local todo_state = require('nexus.state.todo')
local logger = require('nexus.logger')

---@class TodoEditAction : Action
local TodoEditAction = {}
TodoEditAction.__index = TodoEditAction
setmetatable(TodoEditAction, { __index = Action })

function TodoEditAction:new()
  local instance = Action:new({
    name = "todo.edit",
    description = "Edit an existing todo item",
    category = "todo",
    can_undo = false
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate edit todo arguments
---@param args table Action arguments with 'id' and 'text' fields
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function TodoEditAction:validate(args)
  if not args then
    return false, "Arguments required"
  end
  
  if not args.id then
    return false, "Todo ID is required"
  end
  
  if type(args.id) ~= "string" then
    return false, "Todo ID must be a string"
  end
  
  if not args.text then
    return false, "Todo text is required"
  end
  
  if type(args.text) ~= "string" then
    return false, "Todo text must be a string"
  end
  
  if args.text:match("^%s*$") then
    return false, "Todo text cannot be empty or only whitespace"
  end
  
  -- Check if todo exists
  local todo = todo_state.get_todo_by_id(args.id)
  if not todo then
    return false, string.format("Todo with ID '%s' not found", args.id)
  end
  
  return true, nil
end

---Execute edit todo action
---@param args table Action arguments with 'id' and 'text' fields
---@return boolean success Whether execution succeeded
function TodoEditAction:_execute(args)
  local id = args.id
  local text = args.text:gsub("^%s+", ""):gsub("%s+$", "") -- Trim whitespace
  
  -- Store original todo for context
  local original_todo = todo_state.get_todo_by_id(id)
  self.context.original_todo = vim.deepcopy(original_todo)
  self.context.id = id
  self.context.new_text = text
  
  local updated_todo, error_msg = todo_state.edit_todo(id, text)
  if not updated_todo then
    logger.error('TODO_EDIT_ACTION', string.format('Failed to edit todo: %s', error_msg or 'unknown error'))
    return false, error_msg
  end
  
  self.context.updated_todo = updated_todo
  
  logger.info('TODO_EDIT_ACTION', string.format('Successfully edited todo'), {
    id = id,
    old_text = original_todo.text,
    new_text = text
  })
  
  -- Show user feedback
  vim.notify(string.format("Updated todo: %s", text), vim.log.levels.INFO)
  
  return true
end

return TodoEditAction