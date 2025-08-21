---@class Action
---@field name string The action name
---@field description string Action description
---@field category string Action category (git, navigation, etc.)
---@field can_undo boolean Whether this action supports undo
---@field context table Action execution context
---@field validate fun(args: table): boolean, string? Validate action arguments
---@field execute fun(args: table): boolean Execute the action
---@field undo fun(): boolean Undo the action (optional)

local logger = require('nexus.logger')

local Action = {}

---Create a new action instance
---@param opts table Action options
---@return Action
function Action:new(opts)
  opts = opts or {}
  
  local instance = {
    name = opts.name or "unknown",
    description = opts.description or "",
    category = opts.category or "general",
    can_undo = opts.can_undo or false,
    context = {},
    _executed = false,
    _execution_count = 0
  }
  
  setmetatable(instance, { __index = self })
  return instance
end

---Execute the action with validation and context management
---@param args table Action arguments
---@return boolean success Whether execution succeeded
---@return string? error_msg Error message if failed
function Action:execute(args)
  args = args or {}
  
  -- Validate arguments first
  local valid, error_msg = self:validate(args)
  if not valid then
    logger.error('ACTION', string.format('Action %s validation failed: %s', self.name, error_msg or 'unknown error'))
    return false, error_msg
  end
  
  -- Store execution context
  self.context.args = args
  self.context.timestamp = os.time()
  self.context.execution_id = self._execution_count + 1
  
  -- Execute the action
  logger.debug('ACTION', string.format('Executing action: %s (attempt %d)', self.name, self.context.execution_id))
  
  local success, result = pcall(self._execute, self, args)
  if not success then
    logger.error('ACTION', string.format('Action %s execution failed: %s', self.name, result))
    return false, result
  end
  
  if result then
    self._executed = true
    self._execution_count = self._execution_count + 1
    logger.info('ACTION', string.format('Action %s executed successfully', self.name))
  end
  
  return result, nil
end

---Undo the action if supported
---@return boolean success Whether undo succeeded
---@return string? error_msg Error message if failed
function Action:undo()
  if not self.can_undo then
    local msg = string.format('Action %s does not support undo', self.name)
    logger.warn('ACTION', msg)
    return false, msg
  end
  
  if not self._executed then
    local msg = string.format('Action %s has not been executed', self.name)
    logger.warn('ACTION', msg)
    return false, msg
  end
  
  logger.debug('ACTION', string.format('Undoing action: %s', self.name))
  
  local success, result = pcall(self._undo, self)
  if not success then
    logger.error('ACTION', string.format('Action %s undo failed: %s', self.name, result))
    return false, result
  end
  
  if result then
    self._executed = false
    logger.info('ACTION', string.format('Action %s undone successfully', self.name))
  end
  
  return result, nil
end

---Get action information
---@return table info Action information
function Action:get_info()
  return {
    name = self.name,
    description = self.description,
    category = self.category,
    can_undo = self.can_undo,
    executed = self._executed,
    execution_count = self._execution_count,
    last_execution = self.context.timestamp
  }
end

---Check if action can be executed with given arguments
---@param args table Action arguments
---@return boolean can_execute Whether action can be executed
---@return string? reason Reason if cannot execute
function Action:can_execute(args)
  local valid, error_msg = self:validate(args)
  if not valid then
    return false, error_msg
  end
  
  -- Additional context-specific checks can be added here
  return true, nil
end

---Reset action state
function Action:reset()
  self._executed = false
  self.context = {}
end

---Default validation (override in subclasses)
---@param args table Action arguments
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function Action:validate(args)
  return true, nil
end

---Default execute implementation (must override in subclasses)
---@param args table Action arguments
---@return boolean success Whether execution succeeded
function Action:_execute(args)
  error(string.format('Action %s must implement _execute method', self.name))
end

---Default undo implementation (override if can_undo = true)
---@return boolean success Whether undo succeeded
function Action:_undo()
  if self.can_undo then
    error(string.format('Action %s must implement _undo method', self.name))
  end
  return false
end

return Action