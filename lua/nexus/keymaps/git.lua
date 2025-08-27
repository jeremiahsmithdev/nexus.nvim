---@class GitKeymaps
local M = {}

local logger = require('nexus.logger')

--- Handle Enter key in commits section
function M.handle_enter_commits(current_line)
  M.show_commit_details(current_line)
end

--- Handle Enter key in git status section  
function M.handle_enter_git_status(current_line, config)
  local filename = current_line:match("^%s*[MADRCU?][MADRCU?]? (.-)%s+%+") or 
                  current_line:match("^%s*[MADRCU?][MADRCU?]? (.-)%s+%-") or
                  current_line:match("^%s*[MADRCU?][MADRCU?]? (.+)$")
  if filename then
    filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
    
    local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
    local full_path = git_root and (git_root .. '/' .. filename) or filename
    
    local first_line = M.get_first_changed_line(filename)
    local goto_line = first_line and (' | ' .. first_line) or ''
    
    local edit_cmd = 'edit ' .. vim.fn.fnameescape(full_path) .. ' | set number | set signcolumn=yes' .. goto_line
    require('nexus.keymaps.dashboard').handle_action(config, edit_cmd)
  end
end

--- Show commit details in popup
function M.show_commit_details(current_line)
  -- Extract commit hash from the line
  local commit_hash = current_line:match("%s+([a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+)")
  if not commit_hash then
    return
  end
  
  logger.debug('GIT', 'Showing commit details', { hash = commit_hash })
  
  -- Get full commit details
  local commit_info = vim.fn.systemlist('git show --stat --pretty=fuller ' .. commit_hash)
  
  if vim.v.shell_error ~= 0 then
    logger.warn('GIT', 'Failed to get commit details', { hash = commit_hash })
    return
  end
  
  -- Create popup
  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, commit_info)
  
  -- Calculate popup size
  local width = math.min(100, math.max(60, vim.fn.max(vim.tbl_map(vim.fn.strlen, commit_info)) + 4))
  local height = math.min(30, #commit_info + 2)
  
  -- Center the popup
  local ui = vim.api.nvim_list_uis()[1]
  local popup_win = vim.api.nvim_open_win(popup_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = (ui.height - height) / 2,
    col = (ui.width - width) / 2,
    style = 'minimal',
    border = 'rounded',
    title = ' Commit Details ',
    title_pos = 'center'
  })
  
  -- Set popup options
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(popup_buf, 'readonly', true)
  vim.api.nvim_buf_set_option(popup_buf, 'filetype', 'git')
  
  -- Close on 'q' or Escape
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'q', '<cmd>close<cr>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<Esc>', '<cmd>close<cr>', { noremap = true, silent = true })
end

--- Get the first changed line in a file using git diff
function M.get_first_changed_line(filename)
  if not filename then
    return nil
  end
  
  -- Use git diff to find the first changed line
  local git_output = vim.fn.systemlist('git diff --unified=0 HEAD -- "' .. filename .. '"')
  if vim.v.shell_error ~= 0 then
    -- Try with staged changes
    git_output = vim.fn.systemlist('git diff --unified=0 --staged HEAD -- "' .. filename .. '"')
    if vim.v.shell_error ~= 0 then
      return nil
    end
  end
  
  -- Parse the @@ line to get line number
  for _, line in ipairs(git_output) do
    local line_match = line:match("^@@%s+%-(%d+)")
    if line_match then
      return tonumber(line_match)
    end
    
    local plus_match = line:match("^@@%s+%-?%d*,?%d*%s+%+(%d+)")
    if plus_match then
      return tonumber(plus_match)
    end
  end
  
  return nil
end

return M