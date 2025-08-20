local Command = require('nexus.commands.base')
local git_operations = require('nexus.git.operations')
local git_status = require('nexus.git.status')
local logger = require('nexus.logger')

---@class GitAddCommand : Command
local GitAddCommand = {}
GitAddCommand.__index = GitAddCommand
setmetatable(GitAddCommand, { __index = Command })

function GitAddCommand:new()
  local instance = Command:new({
    name = "git.add",
    description = "Add file(s) to git staging area",
    can_undo = true
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate git add arguments
---@param args table Command arguments with 'filename' field
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function GitAddCommand:validate(args)
  if not args.filename then
    return false, "filename is required"
  end
  
  if type(args.filename) ~= "string" then
    return false, "filename must be a string"
  end
  
  if args.filename:match("^%s*$") then
    return false, "filename cannot be empty or whitespace only"
  end
  
  return true, nil
end

---Execute git add command
---@param args table Command arguments with 'filename' and optional 'refresh_callback'
---@return boolean success Whether execution succeeded
function GitAddCommand:_execute(args)
  -- Store context for undo
  self.context.filename = args.filename
  self.context.refresh_callback = args.refresh_callback
  
  -- Execute git add
  local success = git_operations.git_add_file(args.filename, args.refresh_callback)
  
  if success then
    logger.info('GIT_ADD_CMD', string.format('Successfully added file: %s', args.filename))
  else
    logger.error('GIT_ADD_CMD', string.format('Failed to add file: %s', args.filename))
  end
  
  return success
end

---Undo git add command by unstaging the file
---@return boolean success Whether undo succeeded
function GitAddCommand:_undo()
  local filename = self.context.filename
  local refresh_callback = self.context.refresh_callback
  
  if not filename then
    logger.error('GIT_ADD_CMD', 'Cannot undo: missing filename context')
    return false
  end
  
  -- Use git reset to unstage the file
  local success = git_operations.git_unstage_file(filename, refresh_callback)
  
  if success then
    logger.info('GIT_ADD_CMD', string.format('Successfully undid add for file: %s', filename))
  else
    logger.error('GIT_ADD_CMD', string.format('Failed to undo add for file: %s', filename))
  end
  
  return success
end

return GitAddCommand