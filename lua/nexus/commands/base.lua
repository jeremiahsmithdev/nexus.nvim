---@class Command
---@field name string The command name
---@field description string Command description
---@field can_undo boolean Whether this command supports undo
---@field execute fun(args: table): boolean Execute the command
---@field undo fun(): boolean Undo the command (optional)
---@field validate fun(args: table): boolean, string? Validate command arguments

local logger = require('nexus.logger')

local Command = {}

---Create a new command instance
---@param opts table Command options
---@return Command
function Command:new(opts)
  opts = opts or {}
  
  local instance = {
    name = opts.name or "unknown",
    description = opts.description or "",
    can_undo = opts.can_undo or false,
    context = {},
    _executed = false
  }
  
  setmetatable(instance, { __index = self })
  return instance
end

---Execute the command with validation
---@param args table Command arguments
---@return boolean success Whether execution succeeded
---@return string? error_msg Error message if failed
function Command:execute(args)
  args = args or {}
  
  -- Validate arguments first
  local valid, error_msg = self:validate(args)
  if not valid then
    logger.error('COMMAND', string.format('Command %s validation failed: %s', self.name, error_msg or 'unknown error'))
    return false, error_msg
  end
  
  -- Execute the command
  logger.debug('COMMAND', string.format('Executing command: %s', self.name))
  
  local success, result = pcall(self._execute, self, args)
  if not success then
    logger.error('COMMAND', string.format('Command %s execution failed: %s', self.name, result))
    return false, result
  end
  
  if result then
    self._executed = true
    logger.info('COMMAND', string.format('Command %s executed successfully', self.name))
  end
  
  return result, nil
end

---Undo the command if supported
---@return boolean success Whether undo succeeded
---@return string? error_msg Error message if failed
function Command:undo()
  if not self.can_undo then
    local msg = string.format('Command %s does not support undo', self.name)
    logger.warn('COMMAND', msg)
    return false, msg
  end
  
  if not self._executed then
    local msg = string.format('Command %s has not been executed', self.name)
    logger.warn('COMMAND', msg)
    return false, msg
  end
  
  logger.debug('COMMAND', string.format('Undoing command: %s', self.name))
  
  local success, result = pcall(self._undo, self)
  if not success then
    logger.error('COMMAND', string.format('Command %s undo failed: %s', self.name, result))
    return false, result
  end
  
  if result then
    self._executed = false
    logger.info('COMMAND', string.format('Command %s undone successfully', self.name))
  end
  
  return result, nil
end

---Get command information
---@return table info Command information
function Command:get_info()
  return {
    name = self.name,
    description = self.description,
    can_undo = self.can_undo,
    executed = self._executed
  }
end

---Default validation (override in subclasses)
---@param args table Command arguments
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function Command:validate(args)
  return true, nil
end

---Default execute implementation (must override in subclasses)
---@param args table Command arguments
---@return boolean success Whether execution succeeded
function Command:_execute(args)
  error(string.format('Command %s must implement _execute method', self.name))
end

---Default undo implementation (override if can_undo = true)
---@return boolean success Whether undo succeeded
function Command:_undo()
  if self.can_undo then
    error(string.format('Command %s must implement _undo method', self.name))
  end
  return false
end

return Command