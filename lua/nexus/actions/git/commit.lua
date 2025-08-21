local Action = require('nexus.actions.base')
local git_operations = require('nexus.git.operations')
local logger = require('nexus.logger')

---@class GitCommitAction : Action
local GitCommitAction = {}
GitCommitAction.__index = GitCommitAction
setmetatable(GitCommitAction, { __index = Action })

function GitCommitAction:new()
  local instance = Action:new({
    name = "git.commit",
    description = "Create a git commit",
    category = "git",
    can_undo = false -- Commits are generally not undoable via simple operations
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate git commit arguments
---@param args table Action arguments with 'message' field and optional 'amend'
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function GitCommitAction:validate(args)
  -- For interactive commits (no message), allow empty args
  if not args.message and not args.interactive then
    return false, "commit message is required (or set interactive=true)"
  end
  
  if args.message then
    if type(args.message) ~= "string" then
      return false, "commit message must be a string"
    end
    
    if string.match(args.message, "^%s*$") then
      return false, "commit message cannot be empty or whitespace only"
    end
  end
  
  return true, nil
end

---Execute git commit action
---@param args table Action arguments with 'message', optional 'amend', 'interactive', and 'refresh_callback'
---@return boolean success Whether execution succeeded
function GitCommitAction:_execute(args)
  -- Store context for potential future use
  self.context.message = args.message
  self.context.amend = args.amend or false
  self.context.interactive = args.interactive or false
  self.context.refresh_callback = args.refresh_callback
  
  -- Get commit hash before operation (for amend tracking)
  local previous_commit = vim.fn.systemlist('git rev-parse HEAD')[1]
  self.context.previous_commit = previous_commit
  
  local success
  if args.interactive or not args.message then
    -- For interactive commits, create commit window
    if args.amend then
      success = git_operations.create_commit_amend_window(args.refresh_callback)
    else
      success = git_operations.create_commit_window(args.refresh_callback)
    end
    -- For interactive commits, we consider the window creation as success
    success = true
  else
    -- Regular commit with message
    success = git_operations.git_commit(args.message, args.refresh_callback)
  end
  
  if success then
    local operation = args.amend and "amended commit" or "created commit"
    local msg_preview = args.message and (args.message:sub(1, 50) .. (args.message:len() > 50 and "..." or "")) or "interactive"
    logger.info('GIT_COMMIT_ACTION', string.format('Successfully %s: %s', operation, msg_preview))
  else
    local operation = args.amend and "amend commit" or "create commit"
    logger.error('GIT_COMMIT_ACTION', string.format('Failed to %s', operation))
  end
  
  return success
end

return GitCommitAction