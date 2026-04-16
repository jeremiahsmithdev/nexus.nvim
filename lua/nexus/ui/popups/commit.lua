--- Commit popup UI module
--- Handles rendering and interaction for git commit detail popups
--- Provides popups showing commit details with syntax highlighting and browser integration
---@module nexus.ui.popups.commit

local M = {}

local logger = require('nexus.logger')
local actions = require('nexus.actions')

--- Show commit details in a popup window
---@param commit_line string The line containing the commit hash
function M.show_commit_details(commit_line)
  -- Extract commit hash from line like "  a1b2c3d (HEAD -> main) commit message"
  local commit_hash = commit_line:match("%s+([a-f0-9]+)")
  
  if not commit_hash then
    logger.warn('COMMIT', 'Could not extract commit hash from line: ' .. commit_line)
    return
  end
  
  -- Get commit details using git show with notes
  local git_show_cmd = "git show --stat --notes " .. commit_hash
  local commit_details = vim.fn.systemlist(git_show_cmd)
  
  if vim.v.shell_error ~= 0 then
    logger.error('COMMIT', 'Failed to get commit details for: ' .. commit_hash)
    return
  end
  
  -- Create a new buffer for the popup
  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(popup_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(popup_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', true)
  vim.api.nvim_buf_set_option(popup_buf, 'filetype', 'git')
  
  -- Set buffer content
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, commit_details)
  
  -- Apply syntax highlighting similar to main Nexus dashboard
  M.apply_commit_popup_highlighting(popup_buf, commit_details, commit_hash)
  
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', false)
  
  -- Calculate popup size
  local max_width = 100
  local max_height = 30
  local actual_width = math.min(max_width, math.max(50, #commit_details > 0 and math.max(unpack(vim.tbl_map(function(line) return #line end, commit_details))) or 50))
  local actual_height = math.min(max_height, math.max(10, #commit_details))
  
  -- Calculate popup position (center of screen)
  local screen_width = vim.api.nvim_get_option('columns')
  local screen_height = vim.api.nvim_get_option('lines')
  local col = math.floor((screen_width - actual_width) / 2)
  local row = math.floor((screen_height - actual_height) / 2)
  
  -- Create popup window
  local popup_opts = {
    relative = 'editor',
    width = actual_width,
    height = actual_height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' Commit Details: ' .. commit_hash .. ' ',
    title_pos = 'center'
  }
  
  local popup_win = vim.api.nvim_open_win(popup_buf, true, popup_opts)
  
  -- Set popup window options  
  vim.api.nvim_win_set_option(popup_win, 'wrap', false)
  vim.api.nvim_win_set_option(popup_win, 'number', false)
  vim.api.nvim_win_set_option(popup_win, 'relativenumber', false)
  vim.api.nvim_win_set_option(popup_win, 'cursorline', true)
  vim.api.nvim_win_set_option(popup_win, 'winhighlight', 'CursorLine:Visual')
  
  -- Add virtual text hint in top right corner
  local hint_ns = vim.api.nvim_create_namespace('nexus_commit_hint')
  local hint_text = 'Enter -> file | Ctrl-O -> open'
  local hint_col = math.max(0, actual_width - #hint_text)
  vim.api.nvim_buf_set_extmark(popup_buf, hint_ns, 0, 0, {
    virt_text = {{ hint_text, 'Comment' }},
    virt_text_pos = 'overlay',
    virt_text_win_col = hint_col,
    hl_mode = 'combine'
  })
  
  -- Set up keymaps to close popup
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<Esc>', '<cmd>close<CR>', {noremap = true, silent = true})
  
  -- Set up Enter key to navigate to files or close popup
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<CR>', '', {
    noremap = true, 
    silent = true,
    callback = function()
      M.handle_enter_key(popup_buf, popup_win)
    end
  })
  
  -- Add keybinding to open commit in browser with gh
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<C-o>', '', {
    noremap = true, 
    silent = true,
    callback = function()
      -- Use action system with lazy loading to avoid circular dependency
      actions.execute('github.browse', { commit_hash = commit_hash })
    end
  })
  
  
  logger.info('COMMIT', 'Showing details for commit: ' .. commit_hash)
end

--- Handle Enter key press in commit popup
---@param popup_buf number The popup buffer number
---@param popup_win number The popup window number
function M.handle_enter_key(popup_buf, popup_win)
  local cursor = vim.api.nvim_win_get_cursor(popup_win)
  local line_num = cursor[1]
  
  -- Get the current line
  local lines = vim.api.nvim_buf_get_lines(popup_buf, line_num - 1, line_num, false)
  local current_line = lines[1]
  
  if not current_line then
    vim.cmd('close')
    return
  end
  
  -- Check if this line contains a file path (lines ending with |)
  local filename = current_line:match("^%s*(.-)%s*|")
  
  if filename and #filename > 0 then
    -- Clean up the filename (remove any leading/trailing whitespace)
    filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Get git root directory
    local git_root = require('nexus.git.root').get()
    local full_path = git_root and (git_root .. '/' .. filename) or filename
    
    -- Close the popup first
    vim.cmd('close')
    
    -- Open the file
    local edit_cmd = 'edit ' .. vim.fn.fnameescape(full_path) .. ' | set number | set signcolumn=yes'
    vim.cmd(edit_cmd)
    
    logger.info('COMMIT', 'Opened file from commit popup: ' .. filename)
  else
    -- If not on a file line, just close the popup
    vim.cmd('close')
  end
end

--- Apply syntax highlighting to commit popup
---@param buf number The buffer number
---@param lines table Array of lines to highlight
---@param commit_hash string The commit hash for context
function M.apply_commit_popup_highlighting(buf, lines, commit_hash)
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)
  
  -- Create namespaces for different highlight groups
  local commit_ns = vim.api.nvim_create_namespace('nexus_commit_popup')
  
  for i, line in ipairs(lines) do
    if line and #line > 0 then
      -- 1. Highlight commit hash (matches main dashboard highlighting)
      local hash_start, hash_end = line:find('[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+')
      if hash_start and hash_end then
        vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, hash_start - 1, { end_col = hash_end, hl_group = 'Number' })
      end
      
      -- 2. Highlight file paths in diff stats (lines ending with |)
      if line:match("|") then
        local pipe_pos = line:find("|")
        if pipe_pos then
          -- Highlight filename part
          local filename_part = line:sub(1, pipe_pos - 1):match("^%s*(.-)%s*$")
          if filename_part and #filename_part > 0 then
            vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, 0, { end_col = pipe_pos - 1, hl_group = 'String' })
          end

          -- Highlight + and - in diff stats (after the |)
          local stats_part = line:sub(pipe_pos + 1)
          for j = 1, #stats_part do
            local char = stats_part:sub(j, j)
            local actual_pos = pipe_pos + j - 1
            if char == '+' then
              vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, actual_pos, { end_col = actual_pos + 1, hl_group = 'DiagnosticOk' })
            elseif char == '-' then
              vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, actual_pos, { end_col = actual_pos + 1, hl_group = 'DiagnosticError' })
            end
          end
        end
      end
      
      -- 3. Highlight author names (usually after commit hash, before date)
      -- Look for pattern like "hash author date"
      local author_match = line:match('[a-f0-9]+ ([%w%s%-_%.]+) %d+ %w+ ago')
      if author_match then
        local author_start, author_end = line:find(author_match, nil, true)
        if author_start then
          vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, author_start - 1, { end_col = author_end, hl_group = 'Function' })
        end
      end

      -- 4. Highlight dates/time (pattern like "X minutes ago", "X days ago")
      local date_start, date_end = line:find('%d+ [%w]+ ago')
      if date_start then
        vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, date_start - 1, { end_col = date_end, hl_group = 'Comment' })
      end
      
      -- 5. Highlight summary lines (lines with file counts and insertions/deletions)
      if line:match('files? changed') or line:match('insertions?') or line:match('deletions?') then
        -- Highlight numbers in summary
        for num_start, num_end in line:gmatch('()(%d+)()') do
          vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, num_start - 1, { end_col = num_end - 1, hl_group = 'Number' })
        end

        -- Highlight keywords
        local keywords = {'files? changed', 'insertions?', 'deletions?'}
        for _, keyword in ipairs(keywords) do
          local kw_start, kw_end = line:find(keyword)
          if kw_start then
            vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, kw_start - 1, { end_col = kw_end, hl_group = 'Keyword' })
          end
        end
      end

      -- 6. Highlight commit message (usually the second or third line, not containing hash/author/date)
      if i <= 3 and not line:match('[a-f0-9]+') and not line:match('%d+ %w+ ago') and not line:match('|') and #line:gsub('^%s*(.-)%s*$', '%1') > 0 then
        vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, 0, { end_col = #line, hl_group = 'Title' })
      end

      -- 7. Highlight Notes section
      if line:match('^Notes:') then
        vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, 0, { end_col = #line, hl_group = 'Keyword' })
      elseif line:match('^%s*Reviewed by') then
        vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, 0, { end_col = #line, hl_group = 'DiagnosticOk' })
      elseif line:match('^%s*Needs attention') then
        vim.api.nvim_buf_set_extmark(buf, commit_ns, i - 1, 0, { end_col = #line, hl_group = 'DiagnosticWarn' })
      end
    end
  end
end

return M