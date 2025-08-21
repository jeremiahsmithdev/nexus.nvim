local Action = require('nexus.actions.base')
local logger = require('nexus.logger')

---@class GitDiffAction : Action
local GitDiffAction = {}
GitDiffAction.__index = GitDiffAction
setmetatable(GitDiffAction, { __index = Action })

function GitDiffAction:new()
  local instance = Action:new({
    name = "git.diff",
    description = "Show git diff for file(s)",
    category = "git",
    can_undo = false -- Showing diffs doesn't need undo
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate git diff arguments
---@param args table Action arguments with optional 'filename', 'staged', 'commit'
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function GitDiffAction:validate(args)
  -- All arguments are optional for git diff
  if args.filename and type(args.filename) ~= "string" then
    return false, "filename must be a string"
  end
  
  if args.commit and type(args.commit) ~= "string" then
    return false, "commit must be a string"
  end
  
  return true, nil
end

---Execute git diff action
---@param args table Action arguments with optional 'filename', 'staged', 'commit', 'split'
---@return boolean success Whether execution succeeded
function GitDiffAction:_execute(args)
  -- Store context
  self.context.filename = args.filename
  self.context.staged = args.staged or false
  self.context.commit = args.commit
  self.context.split = args.split or 'horizontal'
  
  -- Build git diff command
  local diff_cmd = 'git diff'
  
  if args.staged then
    diff_cmd = diff_cmd .. ' --staged'
  end
  
  if args.commit then
    diff_cmd = diff_cmd .. ' ' .. args.commit
  end
  
  if args.filename then
    diff_cmd = diff_cmd .. ' -- "' .. args.filename .. '"'
  end
  
  -- Execute diff command
  local diff_output = vim.fn.systemlist(diff_cmd)
  
  if vim.v.shell_error ~= 0 then
    logger.error('GIT_DIFF_ACTION', 'Failed to get git diff: ' .. (diff_output[1] or 'unknown error'))
    return false
  end
  
  if #diff_output == 0 then
    logger.info('GIT_DIFF_ACTION', 'No differences found')
    vim.schedule(function()
      vim.notify('No differences found', vim.log.levels.INFO)
    end)
    return true
  end
  
  -- Create diff buffer and window
  local diff_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, diff_output)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(diff_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(diff_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(diff_buf, 'filetype', 'diff')
  vim.api.nvim_buf_set_option(diff_buf, 'modifiable', false)
  
  -- Create window based on split preference
  if args.split == 'vertical' then
    vim.cmd('vsplit')
  elseif args.split == 'tab' then
    vim.cmd('tabnew')
  else
    vim.cmd('split')
  end
  
  vim.api.nvim_win_set_buf(0, diff_buf)
  
  -- Set buffer name
  local buf_name = 'git-diff'
  if args.filename then
    buf_name = buf_name .. ':' .. args.filename
  end
  if args.staged then
    buf_name = buf_name .. ':staged'
  end
  if args.commit then
    buf_name = buf_name .. ':' .. args.commit
  end
  
  vim.api.nvim_buf_set_name(diff_buf, buf_name)
  
  -- Set up keymap to close diff
  vim.api.nvim_buf_set_keymap(diff_buf, 'n', 'q', '<cmd>close<CR>', 
    { noremap = true, silent = true })
  
  logger.info('GIT_DIFF_ACTION', string.format('Showed diff for: %s', args.filename or 'all files'))
  
  return true
end

return GitDiffAction