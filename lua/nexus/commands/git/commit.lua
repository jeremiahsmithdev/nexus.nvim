local Command = require('nexus.commands.base')
local git_operations = require('nexus.git.operations')
local logger = require('nexus.logger')

---@class GitCommitCommand : Command
local GitCommitCommand = {}
GitCommitCommand.__index = GitCommitCommand
setmetatable(GitCommitCommand, { __index = Command })

function GitCommitCommand:new()
  local instance = Command:new({
    name = "git.commit",
    description = "Create a git commit",
    can_undo = false -- Commits are generally not undoable via simple operations
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate git commit arguments
---@param args table Command arguments with 'message' field and optional 'amend'
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function GitCommitCommand:validate(args)
  if not args.message then
    return false, "commit message is required"
  end
  
  if type(args.message) ~= "string" then
    return false, "commit message must be a string"
  end
  
  if string.match(args.message, "^%s*$") then
    return false, "commit message cannot be empty or whitespace only"
  end
  
  return true, nil
end

---Execute git commit command
---@param args table Command arguments with 'message', optional 'amend', and 'refresh_callback'
---@return boolean success Whether execution succeeded
function GitCommitCommand:_execute(args)
  -- Store context for potential future use
  self.context.message = args.message
  self.context.amend = args.amend or false
  self.context.refresh_callback = args.refresh_callback
  
  -- Get commit hash before operation (for amend tracking)
  local previous_commit = vim.fn.systemlist('git rev-parse HEAD')[1]
  self.context.previous_commit = previous_commit
  
  local success
  if args.amend then
    -- For amend, we need to use a different approach since git_operations.git_commit
    -- doesn't support amend. We'll create temporary commit amend window.
    success = git_operations.create_commit_amend_window(args.refresh_callback)
  else
    -- Regular commit
    success = git_operations.git_commit(args.message, args.refresh_callback)
  end
  
  if success then
    local operation = args.amend and "amended commit" or "created commit"
    logger.info('GIT_COMMIT_CMD', string.format('Successfully %s with message: %s', 
      operation, args.message:sub(1, 50) .. (args.message:len() > 50 and "..." or "")))
  else
    local operation = args.amend and "amend commit" or "create commit"
    logger.error('GIT_COMMIT_CMD', string.format('Failed to %s', operation))
  end
  
  return success
end

return GitCommitCommand