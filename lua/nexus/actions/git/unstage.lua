local Action = require('nexus.actions.base')
local git_operations = require('nexus.git.operations')
local logger = require('nexus.logger')

---@class GitUnstageAction : Action
local GitUnstageAction = {}
GitUnstageAction.__index = GitUnstageAction
setmetatable(GitUnstageAction, { __index = Action })

function GitUnstageAction:new()
  local instance = Action:new({
    name = "git.unstage",
    description = "Unstage file(s) from git staging area",
    category = "git",
    can_undo = true
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate git unstage arguments
---@param args table Action arguments with 'filename' field
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function GitUnstageAction:validate(args)
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

---Execute git unstage action
---@param args table Action arguments with 'filename' and optional 'refresh_callback'
---@return boolean success Whether execution succeeded
function GitUnstageAction:_execute(args)
  -- Store context for undo
  self.context.filename = args.filename
  self.context.refresh_callback = args.refresh_callback
  
  -- Execute git reset (unstage)
  local success = git_operations.git_unstage_file(args.filename, args.refresh_callback)
  
  if success then
    logger.info('GIT_UNSTAGE_ACTION', string.format('Successfully unstaged file: %s', args.filename))
  else
    logger.error('GIT_UNSTAGE_ACTION', string.format('Failed to unstage file: %s', args.filename))
  end
  
  return success
end

---Undo git unstage action by re-adding the file
---@return boolean success Whether undo succeeded
function GitUnstageAction:_undo()
  local filename = self.context.filename
  local refresh_callback = self.context.refresh_callback
  
  if not filename then
    logger.error('GIT_UNSTAGE_ACTION', 'Cannot undo: missing filename context')
    return false
  end
  
  -- Use git add to re-stage the file
  local success = git_operations.git_add_file(filename, refresh_callback)
  
  if success then
    logger.info('GIT_UNSTAGE_ACTION', string.format('Successfully undid unstage for file: %s', filename))
  else
    logger.error('GIT_UNSTAGE_ACTION', string.format('Failed to undo unstage for file: %s', filename))
  end
  
  return success
end

return GitUnstageAction