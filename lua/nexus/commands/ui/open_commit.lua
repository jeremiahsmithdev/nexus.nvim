local Command = require('nexus.commands.base')
local logger = require('nexus.logger')

---@class OpenCommitCommand : Command
local OpenCommitCommand = {}
OpenCommitCommand.__index = OpenCommitCommand
setmetatable(OpenCommitCommand, { __index = Command })

function OpenCommitCommand:new()
  local instance = Command:new({
    name = "ui.open_commit",
    description = "Open commit in browser using GitHub CLI",
    can_undo = false -- Opening browser doesn't need undo
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate open commit arguments
---@param args table Command arguments with 'commit_hash' field
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function OpenCommitCommand:validate(args)
  if not args.commit_hash then
    return false, "commit_hash is required"
  end
  
  if type(args.commit_hash) ~= "string" then
    return false, "commit_hash must be a string"
  end
  
  if args.commit_hash:match("^%s*$") then
    return false, "commit_hash cannot be empty or whitespace only"
  end
  
  -- Check if git and gh CLI are available
  if vim.fn.executable('git') == 0 then
    return false, "git command not found"
  end
  
  if vim.fn.executable('gh') == 0 then
    return false, "gh CLI not found - install GitHub CLI to open commits in browser"
  end
  
  return true, nil
end

---Execute open commit command
---@param args table Command arguments with 'commit_hash'
---@return boolean success Whether execution succeeded
function OpenCommitCommand:_execute(args)
  -- Store context
  self.context.commit_hash = args.commit_hash
  
  local commit_hash = args.commit_hash
  
  -- Get the full commit hash first since gh browse needs the full hash
  local full_hash_cmd = string.format('git rev-parse %s', commit_hash)
  local full_hash = vim.fn.systemlist(full_hash_cmd)[1]
  
  if vim.v.shell_error ~= 0 or not full_hash then
    logger.error('OPEN_COMMIT_CMD', 'Failed to get full commit hash for: ' .. commit_hash)
    vim.schedule(function()
      vim.notify('Failed to resolve commit hash: ' .. commit_hash, vim.log.levels.ERROR)
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
          logger.error('OPEN_COMMIT_CMD', 'Failed to open commit in browser: ' .. error_msg)
          vim.schedule(function()
            vim.notify('Failed to open commit: ' .. error_msg, vim.log.levels.ERROR)
          end)
        end
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        logger.info('OPEN_COMMIT_CMD', 'Opened commit in browser: ' .. full_hash)
        vim.schedule(function()
          vim.notify('Opened commit ' .. commit_hash .. ' in browser', vim.log.levels.INFO)
        end)
      else
        logger.error('OPEN_COMMIT_CMD', 'gh browse failed with exit code: ' .. exit_code)
        vim.schedule(function()
          vim.notify('Failed to open commit in browser', vim.log.levels.ERROR)
        end)
      end
    end
  })
  
  logger.info('OPEN_COMMIT_CMD', string.format('Started opening commit in browser: %s', commit_hash))
  
  -- Return true since we started the async operation successfully
  return true
end

return OpenCommitCommand