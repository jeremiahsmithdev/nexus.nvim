local M = {}
local logger = require('nexus.logger')
local actions = require('nexus.actions')

-- Section-specific keymap handlers
local todo_keymaps = require('nexus.keymaps.todo')
local linear_keymaps = require('nexus.keymaps.linear')
local dashboard_keymaps = require('nexus.keymaps.dashboard')
local git_keymaps = require('nexus.keymaps.git')
local claude_keymaps = require('nexus.keymaps.claude')

-- Keep legacy imports for existing functionality
local linear_component = require('nexus.render.components.linear')
local linear_state = require('nexus.state.linear')
local todo_component = require('nexus.render.components.todo')
local logo = require('nexus.ui.logo')
local claude = require('nexus.claude')
local tmux = require('nexus.tmux')
local git_command = require('nexus.git.command')
local git_state = require('nexus.state.git')


--- Determine which section the cursor is currently in
---@param lines table All buffer lines
---@param line_num number Current cursor line number
---@param config table Nexus configuration
---@return string section_name The section the cursor is in
function M.get_current_section(lines, line_num, config)
  local current_line = lines[line_num]
  if not current_line then return "unknown" end
  
  -- Look backwards from current line to find the section header
  for i = line_num, 1, -1 do
    local line = lines[i]
    if line then
      -- Check for section headers (end with colon)
      if line:match("^%s*Linear Issues:%s*$") then
        return "linear"
      elseif line:match("^%s*Todo:%s*$") then
        return "todo"
      elseif line:match("^%s*Recent Commits:%s*$") then
        return "commits"
      elseif line:match("^%s*Git Status:%s*$") then
        return "git_status"
      elseif line:match("^%s*Dashboard:%s*$") or line:match("Find file") or line:match("Recently opened files") then
        return "dashboard"
      elseif line:match("^%s*Keyboard Shortcuts:%s*$") then
        return "shortcuts"
      end
    end
  end
  
  -- If no section header found, determine by line content
  if current_line:match("Find file") or current_line:match("Recently opened files") or 
     current_line:match("Find word") or current_line:match("New file") or
     current_line:match("Bookmarks") or current_line:match("Restore session") then
    return "dashboard"
  elseif current_line:match("^ %d+%.") then
    return "claude_conversations"
  elseif current_line:match("%s+[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+") then
    return "commits"
  elseif current_line:match("^%s*[MADRCU?][MADRCU?]? ") then
    return "git_status"
  elseif config.linear and config.linear.enabled then
    local linear_component = require('nexus.render.components.linear')
    local is_issue, _ = linear_component.is_linear_issue_line(current_line)
    if is_issue then
      return "linear"
    end
  end
  
  if config.show_todos then
    local todo_component = require('nexus.render.components.todo')
    if todo_component.is_todo_line(current_line) then
      return "todo"
    end
  end
  
  return "unknown"
end

--- Handle Enter key press in Nexus buffer
function M.handle_enter_key(buf, files, config, is_git_repo, render_callback)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  
  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  if not current_line then return end
  
  -- Determine which section we're in
  local section = M.get_current_section(lines, line_num, config)
  
  -- Handle based on section
  if section == "dashboard" then
    dashboard_keymaps.handle_enter(current_line, config)
    
  elseif section == "claude_conversations" then
    claude_keymaps.handle_enter(current_line, config)
    
  elseif section == "commits" then
    git_keymaps.handle_enter_commits(current_line)
    
  elseif section == "git_status" and is_git_repo then
    git_keymaps.handle_enter_git_status(current_line, config)
    
  elseif section == "linear" then
    linear_keymaps.handle_enter(current_line, config, buf, render_callback)
    
  elseif section == "todo" then
    todo_keymaps.handle_enter(current_line, line_num, config)
    
  else
    logger.debug('KEYMAP', 'Enter key pressed in unknown section', { 
      section = section, 
      line = current_line 
    })
  end
end

--- Handle Enter key in dashboard section
function M.handle_enter_dashboard(current_line, config)
  if current_line:match("Find file") then
    M.handle_dashboard_action(config, 'Telescope find_files')
  elseif current_line:match("Recently opened files") then
    M.handle_dashboard_action(config, 'Telescope oldfiles')
  elseif current_line:match("Find word") then
    M.handle_dashboard_action(config, 'Telescope live_grep')
  elseif current_line:match("New file") then
    M.handle_dashboard_action(config, 'enew')
  elseif current_line:match("Bookmarks") then
    M.handle_dashboard_action(config, 'Telescope marks')
  elseif current_line:match("Restore session") then
    if vim.fn.filereadable('Session.vim') == 1 then
      M.handle_dashboard_action(config, 'source Session.vim')
    else
      logger.warn('SESSION', 'No session file found')
    end
  end
end

--- Handle Enter key in Claude conversations section
function M.handle_enter_claude_conversations(current_line, config)
  local conversations = claude.get_claude_conversations(config)
  local line_index = current_line:match("^ (%d+)%.")
  if line_index then
    local conv_index = tonumber(line_index)
    if conv_index and conversations[conv_index] then
      tmux.send_resume_to_claude(conversations[conv_index].session_id)
    end
  end
end

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
    M.handle_dashboard_action(config, edit_cmd)
  end
end

--- Handle Enter key in Linear section
function M.handle_enter_linear(current_line, config, buf, render_callback)
  if current_line:match("No API key found") or current_line:match("Invalid API key") then
    logger.info('LINEAR', 'Triggering API key setup')
    M.setup_linear_api_key(config, function()
      render_callback(buf)
    end)
    return
  end
  
  local is_issue, identifier = linear_component.is_linear_issue_line(current_line)
  if is_issue and identifier then
    local issues = linear_state.get_issues()
    local issue = linear_component.get_issue_from_line(current_line, issues)
    if issue and issue.url then
      logger.info('LINEAR', 'Opening Linear issue', {
        identifier = issue.identifier,
        url = issue.url
      })
      M.show_linear_issue_details(issue, config)
    else
      logger.warn('LINEAR', 'Could not find issue data', {
        identifier = identifier,
        issue = issue
      })
    end
  end
end

--- Handle Enter key in todo section
function M.handle_enter_todo(current_line, line_num, config)
  local todo_id = todo_component.get_todo_id_from_line_num(line_num)
  if todo_id then
    local todo = todo_state.get_todo_by_id(todo_id)
    if todo then
      M.show_todo_details(todo, config)
    end
  end
end

function M.setup_keymaps(buf, files, config, is_git_repo, render_callback, section_ranges)
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.handle_enter_key(buf, files, config, is_git_repo, render_callback)
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
  
  -- Note: <Esc> keymap removed to prevent accidental quitting
  
  -- Calculate logo section end (just logo, NOT buttons)
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
  
  -- Override gg to go to first actionable line but show logo in viewport
  vim.api.nvim_buf_set_keymap(buf, 'n', 'gg', '', {
    noremap = true,
    silent = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local target_line = nil
      
      -- Find the first actionable line
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
          
          -- This is the first actionable line
          target_line = i
          break
        end
        ::continue::
      end
      
      if target_line then
        -- First, scroll to show the top of the buffer (logo)
        vim.cmd('normal! gg')
        
        -- Then set cursor to the actionable line
        vim.api.nvim_win_set_cursor(0, {target_line, 0})
      else
        -- Fallback: just go to top if no actionable line found
        vim.cmd('normal! gg')
      end
    end
  })
  
  -- Section navigation with { and } - jump to first actionable line of previous/next section
  vim.api.nvim_buf_set_keymap(buf, 'n', '{', '', {
    noremap = true,
    silent = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local current_line = vim.api.nvim_win_get_cursor(0)[1]
      local current_section = M.get_current_section(lines, current_line, config)
      
      -- Find previous section header
      for i = current_line - 1, 1, -1 do
        local line = lines[i]
        if line and line:match("^%s*[^%s].*:%s*$") then
          local section = M.get_current_section(lines, i, config)
          if section ~= current_section then
            -- Found different section, move to its first actionable line
            vim.api.nvim_win_set_cursor(0, {i + 1, 0})
            move_to_next_actionable(1)
            return
          end
        end
      end
      -- No previous section, go to top
      vim.cmd('normal! gg')
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', '}', '', {
    noremap = true,
    silent = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local current_line = vim.api.nvim_win_get_cursor(0)[1]
      local current_section = M.get_current_section(lines, current_line, config)
      
      -- Find next section header
      for i = current_line + 1, #lines do
        local line = lines[i]
        if line and line:match("^%s*[^%s].*:%s*$") then
          local section = M.get_current_section(lines, i, config)
          if section ~= current_section then
            -- Found different section, move to its first actionable line
            vim.api.nvim_win_set_cursor(0, {i + 1, 0})
            move_to_next_actionable(1)
            return
          end
        end
      end
      -- No next section, go to end
      vim.cmd('normal! G')
    end
  })
  
  -- Git-specific keymaps (only in git repositories)
  if is_git_repo then
    vim.api.nvim_buf_set_keymap(buf, 'n', 'r', '', {
      noremap = true,
      silent = true,
      callback = function()
        -- Refresh Linear data if enabled
        if config.linear and config.linear.enabled then
                  linear_state.refresh_data(config)
        end
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
        M.handle_c_key(buf, render_callback, config)
      end
    })
    
    vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>g', '', {
      noremap = true,
      silent = true,
      callback = function()
        git_command.create_git_command_window(function()
          -- Update git status through state system and refresh
          git_state.update_git_status(true) -- force refresh
          local files = git_state.get_git_status()
          render_callback(buf, files)
        end)
      end
    })
    
    -- Todo-specific keymaps (available in git repos since todos are stored there)
    if config.show_todos then
      vim.api.nvim_buf_set_keymap(buf, 'n', 'e', '', {
        noremap = true,
        silent = true,
        callback = function()
          M.handle_e_key(buf, render_callback, config)
        end
      })
      
      vim.api.nvim_buf_set_keymap(buf, 'n', 'd', '', {
        noremap = true,
        silent = true,
        callback = function()
          M.handle_d_key(buf, render_callback, config)
        end
      })
      
      vim.api.nvim_buf_set_keymap(buf, 'n', 'D', '', {
        noremap = true,
        silent = true,
        callback = function()
          M.handle_D_key(buf, render_callback, config)
        end
      })
    end
  end
  
  -- Linear-specific keymaps (section-aware)
  if config.linear and config.linear.enabled then
    vim.api.nvim_buf_set_keymap(buf, 'n', 's', '', {
      noremap = true,
      silent = true,
      callback = function()
        M.handle_linear_status_update(buf, render_callback, config)
      end
    })
    
    vim.api.nvim_buf_set_keymap(buf, 'n', 'p', '', {
      noremap = true,
      silent = true,
      callback = function()
        M.handle_linear_project_selection(buf, render_callback, config)
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
      -- Close the Nexus buffer when other buffers exist
      vim.cmd('bdelete')
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
      -- Close the Nexus buffer when other buffers exist
      vim.cmd('bdelete')
    end
  end)
end

function M.handle_git_add(buf, render_callback)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  
  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  logger.debug('GIT_ADD', string.format('Cursor at line %d: "%s"', line_num, current_line or 'nil'))
  
  -- Check if it's a git status line
  if current_line and current_line:match("%s*  [MADRCU?][MADRCU?]? ") then
    local filename = current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%+") or 
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%-") or
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.+)$")
    if filename then
      filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
      
      -- Use action system with lazy loading to avoid circular dependency
      actions.execute('git.add', {
        filename = filename,
        refresh_callback = function()
          -- Update git status through state system and refresh
          git_state.update_git_status(true) -- force refresh
          local files = git_state.get_git_status()
          render_callback(buf, files)
        end
      })
    end
  end
end

function M.handle_git_unstage(buf, render_callback)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  
  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  logger.debug('GIT_UNSTAGE', string.format('Cursor at line %d: "%s"', line_num, current_line or 'nil'))
  
  -- Check if it's a git status line
  if current_line and current_line:match("%s*  [MADRCU?][MADRCU?]? ") then
    local filename = current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%+") or 
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.-)%s+%-") or
                    current_line:match("%s*  [MADRCU?][MADRCU?]? (.+)$")
    if filename then
      filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
      
      -- Use action system with lazy loading to avoid circular dependency
      actions.execute('git.unstage', {
        filename = filename,
        refresh_callback = function()
          -- Update git status through state system and refresh
          git_state.update_git_status(true) -- force refresh
          local files = git_state.get_git_status()
          render_callback(buf, files)
        end
      })
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
  
  -- Add virtual text hint in top right corner
  local hint_ns = vim.api.nvim_create_namespace('nexus_commit_hint')
  local hint_text = 'Ctrl-O -> open'
  local hint_col = actual_width - #hint_text
  vim.api.nvim_buf_set_extmark(popup_buf, hint_ns, 0, 0, {
    virt_text = {{ hint_text, 'Comment' }},
    virt_text_pos = 'overlay',
    virt_text_win_col = hint_col,
    hl_mode = 'combine'
  })
  
  -- Set up keymaps to close popup
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<Esc>', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<CR>', '<cmd>close<CR>', {noremap = true, silent = true})
  
  -- Add keybinding to open commit in browser with gh
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<C-o>', '', {
    noremap = true, 
    silent = true,
    callback = function()
      -- Use action system with lazy loading to avoid circular dependency
      actions.execute('open_commit', { commit_hash = commit_hash })
    end
  })
  
  logger.info('COMMIT', 'Showing details for commit: ' .. commit_hash)
end

-- Show Linear issue details in popup
function M.show_linear_issue_details(issue, config)
  logger.info('LINEAR', 'Showing Linear issue details', { 
    identifier = issue.identifier,
    title = issue.title
  })
  
  -- Format issue details
  local issue_details = {}
  
  -- Header with issue identifier and title
  local title = (issue.title and type(issue.title) == "string") and issue.title or "No title"
  table.insert(issue_details, string.format("%s - %s", issue.identifier, title))
  table.insert(issue_details, string.rep("=", #issue_details[1]))
  table.insert(issue_details, "")
  
  -- Basic info
  local description_start_line = nil
  local description_end_line = nil
  
  if issue.description and type(issue.description) == "string" and issue.description ~= "" then
    table.insert(issue_details, "Description:")
    description_start_line = #issue_details + 1 -- Next line after "Description:" header
    -- Split description by lines
    for line in issue.description:gmatch("[^\r\n]+") do
      table.insert(issue_details, "  " .. line)
    end
    description_end_line = #issue_details
    table.insert(issue_details, "")
  else
    table.insert(issue_details, "Description:")
    description_start_line = #issue_details + 1
    table.insert(issue_details, "  ") -- Add empty line for editing
    description_end_line = #issue_details
    table.insert(issue_details, "")
  end
  
  -- Status and Priority
  local status_line = "Status: " .. (issue.state and issue.state.name or "Unknown")
  if issue.priority and type(issue.priority) == "number" and issue.priority > 0 then
    local priority_names = { [1] = "Low", [2] = "Medium", [3] = "High", [4] = "Urgent" }
    local priority_name = priority_names[issue.priority] or "None"
    status_line = status_line .. " | Priority: " .. priority_name
  end
  table.insert(issue_details, status_line)
  
  -- Assignee
  if issue.assignee and type(issue.assignee) == "table" and issue.assignee.name then
    table.insert(issue_details, "Assignee: " .. issue.assignee.name)
  end
  
  -- Estimate
  if issue.estimate and type(issue.estimate) == "number" and issue.estimate > 0 then
    table.insert(issue_details, "Estimate: " .. issue.estimate .. " points")
  end
  
  -- Cycle
  if issue.cycle and type(issue.cycle) == "table" and issue.cycle.name then
    table.insert(issue_details, "Cycle: " .. issue.cycle.name)
  end
  
  -- Team
  if issue.team and type(issue.team) == "table" and issue.team.name then
    table.insert(issue_details, "Team: " .. issue.team.name)
  end
  
  -- Labels
  if issue.labels and type(issue.labels) == "table" and #issue.labels > 0 then
    local label_names = {}
    for _, label in ipairs(issue.labels) do
      if type(label) == "table" and label.name then
        table.insert(label_names, label.name)
      end
    end
    if #label_names > 0 then
      table.insert(issue_details, "Labels: " .. table.concat(label_names, ", "))
    end
  end
  
  -- Dates
  if issue.createdAt and type(issue.createdAt) == "string" then
    table.insert(issue_details, "Created: " .. issue.createdAt)
  end
  
  if issue.updatedAt and type(issue.updatedAt) == "string" then
    table.insert(issue_details, "Updated: " .. issue.updatedAt)
  end
  
  -- URL (for reference)
  if issue.url and type(issue.url) == "string" then
    table.insert(issue_details, "")
    table.insert(issue_details, "URL: " .. issue.url)
  end
  
  -- Create a new buffer for the popup
  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(popup_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(popup_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', true)
  
  -- Set buffer content
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, issue_details)
  
  -- Apply syntax highlighting
  M.apply_linear_popup_highlighting(popup_buf, issue_details, issue)
  
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', false)
  
  -- Calculate popup size
  local max_width = 100
  local max_height = 30
  local actual_width = math.min(max_width, math.max(50, #issue_details > 0 and math.max(unpack(vim.tbl_map(function(line) return #line end, issue_details))) or 50))
  local actual_height = math.min(max_height, math.max(10, #issue_details))
  
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
    title = ' Linear Issue: ' .. issue.identifier .. ' ',
    title_pos = 'center'
  }
  
  local popup_win = vim.api.nvim_open_win(popup_buf, true, popup_opts)
  
  -- Set popup window options
  vim.api.nvim_win_set_option(popup_win, 'wrap', true)
  vim.api.nvim_win_set_option(popup_win, 'number', false)
  vim.api.nvim_win_set_option(popup_win, 'relativenumber', false)
  vim.api.nvim_win_set_option(popup_win, 'cursorline', true)
  
  -- Add virtual text hint in top right corner
  local hint_ns = vim.api.nvim_create_namespace('nexus_linear_hint')
  local hint_text = 'e -> edit desc | Ctrl-O -> open'
  local hint_col = actual_width - #hint_text
  vim.api.nvim_buf_set_extmark(popup_buf, hint_ns, 0, 0, {
    virt_text = {{ hint_text, 'Comment' }},
    virt_text_pos = 'overlay',
    virt_text_win_col = hint_col,
    hl_mode = 'combine'
  })
  
  -- Set up keymaps to close popup
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<Esc>', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<CR>', '<cmd>close<CR>', {noremap = true, silent = true})
  
  -- Add keybinding to open issue in browser with Ctrl-O
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<C-o>', '', {
    noremap = true, 
    silent = true,
    callback = function()
      -- Close the popup first
      vim.cmd('close')
      -- Then open the issue in browser
      M.open_linear_issue(issue)
    end
  })
  
  -- Add keybinding to edit description with 'e'
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'e', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.edit_linear_issue_description(popup_buf, issue, description_start_line, description_end_line, config)
    end
  })
  
  logger.info('LINEAR', 'Showing details for Linear issue: ' .. issue.identifier)
end

-- Edit Linear issue description
function M.edit_linear_issue_description(popup_buf, issue, description_start_line, description_end_line, config)
  logger.info('LINEAR', 'Editing description for issue: ' .. issue.identifier)
  
  -- Make buffer modifiable for editing and set up for :w to work
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', true)
  vim.api.nvim_buf_set_option(popup_buf, 'buftype', 'acwrite') -- Allow custom write behavior
  
  -- Clear any existing buffer with this name first
  local buffer_name = 'linear-desc-' .. issue.identifier
  pcall(function()
    local existing_buf = vim.fn.bufnr('^' .. buffer_name .. '$')
    if existing_buf ~= -1 and existing_buf ~= popup_buf then
      vim.api.nvim_buf_delete(existing_buf, { force = true })
    end
  end)
  
  vim.api.nvim_buf_set_name(popup_buf, buffer_name)
  
  -- Find the Description: line and position cursor appropriately
  local all_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  local desc_line_num = nil
  
  for i, line in ipairs(all_lines) do
    if line:match("^Description:") then
      desc_line_num = i
      break
    end
  end
  
  if desc_line_num then
    -- Always position cursor on the line AFTER Description: (where content should go)
    if desc_line_num < #all_lines and all_lines[desc_line_num + 1] then
      -- Move to next line if it exists
      vim.api.nvim_win_set_cursor(0, {desc_line_num + 1, 2})
    else
      -- Fallback to original positioning
      vim.api.nvim_win_set_cursor(0, {description_start_line, 2})
    end
  else
    -- Fallback to original positioning
    vim.api.nvim_win_set_cursor(0, {description_start_line, 2})
  end
  
  -- Clear existing keymaps that would close the buffer
  pcall(vim.api.nvim_buf_del_keymap, popup_buf, 'n', 'q')
  pcall(vim.api.nvim_buf_del_keymap, popup_buf, 'n', '<Esc>')
  pcall(vim.api.nvim_buf_del_keymap, popup_buf, 'n', '<CR>')
  
  -- Add editing keymaps to the popup buffer
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<C-s>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.save_linear_issue_description(popup_buf, issue, description_start_line, description_end_line, config)
    end
  })
  
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<Esc>', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Clean up the edit buffer completely
      pcall(vim.api.nvim_buf_set_name, popup_buf, '')
      pcall(vim.api.nvim_buf_set_option, popup_buf, 'buftype', 'nofile')
      
      -- Cancel editing - close popup
      vim.cmd('close')
      -- Schedule buffer deletion to avoid issues
      vim.schedule(function()
        pcall(vim.api.nvim_buf_delete, popup_buf, { force = true })
      end)
    end
  })
  
  -- Add :w command support by intercepting the write command
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = popup_buf,
    callback = function()
      M.save_linear_issue_description(popup_buf, issue, description_start_line, description_end_line, config)
    end,
    desc = 'Save Linear issue description with :w'
  })
  
  
  -- Much simpler approach: just create a new buffer with only the description content
  -- This avoids all the complexity of trying to protect other lines
  
  -- Extract current description content
  local desc_content = ""
  local found_desc = false
  
  for _, line in ipairs(all_lines) do
    if line:match("^Description:") then
      found_desc = true
      -- Check if there's content on same line
      local same_line_content = line:match("^Description:%s*(.+)")
      if same_line_content and same_line_content:gsub("%s", "") ~= "" then
        desc_content = desc_content .. same_line_content .. "\n"
      end
    elseif found_desc and line:match("^[%w%s]+:") then
      break -- Stop at next field
    elseif found_desc then
      -- Remove indentation and add to content - preserve empty lines
      local clean_line = line:gsub("^  ", "")
      desc_content = desc_content .. clean_line .. "\n"
    end
  end
  
  -- Remove trailing newline
  desc_content = desc_content:gsub("\n$", "")
  
  -- Instead of creating a new buffer, just replace the content of the current buffer
  -- This is simpler and avoids buffer reference issues
  
  -- Set the description content (split by lines) 
  local desc_lines = desc_content ~= "" and vim.split(desc_content, '\n') or {""}
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, desc_lines)
  
  -- Change the window title to indicate editing mode
  vim.api.nvim_win_set_config(0, {
    title = " New Description: " .. issue.identifier .. " ",
    title_pos = "center"
  })
  
  -- Add save hint using a different approach - create an autocmd to maintain it
  vim.schedule(function()
    local hint_ns = vim.api.nvim_create_namespace('nexus_linear_edit_hint')
    
    local function add_hint()
      vim.api.nvim_buf_clear_namespace(popup_buf, hint_ns, 0, -1)
      
      -- Always add to line 0, even if it's empty
      local actual_width = vim.api.nvim_win_get_width(0)
      local hint_text = 'Ctrl-S -> save'
      local hint_col = actual_width - #hint_text - 2
      
      -- Use virt_text_pos = 'right_align' to keep it at the right edge
      vim.api.nvim_buf_set_extmark(popup_buf, hint_ns, 0, 0, {
        virt_text = {{hint_text, 'Comment'}},
        virt_text_pos = 'right_align',
        hl_mode = 'combine'
      })
    end
    
    -- Add initially
    add_hint()
    
    -- Re-add after any text changes
    vim.api.nvim_create_autocmd({'TextChanged', 'TextChangedI', 'BufEnter'}, {
      buffer = popup_buf,
      callback = add_hint,
      once = false
    })
    
    -- Position cursor at start of first line in normal mode
    vim.api.nvim_win_set_cursor(0, {1, 0})
  end)
  
  vim.notify("Edit description - Ctrl-S to save, Esc to cancel", vim.log.levels.INFO)
end

-- Save edited Linear issue description
function M.save_linear_issue_description(popup_buf, issue, description_start_line, description_end_line, config)
  logger.info('LINEAR', 'Saving description for issue: ' .. issue.identifier)
  
  -- Get all lines from the edit buffer and preserve empty lines
  local all_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  local description_text = table.concat(all_lines, '\n')
  -- Only trim whitespace from the very beginning and end, preserve internal empty lines
  description_text = description_text:gsub("^%s*", ""):gsub("%s*$", "")
  
  -- Get cached provider
  local provider = linear_state.get_cached_provider(config)
  
  if not provider then
    vim.notify("❌ Failed to get Linear provider", vim.log.levels.ERROR)
    return
  end
  
  vim.notify("Saving description...", vim.log.levels.INFO)
  
  -- Update the issue using the provider
  local updated_issue, error_msg = provider:update_issue(issue.id, {
    description = description_text
  })
  
  if updated_issue then
    logger.info('LINEAR', 'Description updated successfully', {
      identifier = updated_issue.identifier
    })
    
    vim.notify("✅ Description saved successfully!", vim.log.levels.INFO)
    
    -- Clean up the edit buffer completely
    pcall(vim.api.nvim_buf_set_name, popup_buf, '')
    pcall(vim.api.nvim_buf_set_option, popup_buf, 'buftype', 'nofile')
    
    -- Refresh Linear data
    linear_state.refresh_data(config)
    
    -- Close the popup and clean up buffer
    vim.cmd('close')
    -- Schedule buffer deletion to avoid issues
    vim.schedule(function()
      pcall(vim.api.nvim_buf_delete, popup_buf, { force = true })
    end)
  else
    logger.error('LINEAR', 'Failed to update description', {
      identifier = issue.identifier,
      error = error_msg
    })
    
    vim.notify("❌ Failed to save description: " .. (error_msg or "Unknown error"), vim.log.levels.ERROR)
  end
end

-- Apply syntax highlighting to commit details popup
function M.apply_commit_popup_highlighting(buf, lines, commit_hash)
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)
  
  -- Create namespaces for different highlight groups
  local commit_ns = vim.api.nvim_create_namespace('nexus_commit_popup')
  
  for i, line in ipairs(lines) do
    if line and #line > 0 then
      -- 1. Highlight commit hash (matches main dashboard highlighting)
      local hash_start, hash_end = line:find('[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+')
      if hash_start and hash_end then
        vim.api.nvim_buf_add_highlight(buf, commit_ns, 'Number', i - 1, hash_start - 1, hash_end)
      end
      
      -- 2. Highlight file paths in diff stats (lines ending with |)
      if line:match("|") then
        local pipe_pos = line:find("|")
        if pipe_pos then
          -- Highlight filename part
          local filename_part = line:sub(1, pipe_pos - 1):match("^%s*(.-)%s*$")
          if filename_part and #filename_part > 0 then
            vim.api.nvim_buf_add_highlight(buf, commit_ns, 'String', i - 1, 0, pipe_pos - 1)
          end
          
          -- Highlight + and - in diff stats (after the |)
          local stats_part = line:sub(pipe_pos + 1)
          for j = 1, #stats_part do
            local char = stats_part:sub(j, j)
            local actual_pos = pipe_pos + j - 1
            if char == '+' then
              vim.api.nvim_buf_add_highlight(buf, commit_ns, 'DiagnosticOk', i - 1, actual_pos, actual_pos + 1)
            elseif char == '-' then
              vim.api.nvim_buf_add_highlight(buf, commit_ns, 'DiagnosticError', i - 1, actual_pos, actual_pos + 1)
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
          vim.api.nvim_buf_add_highlight(buf, commit_ns, 'Function', i - 1, author_start - 1, author_end)
        end
      end
      
      -- 4. Highlight dates/time (pattern like "X minutes ago", "X days ago")
      local date_start, date_end = line:find('%d+ [%w]+ ago')
      if date_start then
        vim.api.nvim_buf_add_highlight(buf, commit_ns, 'Comment', i - 1, date_start - 1, date_end)
      end
      
      -- 5. Highlight summary lines (lines with file counts and insertions/deletions)
      if line:match('files? changed') or line:match('insertions?') or line:match('deletions?') then
        -- Highlight numbers in summary
        for num_start, num_end in line:gmatch('()(%d+)()') do
          vim.api.nvim_buf_add_highlight(buf, commit_ns, 'Number', i - 1, num_start - 1, num_end - 1)
        end
        
        -- Highlight keywords
        local keywords = {'files? changed', 'insertions?', 'deletions?'}
        for _, keyword in ipairs(keywords) do
          local kw_start, kw_end = line:find(keyword)
          if kw_start then
            vim.api.nvim_buf_add_highlight(buf, commit_ns, 'Keyword', i - 1, kw_start - 1, kw_end)
          end
        end
      end
      
      -- 6. Highlight commit message (usually the second or third line, not containing hash/author/date)
      if i <= 3 and not line:match('[a-f0-9]+') and not line:match('%d+ %w+ ago') and not line:match('|') and #line:gsub('^%s*(.-)%s*$', '%1') > 0 then
        vim.api.nvim_buf_add_highlight(buf, commit_ns, 'Title', i - 1, 0, -1)
      end
    end
  end
end

-- Apply syntax highlighting to Linear issue details popup
function M.apply_linear_popup_highlighting(buf, lines, issue)
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)
  
  -- Create namespace for Linear popup highlighting
  local linear_ns = vim.api.nvim_create_namespace('nexus_linear_popup')
  
  for i, line in ipairs(lines) do
    if line and #line > 0 then
      -- 1. Highlight the header line (issue identifier and title)
      if i == 1 and line:match('[A-Z]+-[0-9]+') then
        -- Highlight the identifier
        local id_start, id_end = line:find('[A-Z]+-[0-9]+')
        if id_start then
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'Number', i - 1, id_start - 1, id_end)
        end
        
        -- Highlight the rest as title
        local dash_pos = line:find(' - ')
        if dash_pos then
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'Title', i - 1, dash_pos + 2, -1)
        end
      end
      
      -- 2. Highlight the separator line (===)
      if line:match('^=+$') then
        vim.api.nvim_buf_add_highlight(buf, linear_ns, 'Comment', i - 1, 0, -1)
      end
      
      -- 3. Highlight field names (Status:, Assignee:, etc.)
      local field_patterns = {
        'Description:', 'Status:', 'Priority:', 'Assignee:', 'Estimate:', 
        'Cycle:', 'Team:', 'Labels:', 'Created:', 'Updated:', 'URL:'
      }
      
      for _, pattern in ipairs(field_patterns) do
        local field_start, field_end = line:find(pattern)
        if field_start then
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'Keyword', i - 1, field_start - 1, field_end)
          break
        end
      end
      
      -- 4. Highlight priority levels with colors
      if line:match('Priority:') then
        if line:match('Urgent') then
          local urgent_start, urgent_end = line:find('Urgent')
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'DiagnosticError', i - 1, urgent_start - 1, urgent_end)
        elseif line:match('High') then
          local high_start, high_end = line:find('High')
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'DiagnosticWarn', i - 1, high_start - 1, high_end)
        elseif line:match('Medium') then
          local medium_start, medium_end = line:find('Medium')
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'DiagnosticInfo', i - 1, medium_start - 1, medium_end)
        elseif line:match('Low') then
          local low_start, low_end = line:find('Low')
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'DiagnosticHint', i - 1, low_start - 1, low_end)
        end
      end
      
      -- 5. Highlight status with colors
      if line:match('Status:') then
        if line:match('Completed') then
          local completed_start, completed_end = line:find('Completed')
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'DiagnosticOk', i - 1, completed_start - 1, completed_end)
        elseif line:match('Started') then
          local started_start, started_end = line:find('Started')
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'DiagnosticInfo', i - 1, started_start - 1, started_end)
        elseif line:match('Canceled') then
          local canceled_start, canceled_end = line:find('Canceled')
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'DiagnosticError', i - 1, canceled_start - 1, canceled_end)
        end
      end
      
      -- 6. Highlight URLs
      if line:match('https?://[%w.-/]+') then
        local url_start, url_end = line:find('https?://[%w.-/]+')
        vim.api.nvim_buf_add_highlight(buf, linear_ns, 'Underlined', i - 1, url_start - 1, url_end)
      end
      
      -- 7. Highlight numbers (estimates, dates)
      if line:match('Estimate:') or line:match('points') then
        for num_start, num_end in line:gmatch('()(%d+)()') do
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'Number', i - 1, num_start - 1, num_end - 1)
        end
      end
      
      -- 8. Highlight names (assignee names, team names)
      if line:match('Assignee:') or line:match('Team:') or line:match('Cycle:') then
        local colon_pos = line:find(':')
        if colon_pos and colon_pos < #line then
          local value_start = line:find('[^%s:]', colon_pos + 1)
          if value_start then
            vim.api.nvim_buf_add_highlight(buf, linear_ns, 'String', i - 1, value_start - 1, -1)
          end
        end
      end
    end
  end
end

function M.handle_dashboard_action(config, command)
  -- The key difference is handled in buffer creation (persistent vs non-persistent)
  -- When keep_open_after_startup = true, Nexus buffer is created as persistent
  -- When keep_open_after_startup = false, Nexus buffer gets wiped when replaced
  vim.cmd(command)
end

function M.open_commit_in_browser(commit_hash)
  if not commit_hash then
    logger.error('COMMIT', 'No commit hash provided for browser opening')
    return
  end
  
  -- Use actions system for GitHub browse
  actions.execute('github.browse', {
    commit_hash = commit_hash
  })
end

-- Open Linear issue in browser
function M.open_linear_issue(issue)
  logger.info('LINEAR', 'Opening Linear issue', { 
    identifier = issue.identifier,
    url = issue.url 
  })
  
  -- Platform-specific URL opening
  local open_cmd
  if vim.fn.has('mac') == 1 then
    open_cmd = 'open'
  elseif vim.fn.has('unix') == 1 then
    open_cmd = 'xdg-open'
  elseif vim.fn.has('win32') == 1 then
    open_cmd = 'start'
  else
    logger.error('LINEAR', 'Unsupported platform for opening URLs')
    vim.notify("Unsupported platform for opening URLs", vim.log.levels.ERROR)
    return
  end
  
  -- Execute command to open URL
  local result = vim.fn.system(string.format('%s "%s"', open_cmd, issue.url))
  local exit_code = vim.v.shell_error
  
  if exit_code == 0 then
    vim.notify(string.format("Opened %s in browser", issue.identifier), vim.log.levels.INFO)
  else
    logger.error('LINEAR', 'Failed to open browser', { 
      exit_code = exit_code,
      result = result
    })
    vim.notify(string.format("Failed to open browser: %s", result), vim.log.levels.ERROR)
  end
end

-- Refresh Linear issues
function M.refresh_linear_issues(buf, config, render_callback)
  logger.info('LINEAR', 'Refreshing Linear issues')
  vim.notify("Refreshing Linear issues...", vim.log.levels.INFO)
  
  linear_state.refresh_data(config)
  
  -- Re-render the buffer
  render_callback(buf)
end

-- Setup Linear API key
function M.setup_linear_api_key(config, render_callback)
  logger.info('LINEAR', 'Setting up Linear API key')
  
  linear_state.handle_api_key_setup(config, render_callback)
end

-- Handle Linear status update for current issue
function M.handle_linear_status_update(buf, render_callback, config)
  local issue = M.get_current_issue_from_cursor(buf)
  if not issue then
    return
  end
  
  logger.info('LINEAR', 'Starting status update', { 
    identifier = issue.identifier,
    current_status = issue.state and issue.state.name 
  })
  
  -- Show status selection modal
  M.show_status_selection_modal(issue, config, function(new_status_id)
    if new_status_id then
      logger.info('LINEAR', 'Updating issue status', {
        identifier = issue.identifier,
        issue_id = issue.id,
        new_status_id = new_status_id
      })
      
      vim.notify(string.format("Updating %s status...", issue.identifier), vim.log.levels.INFO)
      
      linear_state.update_issue_status(issue.id, new_status_id, config, function(success, result)
        if success then
          vim.notify(string.format("✅ %s status updated to: %s", 
            result.identifier, 
            result.state.name), 
            vim.log.levels.INFO)
          
          render_callback(buf)
        else
          vim.notify(string.format("❌ Failed to update %s: %s", 
            issue.identifier, 
            result or "Unknown error"), 
            vim.log.levels.ERROR)
        end
      end)
    end
  end)
end

-- Handle Linear project selection
function M.handle_linear_project_selection(buf, render_callback, config)
  logger.info('LINEAR', 'Starting project selection')
  
  -- Show project selection modal (two-step: team -> project)
  M.show_project_selection_modal(config, function(new_team_id, new_project_id)
    if new_team_id then
      logger.info('LINEAR', 'Updating team/project selection', {
        new_team_id = new_team_id,
        new_project_id = new_project_id
      })
      
      -- Update config for this session
      if not config.linear then
        config.linear = {}
      end
      config.linear.team_id = new_team_id
      if new_project_id then
        config.linear.project_id = new_project_id
      end
      
      vim.notify("Switching Linear project...", vim.log.levels.INFO)
      
      -- Force refresh Linear data with new team/project
      local linear_state = require('nexus.state.linear')
      linear_state.refresh_data(config)
      
      -- Re-render the buffer after a short delay to allow data refresh
      vim.defer_fn(function()
        render_callback(buf)
      end, 500)
    end
  end)
end

-- Handle Linear issue creation
function M.handle_linear_create_issue(buf, render_callback, config)
  logger.info('LINEAR', 'Starting issue creation')
  
  -- Prompt for issue title
  vim.ui.input({
    prompt = 'Issue title: '
  }, function(title)
    if not title or title:match('^%s*$') then
      return
    end
    
    -- Prompt for issue description (optional)
    vim.ui.input({
      prompt = 'Description (optional): '
    }, function(description)
      -- Get cached provider
      local provider = linear_state.get_cached_provider(config)
      if not provider then
        vim.notify("❌ Failed to get Linear provider", vim.log.levels.ERROR)
        return
      end
      
      -- Determine team ID and project ID from existing issues
      local existing_issues = linear_state.get_issues()
      local team_id = nil
      local project_id = nil
      
      if existing_issues and #existing_issues > 0 then
        -- Use team and project from the first existing issue
        local first_issue = existing_issues[1]
        team_id = first_issue.team and first_issue.team.id
        project_id = first_issue.project and first_issue.project.id
        
        logger.debug('LINEAR', 'Using team and project from existing issues', {
          team_id = team_id,
          team_name = first_issue.team and first_issue.team.name,
          project_id = project_id,
          project_name = first_issue.project and first_issue.project.name
        })
      end
      
      if not team_id then
        vim.notify("❌ No team found. Load existing Linear issues first or configure team_id in config.", vim.log.levels.ERROR)
        return
      end
      
      vim.notify("Creating Linear issue...", vim.log.levels.INFO)
      
      -- Create the issue
      local issue_data = {
        title = title,
        description = description or "",
        priority = 0, -- Default priority
        team_id = team_id,
        project_id = project_id -- Assign to same project as existing issues
      }
      
      local created_issue, error_msg = provider:create_issue(issue_data)
      
      if created_issue then
        logger.info('LINEAR', 'Issue created successfully', {
          identifier = created_issue.identifier,
          title = created_issue.title
        })
        
        vim.notify(string.format("✅ Created issue %s: %s", 
          created_issue.identifier, 
          created_issue.title), 
          vim.log.levels.INFO)
        
        -- Refresh Linear data to show the new issue
        linear_state.refresh_data(config)
        
        -- Re-render the buffer
        render_callback(buf)
      else
        logger.error('LINEAR', 'Failed to create issue', {
          error = error_msg,
          title = title
        })
        vim.notify(string.format("❌ Failed to create issue: %s", 
          error_msg or "Unknown error"), 
          vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Extract issue identification from cursor position
function M.get_current_issue_from_cursor(buf)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  
  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  if not current_line then
    logger.warn('LINEAR', 'No current line found')
    return nil
  end
  
  -- Check if this is a Linear issue line
  local is_issue, identifier = linear_component.is_linear_issue_line(current_line)
  
  if not is_issue or not identifier then
    logger.warn('LINEAR', 'Not on a Linear issue line', { line = current_line })
    vim.notify("Position cursor on a Linear issue to update its status", vim.log.levels.WARN)
    return nil
  end
  
  logger.debug('LINEAR', 'Found Linear issue line', { identifier = identifier })
  
  -- Get the issue data
  local issues = linear_state.get_issues()
  local issue = linear_component.get_issue_from_line(current_line, issues)
  
  if not issue then
    logger.error('LINEAR', 'Could not find issue data', { identifier = identifier })
    vim.notify("Could not find issue data for " .. identifier, vim.log.levels.ERROR)
    return nil
  end
  
  return issue
end

-- Show status selection modal
function M.show_status_selection_modal(issue, config, callback)
  logger.info('LINEAR', 'Showing status selection modal', { 
    identifier = issue.identifier 
  })
  
  -- Get available states from cached provider
  local states = linear_state.get_cached_states(config, issue.team and issue.team.id)
  
  if not states then
    vim.notify("Failed to fetch available states", vim.log.levels.ERROR)
    return
  end
  
  if #states == 0 then
    vim.notify("No states available for this team", vim.log.levels.WARN)
    return
  end
  
  -- Sort states by position
  table.sort(states, function(a, b) 
    return (a.position or 999) < (b.position or 999) 
  end)
  
  -- Create status selection menu
  local status_options = {}
  local current_status_idx = nil
  
  for i, state in ipairs(states) do
    local display_name = state.name
    if issue.state and issue.state.id == state.id then
      display_name = display_name .. " (current)"
      current_status_idx = i
    end
    table.insert(status_options, display_name)
  end
  
  -- Show selection using vim.ui.select
  vim.ui.select(status_options, {
    prompt = string.format("Select new status for %s:", issue.identifier),
    format_item = function(item)
      return "  " .. item
    end,
  }, function(choice, idx)
    if choice and idx then
      local selected_state = states[idx]
      if selected_state and (not issue.state or selected_state.id ~= issue.state.id) then
        logger.info('LINEAR', 'Status selected', { 
          identifier = issue.identifier,
          new_status = selected_state.name,
          new_status_id = selected_state.id
        })
        callback(selected_state.id)
      else
        logger.debug('LINEAR', 'Same status selected, no change needed')
      end
    else
      logger.debug('LINEAR', 'Status selection cancelled')
    end
  end)
end

-- Show project selection modal (two-step: team then project)
function M.show_project_selection_modal(config, callback)
  logger.info('LINEAR', 'Showing project selection modal')
  
  -- Get cached Linear provider
  local linear_state = require('nexus.state.linear')
  local provider = linear_state.get_cached_provider(config)
  
  if not provider then
    vim.notify("Failed to get Linear provider", vim.log.levels.ERROR)
    return
  end
  
  -- Step 1: Get available teams
  local teams, error_msg = provider:get_teams()
  
  if not teams then
    vim.notify("Failed to fetch Linear teams: " .. (error_msg or "Unknown error"), vim.log.levels.ERROR)
    return
  end
  
  if #teams == 0 then
    vim.notify("No Linear teams available", vim.log.levels.WARN)
    return
  end
  
  -- Sort teams by name
  table.sort(teams, function(a, b) 
    return a.name < b.name 
  end)
  
  -- Create team selection menu
  local team_options = {}
  local current_team_idx = nil
  
  for i, team in ipairs(teams) do
    local display_name = string.format("%s (%s)", team.name, team.key)
    if config.linear.team_id and config.linear.team_id == team.id then
      display_name = display_name .. " (current)"
      current_team_idx = i
    end
    table.insert(team_options, display_name)
  end
  
  -- Show team selection using vim.ui.select
  vim.ui.select(team_options, {
    prompt = "Step 1: Select Linear team:",
    format_item = function(item)
      return "  " .. item
    end,
  }, function(choice, idx)
    if choice and idx then
      local selected_team = teams[idx]
      logger.info('LINEAR', 'Team selected', { 
        team_name = selected_team.name,
        team_id = selected_team.id
      })
      
      -- Step 2: Get projects for the selected team
      M.show_team_projects_selection(provider, selected_team, config, callback)
    else
      logger.debug('LINEAR', 'Team selection cancelled')
    end
  end)
end

-- Show projects selection for a specific team
function M.show_team_projects_selection(provider, selected_team, config, callback)
  logger.info('LINEAR', 'Showing projects for team', { team_name = selected_team.name })
  
  -- Get projects for the selected team
  local projects, error_msg = provider:get_projects(selected_team.id)
  
  if not projects then
    vim.notify("Failed to fetch projects for " .. selected_team.name .. ": " .. (error_msg or "Unknown error"), vim.log.levels.ERROR)
    -- Still allow team-only selection
    callback(selected_team.id, nil)
    return
  end
  
  if #projects == 0 then
    vim.notify("No active projects in " .. selected_team.name .. ". Selecting team only.", vim.log.levels.INFO)
    callback(selected_team.id, nil)
    return
  end
  
  -- Sort projects by name
  table.sort(projects, function(a, b) 
    return a.name < b.name 
  end)
  
  -- Create project selection menu with team-only option
  local project_options = {"[No specific project - team only]"}
  local current_project_idx = nil
  
  for i, project in ipairs(projects) do
    local display_name = project.name
    if project.description and project.description ~= "" then
      display_name = display_name .. " - " .. project.description:gsub("\n.*", ""):sub(1, 50) -- First line, truncated
    end
    
    if config.linear.project_id and config.linear.project_id == project.id then
      display_name = display_name .. " (current)"
      current_project_idx = i + 1 -- +1 because of the "no project" option
    end
    table.insert(project_options, display_name)
  end
  
  -- Show project selection
  vim.ui.select(project_options, {
    prompt = string.format("Step 2: Select project in %s:", selected_team.name),
    format_item = function(item)
      return "  " .. item
    end,
  }, function(choice, idx)
    if choice and idx then
      if idx == 1 then
        -- Selected "no specific project"
        logger.info('LINEAR', 'Team-only selection', { 
          team_name = selected_team.name,
          team_id = selected_team.id
        })
        callback(selected_team.id, nil)
      else
        -- Selected a specific project
        local selected_project = projects[idx - 1] -- -1 because of the "no project" option
        logger.info('LINEAR', 'Team and project selected', { 
          team_name = selected_team.name,
          team_id = selected_team.id,
          project_name = selected_project.name,
          project_id = selected_project.id
        })
        callback(selected_team.id, selected_project.id)
      end
    else
      logger.debug('LINEAR', 'Project selection cancelled')
    end
  end)
end

-- Get the first changed line number for a file using git diff
function M.get_first_changed_line(filename)
  -- Try unstaged changes first
  local handle = io.popen('git diff --unified=0 -- "' .. filename .. '" 2>/dev/null')
  if handle then
    local result = handle:read('*a')
    handle:close()
    
    -- If no unstaged changes, try staged changes
    if result == '' then
      handle = io.popen('git diff --cached --unified=0 -- "' .. filename .. '" 2>/dev/null')
      if handle then
        result = handle:read('*a')
        handle:close()
      end
    end
    
    -- Parse the diff output to find first changed line
    if result and result ~= '' then
      for line in result:gmatch('[^\r\n]+') do
        -- Look for hunk headers like @@ -10,5 +10,6 @@
        local new_start = line:match('^@@ %-?%d+,?%d* %+(%d+)')
        if new_start then
          return tonumber(new_start)
        end
      end
    end
  end
  
  return nil
end

-- Handle 'c' key - context-aware create (git commit, Linear issue, or todo)
function M.handle_c_key(buf, render_callback, config)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  if not current_line then return end
  
  -- Determine which section we're in
  local section = M.get_current_section(lines, line_num, config)
  
  -- Handle based on section
  if section == "linear" then
    linear_keymaps.handle_create(buf, render_callback, config)
  elseif section == "todo" then
    todo_keymaps.handle_create(buf, render_callback, config)
  else
    -- Default: git commit
    actions.execute('git.commit', {
      interactive = true,
      refresh_callback = function()
        render_callback(buf)
      end
    })
  end
end

-- Handle 'e' key - edit todo
function M.handle_e_key(buf, render_callback, config)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  if not current_line then return end
  
  -- Determine which section we're in
  local section = M.get_current_section(lines, line_num, config)
  
  -- Only handle 'e' key in todo section
  if section == "todo" then
    local todo_id = todo_component.get_todo_id_from_line_num(line_num)
    if todo_id then
      todo_keymaps.handle_edit(todo_id, buf, render_callback, config)
    end
  end
end

-- Handle 'd' key - mark todo as done
function M.handle_d_key(buf, render_callback, config)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  if not current_line then return end
  
  -- Determine which section we're in
  local section = M.get_current_section(lines, line_num, config)
  
  -- Only handle 'd' key in todo section
  if section == "todo" then
    local todo_id = todo_component.get_todo_id_from_line_num(line_num)
    if todo_id then
      todo_keymaps.handle_done(todo_id, buf, render_callback, config)
    end
  end
end

-- Check if cursor is in the Todo section
function M.is_in_todo_section(lines, line_num)
  -- Look backwards for section headers
  for i = line_num, 1, -1 do
    local line = lines[i]
    if line then
      if line:match("^Todo:") then
        return true
      elseif line:match("^[%w%s]+:$") and not line:match("^Todo:") then
        -- Hit another section header
        return false
      end
    end
  end
  return false
end

-- Handle todo creation
function M.handle_todo_create(buf, render_callback, config)
  vim.ui.input({
    prompt = 'New todo: '
  }, function(text)
    if not text or text:match('^%s*$') then
      return
    end
    
    actions.execute('todo.create', {
      text = text
    })
    -- Refresh the buffer after creating
    render_callback(buf)
  end)
end

-- Handle todo editing
function M.handle_todo_edit(todo_id, buf, render_callback, config)
  local todo = todo_state.get_todo_by_id(todo_id)
  if not todo then
    vim.notify("Todo not found", vim.log.levels.ERROR)
    return
  end
  
  vim.ui.input({
    prompt = 'Edit todo: ',
    default = todo.text
  }, function(text)
    if not text or text:match('^%s*$') then
      return
    end
    
    actions.execute('todo.edit', {
      id = todo_id,
      text = text
    })
    -- Refresh the buffer after editing
    render_callback(buf)
  end)
end

-- Handle todo completion
function M.handle_todo_done(todo_id, buf, render_callback, config)
  local todo = todo_state.get_todo_by_id(todo_id)
  if not todo then
    vim.notify("Todo not found", vim.log.levels.ERROR)
    return
  end
  
  if todo.completed then
    vim.notify("Todo already completed", vim.log.levels.INFO)
    return
  end
  
  actions.execute('todo.done', {
    id = todo_id
  })
  -- Refresh the buffer after marking done
  render_callback(buf)
end

-- Handle 'D' key - delete todo
function M.handle_D_key(buf, render_callback, config)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  if not current_line then return end
  
  -- Determine which section we're in
  local section = M.get_current_section(lines, line_num, config)
  
  -- Only handle 'D' key in todo section
  if section == "todo" then
    local todo_id = todo_component.get_todo_id_from_line_num(line_num)
    if todo_id then
      todo_keymaps.handle_delete(todo_id, buf, render_callback, config)
    end
  end
end

-- Handle todo deletion  
function M.handle_todo_delete(todo_id, buf, render_callback, config)
  local todo = todo_state.get_todo_by_id(todo_id)
  if not todo then
    vim.notify("Todo not found", vim.log.levels.ERROR)
    return
  end
  
  -- Confirm deletion
  vim.ui.select({'Yes', 'No'}, {
    prompt = string.format('Delete todo: "%s"?', todo.text)
  }, function(choice)
    if choice == 'Yes' then
      actions.execute('todo.delete', {
        id = todo_id
      })
      -- Refresh the buffer after deleting
      render_callback(buf)
    end
  end)
end

-- Show todo details popup
function M.show_todo_details(todo, config)
  local todo_details = {}
  
  -- Header
  table.insert(todo_details, string.format("Todo: %s", todo.text))
  table.insert(todo_details, string.rep("=", #todo_details[1]))
  table.insert(todo_details, "")
  
  -- Status
  local status = todo.completed and "✅ Completed" or "⭕ Active"
  table.insert(todo_details, "Status: " .. status)
  
  -- Dates
  local created_date = os.date("%Y-%m-%d %H:%M", todo.created_at)
  table.insert(todo_details, "Created: " .. created_date)
  
  if todo.updated_at ~= todo.created_at then
    local updated_date = os.date("%Y-%m-%d %H:%M", todo.updated_at)
    table.insert(todo_details, "Updated: " .. updated_date)
  end
  
  -- Create popup buffer
  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(popup_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(popup_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', true)
  
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, todo_details)
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', false)
  
  -- Calculate popup size
  local max_width = 60
  local max_height = 20
  local actual_width = math.min(max_width, math.max(30, #todo_details > 0 and math.max(unpack(vim.tbl_map(function(line) return #line end, todo_details))) or 30))
  local actual_height = math.min(max_height, math.max(8, #todo_details))
  
  -- Calculate popup position
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
    title = ' Todo Details ',
    title_pos = 'center'
  }
  
  local popup_win = vim.api.nvim_open_win(popup_buf, true, popup_opts)
  
  -- Set popup window options
  vim.api.nvim_win_set_option(popup_win, 'wrap', true)
  vim.api.nvim_win_set_option(popup_win, 'number', false)
  vim.api.nvim_win_set_option(popup_win, 'relativenumber', false)
  vim.api.nvim_win_set_option(popup_win, 'cursorline', true)
  
  -- Set up keymaps to close popup
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<Esc>', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<CR>', '<cmd>close<CR>', {noremap = true, silent = true})
end

return M
