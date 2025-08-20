local Command = require('nexus.commands.base')
local logger = require('nexus.logger')

---@class OpenFileCommand : Command
local OpenFileCommand = {}
OpenFileCommand.__index = OpenFileCommand
setmetatable(OpenFileCommand, { __index = Command })

function OpenFileCommand:new()
  local instance = Command:new({
    name = "ui.open_file",
    description = "Open a file in the editor",
    can_undo = false -- File opening doesn't need undo (user can close manually)
  })
  setmetatable(instance, { __index = self })
  return instance
end

---Validate open file arguments
---@param args table Command arguments with 'filename' field
---@return boolean valid Whether arguments are valid
---@return string? error_msg Error message if invalid
function OpenFileCommand:validate(args)
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

---Execute open file command
---@param args table Command arguments with 'filename' and optional 'line', 'column'
---@return boolean success Whether execution succeeded
function OpenFileCommand:_execute(args)
  -- Store context
  self.context.filename = args.filename
  self.context.line = args.line
  self.context.column = args.column
  self.context.split = args.split
  
  local filename = args.filename
  local line = args.line or 1
  local column = args.column or 0
  
  -- Resolve relative paths to absolute paths using git root
  if not filename:match("^/") then
    local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
    if git_root and vim.v.shell_error == 0 then
      filename = git_root .. '/' .. filename
    end
  end
  
  local success = true
  
  -- Check if file exists
  if not vim.loop.fs_stat(filename) then
    logger.error('OPEN_FILE_CMD', string.format('File not found: %s', filename))
    return false
  end
  
  -- Open the file
  if args.split then
    if args.split == 'vertical' then
      vim.cmd('vsplit ' .. vim.fn.fnameescape(filename))
    elseif args.split == 'horizontal' then
      vim.cmd('split ' .. vim.fn.fnameescape(filename))
    elseif args.split == 'tab' then
      vim.cmd('tabnew ' .. vim.fn.fnameescape(filename))
    else
      logger.warn('OPEN_FILE_CMD', string.format('Unknown split type: %s, opening normally', args.split))
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
    logger.info('OPEN_FILE_CMD', string.format('Successfully opened file: %s', filename))
  else
    logger.error('OPEN_FILE_CMD', string.format('Failed to open file: %s', filename))
  end
  
  return success
end

return OpenFileCommand