local Action = require('nexus.actions.base')
local todo_state = require('nexus.state.todo')
local logger = require('nexus.logger')

---@class TodoCreateAction : Action
local TodoCreateAction = {}
TodoCreateAction.__index = TodoCreateAction
setmetatable(TodoCreateAction, { __index = Action })

function TodoCreateAction:new()
  local instance = Action:new({
    name = "todo.create",
    description = "Create a new todo item",
    category = "todo",
    can_undo = false
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate create todo arguments
---@param args table Action arguments with 'text' field
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function TodoCreateAction:validate(args)
  if not args then
    return false, "Arguments required"
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
  
  return true, nil
end

---Execute create todo action
---@param args table Action arguments with 'text' field
---@return boolean success Whether execution succeeded
function TodoCreateAction:_execute(args)
  local text = args.text:gsub("^%s+", ""):gsub("%s+$", "") -- Trim whitespace
  
  -- Store context
  self.context.text = text
  
  local todo, error_msg = todo_state.add_todo(text)
  if not todo then
    logger.error('TODO_CREATE_ACTION', string.format('Failed to create todo: %s', error_msg or 'unknown error'))
    return false, error_msg
  end
  
  self.context.created_todo = todo
  
  logger.info('TODO_CREATE_ACTION', string.format('Successfully created todo: %s', text), {
    id = todo.id
  })
  
  -- Show user feedback
  vim.notify(string.format("Created todo: %s", text), vim.log.levels.INFO)
  
  return true
end

return TodoCreateAction