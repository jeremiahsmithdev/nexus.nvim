local M = {}
local logger = require('nexus.logger')

local git_operations = require('nexus.git.operations')
local git_command = require('nexus.git.command')
local tmux = require('nexus.tmux')


function M.setup_keymaps(buf, files, config, is_git_repo, render_callback, section_ranges)
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local line_num = cursor[1]
      
      -- Get all lines in the buffer
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local current_line = lines[line_num]
      
      -- Check if it's a dashboard button line
      if config.show_dashboard_buttons and current_line and current_line:match("Find file") then
        M.handle_dashboard_action(config, 'Telescope find_files')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Recently opened files") then
        M.handle_dashboard_action(config, 'Telescope oldfiles')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Find word") then
        M.handle_dashboard_action(config, 'Telescope live_grep')
      elseif config.show_dashboard_buttons and current_line and current_line:match("New file") then
        M.handle_dashboard_action(config, 'enew')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Bookmarks") then
        M.handle_dashboard_action(config, 'Telescope marks')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Restore session") then
        -- Basic session restore - could be enhanced with session manager
        if vim.fn.filereadable('Session.vim') == 1 then
          M.handle_dashboard_action(config, 'source Session.vim')
        else
          logger.warn('SESSION', 'No session file found')
        end
      -- Check if it's a Claude conversation line (format: " N. ...")
      elseif config.show_claude_conversations and current_line and current_line:match("^ %d+%.") then
        -- Extract session ID and send /resume command
        local claude = require('nexus.claude')
        local conversations = claude.get_claude_conversations(config)
        local line_index = current_line:match("^ (%d+)%.")
        if line_index then
          local conv_index = tonumber(line_index)
          if conv_index and conversations[conv_index] then
            tmux.send_resume_to_claude(conversations[conv_index].session_id)
          end
        end
      -- Check if it's a commit line (recent commits section)
      elseif is_git_repo and current_line and current_line:match("%s+[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+") then
        M.show_commit_details(current_line)
      -- Check if it's a git status line (only in git repos)
      elseif is_git_repo and current_line and current_line:match("%s*  [MADRCU?][MADRCU?]? ") then
        -- This is a git status line - extract filename and open file
        local filename = current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%+") or 
                        current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%-") or
                        current_line:match("%s*  [MADRCU?][MADRCU?]? (.+)$")
        if filename then
          filename = filename:gsub("%s+$", "")
        end
        
        if filename then
          filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
          
          local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
          local full_path = git_root and (git_root .. '/' .. filename) or filename
          local edit_cmd = 'edit ' .. vim.fn.fnameescape(full_path) .. ' | set number | set signcolumn=yes'
          M.handle_dashboard_action(config, edit_cmd)
        end
      end
    end
  })
  
  -- Set up async quit keymaps
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.async_quit()
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.async_esc()
    end
  })
  
  -- Calculate logo section end (just logo, NOT buttons)
  local logo = require('nexus.ui.logo')
  local logo_lines = logo.get_neovim_logo(config)
  local logo_end_line = #logo_lines  -- Logo only
  
  -- Custom navigation that skips non-actionable lines
  local function move_to_next_actionable(direction)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    local step = direction > 0 and 1 or -1
    
    for i = current_line + step, direction > 0 and #lines or 1, step do
      if lines[i] then
        -- Skip logo section completely
        if i <= logo_end_line then
          goto continue
        end
        
        -- Skip keyboard shortcuts section completely
        if section_ranges and section_ranges.keyboard_shortcuts then
          local shortcuts_range = section_ranges.keyboard_shortcuts
          if i >= shortcuts_range.start_line and i <= shortcuts_range.end_line then
            goto continue
          end
        end
        
        -- Skip empty lines
        if lines[i]:match("^%s*$") then
          goto continue
        end
        
        -- Skip section titles (lines ending with colon)
        if lines[i]:match(":$") then
          goto continue
        end
        
        -- This is an actionable line
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return
      end
      ::continue::
    end
  end
  
  -- Override j/k to jump between actionable lines
  vim.api.nvim_buf_set_keymap(buf, 'n', 'j', '', {
    noremap = true,
    silent = true,
    callback = function() move_to_next_actionable(1) end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'k', '', {
    noremap = true,
    silent = true,
    callback = function() move_to_next_actionable(-1) end
  })
  
  -- Override gg to go to first actionable line instead of top of buffer
  vim.api.nvim_buf_set_keymap(buf, 'n', 'gg', '', {
    noremap = true,
    silent = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for i = logo_end_line + 1, #lines do
        if lines[i] then
          -- Skip keyboard shortcuts section
          if section_ranges and section_ranges.keyboard_shortcuts then
            local shortcuts_range = section_ranges.keyboard_shortcuts
            if i >= shortcuts_range.start_line and i <= shortcuts_range.end_line then
              goto continue
            end
          end
          
          -- Skip empty lines
          if lines[i]:match("^%s*$") then
            goto continue
          end
          
          -- Skip section titles (lines ending with colon)
          if lines[i]:match(":$") then
            goto continue
          end
          
          -- This is an actionable line
          vim.api.nvim_win_set_cursor(0, {i, 0})
          return
        end
        ::continue::
      end
    end
  })
  
  -- Git-specific keymaps (only in git repositories)
  if is_git_repo then
    vim.api.nvim_buf_set_keymap(buf, 'n', 'r', '', {
      noremap = true,
      silent = true,
      callback = function()
        render_callback(buf)
      end
    })
    
    vim.api.nvim_buf_set_keymap(buf, 'n', 'a', '', {
      noremap = true,
      silent = true,
      callback = function()
        M.handle_git_add(buf, render_callback)
      end
    })
    
    vim.api.nvim_buf_set_keymap(buf, 'n', 'u', '', {
      noremap = true,
      silent = true,
      callback = function()
        M.handle_git_unstage(buf, render_callback)
      end
    })
    
    vim.api.nvim_buf_set_keymap(buf, 'n', 'c', '', {
      noremap = true,
      silent = true,
      callback = function()
        git_operations.create_commit_window(function()
          render_callback(buf)
        end)
      end
    })
    
    vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>g', '', {
      noremap = true,
      silent = true,
      callback = function()
        git_command.create_git_command_window(function()
          -- Re-parse git status after command and refresh
          local git_status = require('nexus.git.status')
          local files = git_status.parse_git_status()
          render_callback(buf, files)
        end)
      end
    })
  end
end

-- Async quit function - only quits when Nexus is the only real buffer
function M.async_quit()
  -- Run buffer check asynchronously to avoid blocking
  vim.schedule(function()
    local current_buf = vim.api.nvim_get_current_buf()
    local real_bufs = 0
    
    -- Quick count of other real buffers
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_option(b, 'buflisted') then
        -- Skip current Nexus buffer
        if b == current_buf then
          goto continue
        end
        
        -- Skip scratch buffers and count real ones
        local buftype = vim.api.nvim_buf_get_option(b, 'buftype')
        if buftype == '' then
          local name = vim.api.nvim_buf_get_name(b)
          if name ~= '' or vim.api.nvim_buf_get_option(b, 'modified') then
            real_bufs = real_bufs + 1
            break -- Early exit once we find any other real buffer
          end
        end
      end
      ::continue::
    end
    
    -- Only quit if Nexus is the only buffer
    if real_bufs == 0 then
      vim.cmd('qa!')
    else
      -- Fallback to default q behavior - simulate default keymap
      vim.cmd('normal! \\<C-\\>\\<C-N>q')
    end
  end)
end

-- Async esc function
function M.async_esc()
  -- Run buffer check asynchronously 
  vim.schedule(function()
    local current_buf = vim.api.nvim_get_current_buf()
    local real_bufs = 0
    
    -- Quick count of other real buffers
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_option(b, 'buflisted') then
        -- Skip current Nexus buffer
        if b == current_buf then
          goto continue
        end
        
        -- Skip scratch buffers and count real ones  
        local buftype = vim.api.nvim_buf_get_option(b, 'buftype')
        if buftype == '' then
          local name = vim.api.nvim_buf_get_name(b)
          if name ~= '' or vim.api.nvim_buf_get_option(b, 'modified') then
            real_bufs = real_bufs + 1
            break -- Early exit once we find any other real buffer
          end
        end
      end
      ::continue::
    end
    
    -- Only quit if Nexus is the only buffer
    if real_bufs == 0 then
      vim.cmd('qa!')
    else
      -- Fallback to default Esc behavior - usually does nothing in normal mode
      vim.cmd('normal! \\<Esc>')
    end
  end)
end

function M.handle_git_add(buf, render_callback)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  
  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  -- Check if it's a git status line
  if current_line and current_line:match("%s*  [MADRCU?][MADRCU?]? ") then
    local filename = current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%+") or 
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%-") or
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.+)$")
    if filename then
      filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
      
      git_operations.git_add_file(filename, function()
        -- Re-parse git status after change and pass to render
        local git_status = require('nexus.git.status')
        local files = git_status.parse_git_status()
        render_callback(buf, files)
      end)
    end
  end
end

function M.handle_git_unstage(buf, render_callback)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  
  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  -- Check if it's a git status line
  if current_line and current_line:match("%s*  [MADRCU?][MADRCU?]? ") then
    local filename = current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%+") or 
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%-") or
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.+)$")
    if filename then
      filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
      
      git_operations.git_unstage_file(filename, function()
        -- Re-parse git status after change and pass to render
        local git_status = require('nexus.git.status')
        local files = git_status.parse_git_status()
        render_callback(buf, files)
      end)
    end
  end
end

function M.show_commit_details(commit_line)
  -- Extract commit hash from line like "  a1b2c3d (HEAD -> main) commit message"
  local commit_hash = commit_line:match("%s+([a-f0-9]+)")
  
  if not commit_hash then
    logger.warn('COMMIT', 'Could not extract commit hash from line: ' .. commit_line)
    return
  end
  
  -- Get commit details using git show
  local git_show_cmd = "git show --stat --pretty=format:'%C(yellow)%h%Creset %C(blue)%an%Creset %C(green)%ar%Creset%n%C(white)%s%Creset%n%n%b' " .. commit_hash
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
  
  -- Set buffer content
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, commit_details)
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
  
  -- Set up keymaps to close popup
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<Esc>', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<CR>', '<cmd>close<CR>', {noremap = true, silent = true})
  
  logger.info('COMMIT', 'Showing details for commit: ' .. commit_hash)
end

function M.handle_dashboard_action(config, command)
  -- The key difference is handled in buffer creation (persistent vs non-persistent)
  -- When keep_open_after_startup = true, Nexus buffer is created as persistent
  -- When keep_open_after_startup = false, Nexus buffer gets wiped when replaced
  vim.cmd(command)
end

return M