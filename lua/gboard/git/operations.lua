local M = {}

function M.git_add_file(filename, refresh_callback)
  local result = vim.fn.system('git add "' .. filename .. '"')
  if vim.v.shell_error == 0 then
    print('Added: ' .. filename)
    if refresh_callback then
      refresh_callback()
    end
    return true
  else
    print('Failed to add: ' .. filename .. ' - ' .. result)
    return false
  end
end

function M.git_unstage_file(filename, refresh_callback)
  local result = vim.fn.system('git reset HEAD "' .. filename .. '"')
  if vim.v.shell_error == 0 then
    print('Unstaged: ' .. filename)
    if refresh_callback then
      refresh_callback()
    end
    return true
  else
    print('Failed to unstage: ' .. filename .. ' - ' .. result)
    return false
  end
end

function M.git_commit(message, refresh_callback)
  local result = vim.fn.system('git commit -m "' .. message .. '"')
  if vim.v.shell_error == 0 then
    print('Committed: ' .. message:sub(1, 50) .. (message:len() > 50 and "..." or ""))
    if refresh_callback then
      refresh_callback()
    end
    return true
  else
    print('Commit failed: ' .. result)
    return false
  end
end

function M.create_commit_window(refresh_callback)
  -- Create floating window for commit message
  local width = 60
  local height = 15
  local bufnr = vim.api.nvim_create_buf(false, true)
  
  -- Calculate position to center the window
  local win_width = vim.api.nvim_get_option('columns')
  local win_height = vim.api.nvim_get_option('lines')
  local row = math.ceil((win_height - height) / 2 - 1)
  local col = math.ceil((win_width - width) / 2)
  
  local opts = {
    style = "minimal",
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    title = " Git Commit ",
    title_pos = "center"
  }
  
  local win = vim.api.nvim_open_win(bufnr, true, opts)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'gitcommit')
  
  -- Disable completions
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', '')
  vim.api.nvim_buf_set_option(bufnr, 'completefunc', '')
  
  -- Create empty lines in buffer to have lines for extmarks
  local empty_lines = {}
  for i = 1, height do
    table.insert(empty_lines, "")
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, empty_lines)
  
  -- Add shortcuts as virtual text at the bottom, centered
  local ns_id = vim.api.nvim_create_namespace('gboard_commit')
  local help_text = "<Enter>/<C-s>: commit  <C-c>: cancel"
  local padding = math.floor((width - #help_text) / 2)
  vim.api.nvim_buf_set_extmark(bufnr, ns_id, height - 1, 0, {
    virt_text = {{string.rep(" ", padding) .. help_text, "Comment"}},
    virt_text_pos = "overlay"
  })
  
  -- Position cursor at the beginning
  vim.api.nvim_win_set_cursor(win, {1, 0})
  
  -- Function to handle commit
  local function do_commit()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local commit_msg = ""
    
    -- Get commit message (everything before comment lines)
    for _, line in ipairs(lines) do
      if not line:match("^#") and line ~= "" then
        commit_msg = commit_msg .. line .. "\n"
      end
    end
    
    commit_msg = commit_msg:gsub("^%s*", ""):gsub("%s*$", "") -- trim
    
    if commit_msg ~= "" then
      vim.api.nvim_win_close(win, true)
      
      -- Ensure we're in normal mode when returning to GBoard
      vim.cmd('stopinsert')
      
      M.git_commit(commit_msg, refresh_callback)
    else
      print('No commit message provided')
    end
  end
  
  -- Set up keymaps for the commit window
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-c>', '<cmd>q<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-c>', '<Esc><cmd>q<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', '<cmd>q<CR>', { noremap = true, silent = true })
  
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Check if buffer has any text content
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_content = false
      for _, line in ipairs(lines) do
        if line:match("%S") then -- Check for non-whitespace
          has_content = true
          break
        end
      end
      
      if not has_content then
        vim.cmd('q')
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = do_commit
  })
  
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-s>', '', {
    noremap = true,
    silent = true,
    callback = do_commit
  })
  
  vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-s>', '<Esc>', {
    noremap = true,
    silent = true,
    callback = do_commit
  })
  
  vim.cmd('startinsert')
end

return M