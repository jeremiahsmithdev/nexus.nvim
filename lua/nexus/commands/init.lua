---@module nexus.commands
---Command registry and factory for the command pattern implementation

local CommandManager = require('nexus.commands.manager')
local logger = require('nexus.logger')

-- Import available commands
local GitAddCommand = require('nexus.commands.git.add')
local GitUnstageCommand = require('nexus.commands.git.unstage') 
local GitCommitCommand = require('nexus.commands.git.commit')
local RefreshCommand = require('nexus.commands.ui.refresh')
local OpenFileCommand = require('nexus.commands.ui.open_file')
local OpenCommitCommand = require('nexus.commands.ui.open_commit')

-- Global command manager instance
local command_manager = CommandManager:new()

-- Command registry
local M = {
  manager = command_manager
}

---Initialize the command system
function M.init()
  logger.debug('COMMANDS', 'Initializing command system')
  
  -- Register git commands with error handling
  local success, err
  
  success, err = pcall(function()
    command_manager:register(GitAddCommand:new())
  end)
  if not success then
    logger.error('COMMANDS', 'Failed to register GitAddCommand: ' .. tostring(err))
  end
  
  success, err = pcall(function()
    command_manager:register(GitUnstageCommand:new())
  end)
  if not success then
    logger.error('COMMANDS', 'Failed to register GitUnstageCommand: ' .. tostring(err))
  end
  
  success, err = pcall(function()
    command_manager:register(GitCommitCommand:new())
  end)
  if not success then
    logger.error('COMMANDS', 'Failed to register GitCommitCommand: ' .. tostring(err))
  end
  
  -- Register UI commands with error handling
  success, err = pcall(function()
    command_manager:register(RefreshCommand:new())
  end)
  if not success then
    logger.error('COMMANDS', 'Failed to register RefreshCommand: ' .. tostring(err))
  end
  
  success, err = pcall(function()
    command_manager:register(OpenFileCommand:new())
  end)
  if not success then
    logger.error('COMMANDS', 'Failed to register OpenFileCommand: ' .. tostring(err))
  end
  
  success, err = pcall(function()
    command_manager:register(OpenCommitCommand:new())
  end)
  if not success then
    logger.error('COMMANDS', 'Failed to register OpenCommitCommand: ' .. tostring(err))
  end
  
  logger.info('COMMANDS', string.format('Registered %d commands', 
    vim.tbl_count(command_manager:list_commands())))
end

---Execute a command by name
---@param name string The command name
---@param args table Command arguments
---@return boolean success Whether execution succeeded
---@return string? error_msg Error message if failed
function M.execute(name, args)
  return command_manager:execute(name, args)
end

---Undo the last executed command
---@return boolean success Whether undo succeeded
---@return string? error_msg Error message if failed
function M.undo()
  return command_manager:undo()
end

---Redo the next command in history
---@return boolean success Whether redo succeeded
---@return string? error_msg Error message if failed
function M.redo()
  return command_manager:redo()
end

---Get list of available commands
---@return table<string, table> Command information by name
function M.list_commands()
  return command_manager:list_commands()
end

---Get command execution history
---@return table history Command execution history
function M.get_history()
  return command_manager:get_history()
end

---Clear command history
function M.clear_history()
  command_manager:clear_history()
end

---Check if a command exists
---@param name string The command name
---@return boolean exists Whether the command exists
function M.has_command(name)
  return command_manager:has_command(name)
end

---Register a new command (for extensions)
---@param command Command The command to register
---@return boolean success Whether registration succeeded
function M.register_command(command)
  return command_manager:register(command)
end

---Unregister a command (for extensions)
---@param name string The command name to unregister
---@return boolean success Whether unregistration succeeded
function M.unregister_command(name)
  return command_manager:unregister(name)
end

---Helper functions for common operations

---Execute git add command
---@param filename string The file to add
---@param refresh_callback function? Optional refresh callback
---@return boolean success Whether execution succeeded
function M.git_add(filename, refresh_callback)
  return M.execute('git.add', {
    filename = filename,
    refresh_callback = refresh_callback
  })
end

---Execute git unstage command
---@param filename string The file to unstage
---@param refresh_callback function? Optional refresh callback
---@return boolean success Whether execution succeeded
function M.git_unstage(filename, refresh_callback)
  return M.execute('git.unstage', {
    filename = filename,
    refresh_callback = refresh_callback
  })
end

---Execute git commit command
---@param message string The commit message
---@param refresh_callback function? Optional refresh callback
---@param amend boolean? Whether to amend the last commit
---@return boolean success Whether execution succeeded
function M.git_commit(message, refresh_callback, amend)
  return M.execute('git.commit', {
    message = message,
    refresh_callback = refresh_callback,
    amend = amend
  })
end

---Execute refresh command
---@param sections table? Optional list of sections to refresh
---@param force boolean? Whether to force refresh
---@return boolean success Whether execution succeeded
function M.refresh(sections, force)
  return M.execute('ui.refresh', {
    sections = sections,
    force = force
  })
end

---Execute open file command
---@param filename string The file to open
---@param line number? Optional line number
---@param column number? Optional column number
---@param split string? Optional split type ('vertical', 'horizontal', 'tab')
---@return boolean success Whether execution succeeded
function M.open_file(filename, line, column, split)
  return M.execute('ui.open_file', {
    filename = filename,
    line = line,
    column = column,
    split = split
  })
end

---Execute open commit command
---@param commit_hash string The commit hash to open
---@return boolean success Whether execution succeeded
function M.open_commit(commit_hash)
  return M.execute('ui.open_commit', {
    commit_hash = commit_hash
  })
end

return M