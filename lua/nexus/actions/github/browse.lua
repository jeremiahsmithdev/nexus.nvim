---@class GitHubBrowseAction : Action
local GitHubBrowseAction = {}
local BaseAction = require('nexus.actions.base')
local logger = require('nexus.logger')

setmetatable(GitHubBrowseAction, { __index = BaseAction })

function GitHubBrowseAction.new()
  local instance = BaseAction:new({
    category = "github",
    name = "github.browse",
    description = "Open commit in GitHub browser",
    can_undo = false
  })
  
  setmetatable(instance, { __index = GitHubBrowseAction })
  return instance
end

---Validate GitHub browse arguments
---@param args table Action arguments
---@return boolean success Whether validation passed
---@return string|nil error Error message if validation failed
function GitHubBrowseAction:validate(args)
  if not args.commit_hash then
    return false, "commit_hash is required"
  end
  
  if type(args.commit_hash) ~= "string" or #args.commit_hash == 0 then
    return false, "commit_hash must be a non-empty string"
  end
  
  return true
end

---Execute GitHub browse action
---@param args table Action arguments
---@return boolean success Whether the action succeeded
function GitHubBrowseAction:execute(args)
  logger.debug('GITHUB_BROWSE', 'Opening commit in browser: ' .. args.commit_hash)
  
  -- Store previous state for potential undo (though this action is not undoable)
  self.previous_state = {
    commit_hash = args.commit_hash
  }
  
  -- Get the full commit hash first since gh browse needs the full hash
  local full_hash_cmd = string.format('git rev-parse %s', args.commit_hash)
  local full_hash = vim.fn.systemlist(full_hash_cmd)[1]
  
  if vim.v.shell_error ~= 0 or not full_hash then
    logger.error('GITHUB_BROWSE', 'Failed to get full commit hash for: ' .. args.commit_hash)
    vim.schedule(function()
      vim.notify('Failed to resolve commit hash: ' .. args.commit_hash, vim.log.levels.ERROR)
    end)
    return false
  end
  
  -- Use gh CLI to open commit in browser with full hash
  local gh_cmd = string.format('gh browse %s', full_hash)
  
  -- Run command asynchronously
  vim.fn.jobstart(gh_cmd, {
    on_stderr = function(_, data)
      if data and #data > 0 then
        local error_msg = table.concat(data, '\n'):gsub('\n$', '')
        if error_msg and #error_msg > 0 then
          logger.error('GITHUB_BROWSE', 'GitHub CLI error: ' .. error_msg)
          vim.schedule(function()
            vim.notify('Failed to open commit in browser: ' .. error_msg, vim.log.levels.ERROR)
          end)
        end
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        logger.info('GITHUB_BROWSE', 'Successfully opened commit in browser: ' .. full_hash)
        vim.schedule(function()
          vim.notify('Opened commit in browser: ' .. args.commit_hash:sub(1, 7), vim.log.levels.INFO)
        end)
      else
        logger.error('GITHUB_BROWSE', 'GitHub CLI command failed with exit code: ' .. exit_code)
        vim.schedule(function()
          vim.notify('Failed to open commit in browser (exit code: ' .. exit_code .. ')', vim.log.levels.ERROR)
        end)
      end
    end
  })
  
  return true
end

---This action is not undoable
---@return boolean success Always returns false since browsing is not undoable
function GitHubBrowseAction:undo()
  logger.warn('GITHUB_BROWSE', 'Cannot undo browser action')
  return false
end

return GitHubBrowseAction