---@class CommandManager
---@field commands table<string, Command> Registered commands
---@field history table<Command> Command execution history
---@field history_index number Current position in history
---@field max_history number Maximum history size

local logger = require('nexus.logger')

local CommandManager = {
  commands = {},
  history = {},
  history_index = 0,
  max_history = 50
}

---Register a command
---@param command Command The command to register
---@return boolean success Whether registration succeeded
function CommandManager:register(command)
  if not command or not command.name then
    logger.error('COMMAND_MANAGER', 'Cannot register command without name')
    return false
  end
  
  if self.commands[command.name] then
    logger.warn('COMMAND_MANAGER', string.format('Overriding existing command: %s', command.name))
  end
  
  self.commands[command.name] = command
  logger.debug('COMMAND_MANAGER', string.format('Registered command: %s', command.name))
  return true
end

---Unregister a command
---@param name string The command name to unregister
---@return boolean success Whether unregistration succeeded
function CommandManager:unregister(name)
  if not self.commands[name] then
    logger.warn('COMMAND_MANAGER', string.format('Command not found for unregistration: %s', name))
    return false
  end
  
  self.commands[name] = nil
  logger.debug('COMMAND_MANAGER', string.format('Unregistered command: %s', name))
  return true
end

---Execute a command by name
---@param name string The command name
---@param args table Command arguments
---@return boolean success Whether execution succeeded
---@return string? error_msg Error message if failed
function CommandManager:execute(name, args)
  local command = self.commands[name]
  if not command then
    local msg = string.format('Command not found: %s', name)
    logger.error('COMMAND_MANAGER', msg)
    return false, msg
  end
  
  local success, error_msg = command:execute(args)
  
  -- Add to history if execution succeeded and command supports undo
  if success and command.can_undo then
    self:_add_to_history(command)
  end
  
  return success, error_msg
end

---Undo the last executed command
---@return boolean success Whether undo succeeded
---@return string? error_msg Error message if failed
function CommandManager:undo()
  if self.history_index <= 0 then
    local msg = 'No commands to undo'
    logger.info('COMMAND_MANAGER', msg)
    return false, msg
  end
  
  local command = self.history[self.history_index]
  local success, error_msg = command:undo()
  
  if success then
    self.history_index = self.history_index - 1
    logger.info('COMMAND_MANAGER', string.format('Undid command: %s', command.name))
  end
  
  return success, error_msg
end

---Redo the next command in history
---@return boolean success Whether redo succeeded  
---@return string? error_msg Error message if failed
function CommandManager:redo()
  if self.history_index >= #self.history then
    local msg = 'No commands to redo'
    logger.info('COMMAND_MANAGER', msg)
    return false, msg
  end
  
  local command = self.history[self.history_index + 1]
  local success, error_msg = command:execute(command.last_args or {})
  
  if success then
    self.history_index = self.history_index + 1
    logger.info('COMMAND_MANAGER', string.format('Redid command: %s', command.name))
  end
  
  return success, error_msg
end

---Get list of registered commands
---@return table<string, table> Command information by name
function CommandManager:list_commands()
  local command_list = {}
  for name, command in pairs(self.commands) do
    command_list[name] = command:get_info()
  end
  return command_list
end

---Get command history
---@return table history Command execution history
function CommandManager:get_history()
  local history = {}
  for i, command in ipairs(self.history) do
    table.insert(history, {
      index = i,
      command = command:get_info(),
      is_current = i == self.history_index
    })
  end
  return history
end

---Clear command history
function CommandManager:clear_history()
  self.history = {}
  self.history_index = 0
  logger.debug('COMMAND_MANAGER', 'Command history cleared')
end

---Check if a command exists
---@param name string The command name
---@return boolean exists Whether the command exists
function CommandManager:has_command(name)
  return self.commands[name] ~= nil
end

---Get a command by name
---@param name string The command name
---@return Command? command The command or nil if not found
function CommandManager:get_command(name)
  return self.commands[name]
end

---Add command to history (internal)
---@param command Command The command to add
function CommandManager:_add_to_history(command)
  -- Remove any history after current position (for new branching)
  for i = self.history_index + 1, #self.history do
    self.history[i] = nil
  end
  
  -- Add new command
  table.insert(self.history, command)
  self.history_index = #self.history
  
  -- Trim history if it exceeds max size
  if #self.history > self.max_history then
    table.remove(self.history, 1)
    self.history_index = self.history_index - 1
  end
  
  logger.debug('COMMAND_MANAGER', string.format('Added to history: %s (position %d)', 
    command.name, self.history_index))
end

---Create a new command manager instance
---@param opts table? Configuration options
---@return CommandManager
function CommandManager:new(opts)
  opts = opts or {}
  
  local instance = {
    commands = {},
    history = {},
    history_index = 0,
    max_history = opts.max_history or 50
  }
  
  setmetatable(instance, { __index = self })
  return instance
end

return CommandManager