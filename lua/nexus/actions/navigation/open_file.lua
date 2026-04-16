local Action = require('nexus.actions.base')
local logger = require('nexus.logger')

---@class OpenFileAction : Action
local OpenFileAction = {}
OpenFileAction.__index = OpenFileAction
setmetatable(OpenFileAction, { __index = Action })

function OpenFileAction:new()
  local instance = Action:new({
    name = "navigation.open_file",
    description = "Open a file in the editor",
    category = "navigation",
    can_undo = false -- File opening doesn't need undo (user can close manually)
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate open file arguments
---@param args table Action arguments with 'filename' field
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function OpenFileAction:validate(args)
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

---Check if file can be opened
---@param args table Action arguments
---@return boolean can_execute Whether action can be executed
---@return string? reason Reason if cannot execute
function OpenFileAction:can_execute(args)
  local valid, error_msg = self:validate(args)
  if not valid then
    return false, error_msg
  end
  
  local filename = args.filename
  
  -- Resolve relative paths to absolute paths using git root
  if not filename:match("^/") then
    local git_root = require('nexus.git.root').get()
    if git_root then
      filename = git_root .. '/' .. filename
    end
  end
  
  -- Check if file exists
  if not vim.loop.fs_stat(filename) then
    return false, string.format("file not found: %s", args.filename)
  end
  
  return true, nil
end

---Execute open file action
---@param args table Action arguments with 'filename' and optional 'line', 'column', 'split'
---@return boolean success Whether execution succeeded
function OpenFileAction:_execute(args)
  -- Store context
  self.context.filename = args.filename
  self.context.line = args.line or 1
  self.context.column = args.column or 0
  self.context.split = args.split
  
  local filename = args.filename
  local line = args.line or 1
  local column = args.column or 0
  
  -- Resolve relative paths to absolute paths using git root
  if not filename:match("^/") then
    local git_root = require('nexus.git.root').get()
    if git_root then
      filename = git_root .. '/' .. filename
    end
  end
  
  -- Open the file based on split preference
  local success = true
  if args.split then
    if args.split == 'vertical' then
      vim.cmd('vsplit ' .. vim.fn.fnameescape(filename))
    elseif args.split == 'horizontal' then
      vim.cmd('split ' .. vim.fn.fnameescape(filename))
    elseif args.split == 'tab' then
      vim.cmd('tabnew ' .. vim.fn.fnameescape(filename))
    else
      logger.warn('OPEN_FILE_ACTION', string.format('Unknown split type: %s, opening normally', args.split))
      vim.cmd('edit ' .. vim.fn.fnameescape(filename))
    end
  else
    vim.cmd('edit ' .. vim.fn.fnameescape(filename))
  end
  
  -- Set cursor position if specified
  if line > 1 or column > 0 then
    vim.api.nvim_win_set_cursor(0, {line, column})
  end
  
  if success then
    logger.info('OPEN_FILE_ACTION', string.format('Successfully opened file: %s', filename))
  else
    logger.error('OPEN_FILE_ACTION', string.format('Failed to open file: %s', filename))
  end
  
  return success
end

return OpenFileAction