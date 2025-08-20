local M = {}
local logger = require('gboard.logger')

local git_operations = require('gboard.git.operations')
local git_command = require('gboard.git.command')
local tmux = require('gboard.tmux')

function M.setup_keymaps(buf, files, config, is_git_repo, render_callback)
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
        vim.cmd('Telescope find_files')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Recently opened files") then
        vim.cmd('Telescope oldfiles')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Find word") then
        vim.cmd('Telescope live_grep')
      elseif config.show_dashboard_buttons and current_line and current_line:match("New file") then
        vim.cmd('enew')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Bookmarks") then
        vim.cmd('Telescope marks')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Restore session") then
        -- Basic session restore - could be enhanced with session manager
        if vim.fn.filereadable('Session.vim') == 1 then
          vim.cmd('source Session.vim')
        else
          logger.warn('SESSION', 'No session file found')
        end
      -- Check if it's a Claude conversation line (format: " N. ...")
      elseif config.show_claude_conversations and current_line and current_line:match("^ %d+%.") then
        -- Extract session ID and send /resume command
        local claude = require('gboard.claude')
        local conversations = claude.get_claude_conversations(config)
        local line_index = current_line:match("^ (%d+)%.")
        if line_index then
          local conv_index = tonumber(line_index)
          if conv_index and conversations[conv_index] then
            tmux.send_resume_to_claude(conversations[conv_index].session_id)
          end
        end
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
          if git_root then
            local full_path = git_root .. '/' .. filename
            vim.cmd('edit ' .. vim.fn.fnameescape(full_path))
            vim.cmd('set number')
            vim.cmd('set signcolumn=yes')
          else
            vim.cmd('edit ' .. vim.fn.fnameescape(filename))
            vim.cmd('set number')
            vim.cmd('set signcolumn=yes')
          end
        end
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.smart_quit()
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.smart_quit()
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
          local git_status = require('gboard.git.status')
          local files = git_status.parse_git_status()
          render_callback(buf, files)
        end)
      end
    })
  end
end

function M.smart_quit()
  -- Count non-empty, listed buffers
  local listed_bufs = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_option(b, 'buflisted') then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= '' or vim.api.nvim_buf_get_option(b, 'modified') then
        listed_bufs = listed_bufs + 1
      end
    end
  end
  
  if listed_bufs <= 1 then
    vim.cmd('qa!')
  else
    vim.cmd('q')
  end
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
        local git_status = require('gboard.git.status')
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
        local git_status = require('gboard.git.status')
        local files = git_status.parse_git_status()
        render_callback(buf, files)
      end)
    end
  end
end

return M