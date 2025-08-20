local M = {}

-- Common git commands for fuzzy finding
local common_commands = {
  "status",
  "add .",
  "add -A",
  "commit -m \"\"",
  "commit --amend",
  "push",
  "push origin main",
  "push origin master", 
  "pull",
  "pull origin main",
  "pull origin master",
  "checkout -b ",
  "checkout ",
  "checkout $(git log --oneline | fzf | awk '{print $1}')",
  "branch",
  "branch -d ",
  "merge ",
  "rebase ",
  "log --oneline",
  "log -p",
  "diff",
  "diff --cached",
  "diff HEAD~1",
  "stash",
  "stash pop",
  "stash list",
  "reset --hard HEAD",
  "reset --soft HEAD~1",
  "reset HEAD ",
  "remote -v",
  "remote add origin ",
  "fetch",
  "clean -fd"
}

function M.create_git_command_window(refresh_callback)
  local width = 80
  local height = 20
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
    title = " Git Command ",
    title_pos = "center"
  }
  
  local win = vim.api.nvim_open_win(bufnr, true, opts)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', '')  -- No filetype to prevent ALL completion triggers
  
  -- Completely disable all forms of completion
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', '')
  vim.api.nvim_buf_set_option(bufnr, 'completefunc', '')  
  vim.api.nvim_buf_set_option(bufnr, 'complete', '')
  vim.api.nvim_buf_set_option(bufnr, 'completeopt', 'noinsert,noselect')
  
  -- Disable completion immediately and aggressively
  vim.schedule(function()
    vim.api.nvim_buf_call(bufnr, function()
      -- Set buffer-local variables to disable various completion systems
      vim.b[bufnr].cmp_enabled = false
      vim.b[bufnr].copilot_enabled = false
      vim.b[bufnr].completion_enable_auto_popup = false
      vim.b[bufnr].completion_enable_auto_signature = false
      vim.b[bufnr].completion_enable_auto_hover = false
      vim.b[bufnr].lsp_completion_enabled = false
      vim.b[bufnr].ale_completion_enabled = false
      vim.b[bufnr].asyncomplete_enable = false
      
      -- Set window-local options
      vim.wo.spell = false
      
      -- Override all completion-related options
      vim.opt_local.complete = ""
      vim.opt_local.completeopt = "noinsert,noselect"  
      vim.opt_local.omnifunc = ""
      vim.opt_local.completefunc = ""
      vim.opt_local.thesaurusfunc = ""
      vim.opt_local.dictionary = ""
      vim.opt_local.thesaurus = ""
      vim.opt_local.infercase = false
      vim.opt_local.spell = false
      vim.opt_local.spelllang = ""
    end)
  end)
  
  -- State for fuzzy finding
  local current_input = ""
  local filtered_commands = vim.deepcopy(common_commands)
  local selected_index = 1
  
  -- Create input area with "git " prefix
  local input_lines = {"git ", string.rep("-", width - 4)}
  for i = 1, height - 2 do
    table.insert(input_lines, "")
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, input_lines)
  
  -- Function to filter commands based on input
  local function filter_commands(input)
    if input == "" then
      return vim.deepcopy(common_commands)
    end
    
    local filtered = {}
    local input_lower = input:lower()
    
    for _, cmd in ipairs(common_commands) do
      if cmd:lower():find(input_lower, 1, true) then
        table.insert(filtered, cmd)
      end
    end
    
    return filtered
  end
  
  -- Function to update buffer content
  local function update_display()
    local lines = {}
    
    -- Input line
    table.insert(lines, "git " .. current_input)
    table.insert(lines, string.rep("-", width - 4))
    
    -- Show filtered commands
    for i, cmd in ipairs(filtered_commands) do
      local prefix = (i == selected_index) and "▶ " or "  "
      table.insert(lines, prefix .. cmd)
      
      -- Limit display to fit window
      if #lines >= height - 3 then
        break
      end
    end
    
    -- Fill remaining lines
    while #lines < height do
      table.insert(lines, "")
    end
    
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    
    -- Highlight selected item and arrow
    local ns_id = vim.api.nvim_create_namespace('gboard_git_command')
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
    
    if selected_index <= #filtered_commands and selected_index > 0 then
      -- Highlight the selected line
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'Visual', selected_index + 1, 0, -1)
      
      -- Highlight the arrow specifically
      vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'String', selected_index + 1, 0, 2)  -- "▶ "
    end
    
    -- Highlight the "git " prefix
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'Keyword', 0, 0, 4)  -- "git "
    
    -- Add virtual text descriptions for special commands
    for i, cmd in ipairs(filtered_commands) do
      local line_idx = i + 1  -- +1 for header line offset
      if cmd:match("checkout.*git log.*fzf.*awk") then
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, line_idx, 0, {
          virt_text = {{"  (fzf checkout commit)", "Comment"}},
          virt_text_pos = "eol"
        })
      end
    end
  end
  
  -- Function to show output in floating window
  local function show_output_window(title, content, is_error)
    local output_width = math.min(80, vim.api.nvim_get_option('columns') - 4)
    local lines = vim.split(content, '\n')
    local output_height = math.min(20, math.max(5, #lines + 2))
    
    local output_bufnr = vim.api.nvim_create_buf(false, true)
    
    -- Calculate position to center the window
    local win_width = vim.api.nvim_get_option('columns')
    local win_height = vim.api.nvim_get_option('lines')
    local row = math.ceil((win_height - output_height) / 2 - 1)
    local col = math.ceil((win_width - output_width) / 2)
    
    local opts = {
      style = "minimal",
      relative = "editor",
      width = output_width,
      height = output_height,
      row = row,
      col = col,
      border = "rounded",
      title = title,
      title_pos = "center"
    }
    
    local output_win = vim.api.nvim_open_win(output_bufnr, true, opts)
    
    -- Set buffer options
    vim.api.nvim_buf_set_option(output_bufnr, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(output_bufnr, 'swapfile', false)
    vim.api.nvim_buf_set_option(output_bufnr, 'modifiable', false)
    vim.api.nvim_buf_set_option(output_bufnr, 'filetype', 'gitcommit')
    
    -- Set content
    vim.api.nvim_buf_set_option(output_bufnr, 'modifiable', true)
    vim.api.nvim_buf_set_lines(output_bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(output_bufnr, 'modifiable', false)
    
    -- Highlight error content if it's an error
    if is_error then
      local ns_id = vim.api.nvim_create_namespace('gboard_git_output_error')
      for i = 0, #lines - 1 do
        vim.api.nvim_buf_add_highlight(output_bufnr, ns_id, 'DiagnosticError', i, 0, -1)
      end
    end
    
    -- Set up keymaps to close the window
    for _, key in ipairs({'<Esc>', 'q', '<CR>', '<C-c>'}) do
      vim.api.nvim_buf_set_keymap(output_bufnr, 'n', key, '<cmd>q<CR>', { noremap = true, silent = true })
    end
    
    -- Add help text
    local help_text = "Press q, <Esc>, or <Enter> to close"
    local help_ns = vim.api.nvim_create_namespace('gboard_git_output_help')
    vim.api.nvim_buf_set_extmark(output_bufnr, help_ns, #lines, 0, {
      virt_text = {{help_text, "Comment"}},
      virt_text_pos = "eol"
    })
  end
  
  -- Function to show git log for checkout selection
  local function show_checkout_selection()
    -- Get git log
    local log_result = vim.fn.system("git log --oneline -20")  -- Limit to 20 commits
    if vim.v.shell_error ~= 0 then
      show_output_window(" Git Error ", "Failed to get git log:\n" .. log_result, true)
      return
    end
    
    -- Parse commits
    local commits = {}
    for line in log_result:gmatch('[^\r\n]+') do
      table.insert(commits, line)
    end
    
    if #commits == 0 then
      show_output_window(" Git Info ", "No commits found", false)
      return
    end
    
    -- Update the current window to show commit selection
    current_input = ""
    filtered_commands = commits
    local all_commits = vim.deepcopy(commits)  -- Keep original list for filtering
    selected_index = 1
    
    -- Function to filter commits based on input
    local function filter_commits(input)
      if input == "" then
        return vim.deepcopy(all_commits)
      end
      
      local filtered = {}
      local input_lower = input:lower()
      
      for _, commit in ipairs(all_commits) do
        if commit:lower():find(input_lower, 1, true) then
          table.insert(filtered, commit)
        end
      end
      
      return filtered
    end
    
    -- Update display function for commits
    local function update_commit_display()
      local lines = {}
      
      -- Input line (just the current input, no prefix)
      table.insert(lines, current_input)
      table.insert(lines, string.rep("-", width - 4))
      
      -- Show filtered commits
      for i, commit in ipairs(filtered_commands) do
        local prefix = (i == selected_index) and "▶ " or "  "
        table.insert(lines, prefix .. commit)
        
        if #lines >= height - 3 then
          break
        end
      end
      
      -- Fill remaining lines
      while #lines < height do
        table.insert(lines, "")
      end
      
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      
      -- Highlight selected item and arrow
      local ns_id = vim.api.nvim_create_namespace('gboard_git_command')
      vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
      
      if selected_index <= #filtered_commands and selected_index > 0 then
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'Visual', selected_index + 1, 0, -1)
        vim.api.nvim_buf_add_highlight(bufnr, ns_id, 'String', selected_index + 1, 0, 2)
      end
      
      -- Add virtual text "Filter: " only when input is empty
      if current_input == "" then
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, 0, 0, {
          virt_text = {{"Filter: ", "Comment"}},
          virt_text_pos = "overlay"
        })
      end
    end
    
    -- Function to sync input from buffer for commit filtering
    local function sync_commit_input()
      local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
      if line ~= current_input then
        current_input = line
        filtered_commands = filter_commits(current_input)
        selected_index = math.min(selected_index, math.max(1, #filtered_commands))
        update_commit_display()
      end
    end
    
    -- Navigation for normal mode only (j/k)
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'j', '', {
      noremap = true, silent = true,
      callback = function()
        if selected_index < #filtered_commands then
          selected_index = selected_index + 1
          update_commit_display()
        end
      end
    })
    
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'k', '', {
      noremap = true, silent = true,
      callback = function()
        if selected_index > 1 then
          selected_index = selected_index - 1
          update_commit_display()
        end
      end
    })
    
    -- Navigation for both modes (arrows and Ctrl-n/Ctrl-p)
    for _, mode in ipairs({'n', 'i'}) do
      -- Down navigation (Down arrow, Ctrl-n)
      for _, key in ipairs({'<Down>', '<C-n>'}) do
        vim.api.nvim_buf_set_keymap(bufnr, mode, key, '', {
          noremap = true, silent = true,
          callback = function()
            if selected_index < #filtered_commands then
              selected_index = selected_index + 1
              update_commit_display()
            end
          end
        })
      end
      
      -- Up navigation (Up arrow, Ctrl-p)  
      for _, key in ipairs({'<Up>', '<C-p>'}) do
        vim.api.nvim_buf_set_keymap(bufnr, mode, key, '', {
          noremap = true, silent = true,
          callback = function()
            if selected_index > 1 then
              selected_index = selected_index - 1
              update_commit_display()
            end
          end
        })
      end
      
      -- Enter to checkout selected commit
      vim.api.nvim_buf_set_keymap(bufnr, mode, '<CR>', '', {
        noremap = true, silent = true,
        callback = function()
          if selected_index <= #filtered_commands and filtered_commands[selected_index] then
            local commit_line = filtered_commands[selected_index]
            local hash = commit_line:match("^([%w]+)")
            if hash then
              vim.api.nvim_win_close(win, true)
              vim.cmd('stopinsert')
              
              local checkout_result = vim.fn.system("git checkout " .. hash)
              if vim.v.shell_error == 0 then
                show_output_window(" Git Checkout Success ", "Checked out: " .. commit_line, false)
              else
                show_output_window(" Git Checkout Error ", "Failed to checkout " .. hash .. ":\n" .. checkout_result, true)
              end
              
              if refresh_callback then
                refresh_callback()
              end
            end
          end
        end
      })
    end
    
    -- Set up auto-update on text change for filtering
    vim.api.nvim_create_autocmd({"TextChangedI", "TextChanged"}, {
      buffer = bufnr,
      callback = function()
        sync_commit_input()
      end
    })
    
    -- Restrict cursor to first line only
    vim.api.nvim_create_autocmd({"CursorMovedI", "CursorMoved"}, {
      buffer = bufnr,
      callback = function()
        local cursor = vim.api.nvim_win_get_cursor(win)
        local row, col = cursor[1], cursor[2]
        
        -- Keep cursor on first line
        if row ~= 1 then
          vim.api.nvim_win_set_cursor(win, {1, col})
        end
      end
    })
    
    -- Change window title to "Git Checkout"
    vim.api.nvim_win_set_config(win, {
      title = " Git Checkout ",
      title_pos = "center"
    })
    
    update_commit_display()
    
    -- Position cursor at beginning of input line and start in insert mode
    vim.api.nvim_win_set_cursor(win, {1, 0})
    vim.cmd('startinsert')
  end
  
  -- Function to execute git command
  local function execute_command(cmd)
    -- Special handling for fzf checkout command
    if cmd:match("checkout.*git log.*fzf.*awk") then
      show_checkout_selection()
      return
    end
    
    -- Special handling for commit --amend
    if cmd == "commit --amend" then
      vim.api.nvim_win_close(win, true)
      vim.cmd('stopinsert')
      
      -- Open commit amend window instead of executing directly
      local operations = require('nexus.git.operations')
      operations.create_commit_amend_window(refresh_callback)
      return
    end
    
    vim.api.nvim_win_close(win, true)
    
    -- Ensure we're in normal mode when returning to Nexus
    vim.cmd('stopinsert')
    
    -- Execute git command
    local full_cmd = "git " .. cmd
    local result = vim.fn.system(full_cmd)
    local clean_result = result:gsub("\n$", "")
    
    -- Show output in floating window
    if vim.v.shell_error == 0 then
      if clean_result ~= "" then
        show_output_window(" Git Output: " .. full_cmd .. " ", clean_result, false)
      else
        -- For commands with no output, show brief success message
        show_output_window(" Git Success ", "Command executed successfully: " .. full_cmd, false)
      end
    else
      show_output_window(" Git Error ", "Command: " .. full_cmd .. "\n\nError:\n" .. clean_result, true)
    end
    
    -- Refresh Nexus if callback provided
    if refresh_callback then
      refresh_callback()
    end
  end
  
  -- Function to sync input from buffer
  local function sync_input_from_buffer()
    local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
    if line:sub(1, 4) == "git " then
      local new_input = line:sub(5)
      if new_input ~= current_input then
        current_input = new_input
        filtered_commands = filter_commands(current_input)
        selected_index = math.min(selected_index, math.max(1, #filtered_commands))
        update_display()
      end
    end
  end
  
  -- Set up keymaps for both normal and insert mode
  -- Exit keymaps
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-c>', '<cmd>q<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-c>', '<Esc><cmd>q<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>', '<cmd>q<CR>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', '<cmd>q<CR>', { noremap = true, silent = true })
  
  -- Navigation (normal mode only)
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'j', '', {
    noremap = true,
    silent = true,
    callback = function()
      if selected_index < #filtered_commands then
        selected_index = selected_index + 1
        update_display()
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'k', '', {
    noremap = true,
    silent = true,
    callback = function()
      if selected_index > 1 then
        selected_index = selected_index - 1
        update_display()
      end
    end
  })
  
  -- Navigation with arrows and Ctrl-n/Ctrl-p (both modes)
  for _, mode in ipairs({'n', 'i'}) do
    -- Down navigation (Down arrow and Ctrl-n)
    for _, key in ipairs({'<Down>', '<C-n>'}) do
      vim.api.nvim_buf_set_keymap(bufnr, mode, key, '', {
        noremap = true,
        silent = true,
        callback = function()
          if selected_index < #filtered_commands then
            selected_index = selected_index + 1
            update_display()
          end
        end
      })
    end
    
    -- Up navigation (Up arrow and Ctrl-p)
    for _, key in ipairs({'<Up>', '<C-p>'}) do
      vim.api.nvim_buf_set_keymap(bufnr, mode, key, '', {
        noremap = true,
        silent = true,
        callback = function()
          if selected_index > 1 then
            selected_index = selected_index - 1
            update_display()
          end
        end
      })
    end
  end
  
  -- Execute command (both modes)
  for _, mode in ipairs({'n', 'i'}) do
    vim.api.nvim_buf_set_keymap(bufnr, mode, '<CR>', '', {
      noremap = true,
      silent = true,
      callback = function()
        sync_input_from_buffer()
        if #filtered_commands > 0 and filtered_commands[selected_index] then
          execute_command(filtered_commands[selected_index])
        elseif current_input ~= "" then
          execute_command(current_input)
        end
      end
    })
  end
  
  -- Tab completion to select current suggestion (override default completion)
  for _, mode in ipairs({'n', 'i'}) do
    vim.api.nvim_buf_set_keymap(bufnr, mode, '<Tab>', '', {
      noremap = true,
      silent = true,
      callback = function()
        if #filtered_commands > 0 and filtered_commands[selected_index] then
          current_input = filtered_commands[selected_index]
          vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {"git " .. current_input})
          filtered_commands = filter_commands(current_input)
          update_display()
          -- Position cursor at end of input
          vim.api.nvim_win_set_cursor(win, {1, 4 + #current_input})
        end
      end
    })
  end
  
  -- Override ALL possible completion triggers to prevent popups
  local completion_keys = {
    '<C-x><C-o>', '<C-x><C-n>', '<C-x><C-p>', '<C-x><C-l>', '<C-x><C-f>', 
    '<C-x><C-k>', '<C-x><C-t>', '<C-x><C-i>', '<C-x><C-]>', '<C-x><C-d>',
    '<C-x><C-v>', '<C-x><C-u>', '<C-x><C-s>', '<C-o>', '<C-x>', '<C-Space>',
    '<C-@>'  -- Some completion plugins use Ctrl-Space
  }
  
  for _, key in ipairs(completion_keys) do
    vim.api.nvim_buf_set_keymap(bufnr, 'i', key, '', { noremap = true, silent = true })
  end
  
  -- Also block any autocommands that might trigger completion
  vim.api.nvim_create_autocmd({"InsertCharPre", "TextChangedI", "TextChangedP"}, {
    buffer = bufnr,
    callback = function()
      -- Prevent any completion popup
      if vim.fn.pumvisible() == 1 then
        vim.cmd('silent! pclose')
        return true
      end
    end
  })
  
  -- Set up auto-update on text change
  vim.api.nvim_create_autocmd({"TextChangedI", "TextChanged"}, {
    buffer = bufnr,
    callback = function()
      sync_input_from_buffer()
    end
  })
  
  -- Restrict cursor to first line and after "git "
  vim.api.nvim_create_autocmd({"CursorMovedI", "CursorMoved"}, {
    buffer = bufnr,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(win)
      local row, col = cursor[1], cursor[2]
      
      -- Keep cursor on first line
      if row ~= 1 then
        vim.api.nvim_win_set_cursor(win, {1, col})
      end
      
      -- Keep cursor after "git " (position 4)
      if col < 4 then
        vim.api.nvim_win_set_cursor(win, {1, 4})
      end
    end
  })
  
  -- Initial display
  update_display()
  
  -- Make buffer editable and start in insert mode
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  
  -- Position cursor after "git " and start insert mode
  vim.api.nvim_win_set_cursor(win, {1, 4})
  vim.cmd('startinsert')
end

return M