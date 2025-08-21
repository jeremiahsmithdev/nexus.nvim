local M = {}
local logger = require('nexus.logger')

local actions = require('nexus.actions')
local git_command = require('nexus.git.command')
local tmux = require('nexus.tmux')
local linear_state = require('nexus.state.linear')
local linear_component = require('nexus.render.components.linear')
local git_state = require('nexus.state.git')
local claude = require('nexus.claude')
local logo = require('nexus.ui.logo')


--- Handle Enter key press in Nexus buffer
function M.handle_enter_key(buf, files, config, is_git_repo, render_callback)
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
  -- Check if it's a Linear issue line or error line
  elseif config.linear and config.linear.enabled and current_line then
    local is_issue, identifier = linear_component.is_linear_issue_line(current_line)
    
    logger.debug('LINEAR', 'Checking Linear line', {
      current_line = current_line,
      is_issue = is_issue,
      identifier = identifier
    })
    
    if is_issue and identifier then
      -- Get issue data and open in browser
          local issues = linear_state.get_issues()
      
      logger.debug('LINEAR', 'Found Linear issue', {
        identifier = identifier,
        issues_count = issues and #issues or 0
      })
      
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
    elseif current_line:match("No API key found") or current_line:match("Invalid API key") then
      -- Handle API key setup
      logger.info('LINEAR', 'Triggering API key setup')
      M.setup_linear_api_key(config, function()
        render_callback(buf)
      end)
    else
      logger.warn('LINEAR', 'Linear line detected but no action matched', { line = current_line })
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
      local full_path = git_root and (git_root .. '/' .. filename) or filename
      local edit_cmd = 'edit ' .. vim.fn.fnameescape(full_path) .. ' | set number | set signcolumn=yes'
      M.handle_dashboard_action(config, edit_cmd)
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
  
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.async_esc()
    end
  })
  
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
        -- Check if we're in Linear section first (if Linear is enabled)
        if config.linear and config.linear.enabled then
          local cursor = vim.api.nvim_win_get_cursor(0)
          local line_num = cursor[1]
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          local current_line = lines[line_num]
          
          if current_line then
            local in_linear_section = false
            
            if current_line:match("Linear Issues:") then
              in_linear_section = true
            else
              local linear_component = require('nexus.render.components.linear')
              local is_issue, _ = linear_component.is_linear_issue_line(current_line)
              if is_issue then
                in_linear_section = true
              else
                if current_line:match("Loading issues") or 
                   current_line:match("No issues found") or 
                   current_line:match("No API key") or 
                   current_line:match("Invalid API key") then
                  in_linear_section = true
                end
              end
            end
            
            if in_linear_section then
              -- Handle Linear create issue
              M.handle_linear_create_issue(buf, render_callback, config)
              return
            end
          end
        end
        
        -- Default: Use actions system for git commit window
        actions.execute('git.commit', {
          interactive = true,
          refresh_callback = function()
            render_callback(buf)
          end
        })
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
    -- table.insert(issue_details, "  (No description - press 'e' to add one)")
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
  
  -- Make buffer modifiable for editing
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', true)
  
  -- Move cursor to description section
  vim.api.nvim_win_set_cursor(0, {description_start_line, 2})
  
  -- Clear existing keymaps that would close the buffer
  pcall(vim.api.nvim_buf_del_keymap, popup_buf, 'n', 'q')
  pcall(vim.api.nvim_buf_del_keymap, popup_buf, 'n', '<Esc>')
  pcall(vim.api.nvim_buf_del_keymap, popup_buf, 'n', '<CR>')
  
  -- Add editing keymaps
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
      -- Cancel editing - close popup
      vim.cmd('close')
    end
  })
  
  -- Update hint text
  local hint_ns = vim.api.nvim_create_namespace('nexus_linear_hint')
  vim.api.nvim_buf_clear_namespace(popup_buf, hint_ns, 0, -1)
  local actual_width = vim.api.nvim_win_get_width(0)
  local hint_text = 'Ctrl-S -> save | Esc -> cancel'
  local hint_col = actual_width - #hint_text
  vim.api.nvim_buf_set_extmark(popup_buf, hint_ns, 0, 0, {
    virt_text = {{ hint_text, 'Comment' }},
    virt_text_pos = 'overlay',
    virt_text_win_col = hint_col,
    hl_mode = 'combine'
  })
  
  -- Enter insert mode in description area
  vim.schedule(function()
    vim.cmd('startinsert')
  end)
  
  vim.notify("Edit description - Ctrl-S to save, Esc to cancel", vim.log.levels.INFO)
end

-- Save edited Linear issue description
function M.save_linear_issue_description(popup_buf, issue, description_start_line, description_end_line, config)
  logger.info('LINEAR', 'Saving description for issue: ' .. issue.identifier)
  
  -- Extract description text from buffer
  local lines = vim.api.nvim_buf_get_lines(popup_buf, description_start_line - 1, description_end_line, false)
  local description_text = ""
  
  for _, line in ipairs(lines) do
    -- Remove leading indentation (2 spaces)
    local clean_line = line:gsub("^  ", "")
    description_text = description_text .. clean_line .. "\n"
  end
  
  -- Remove trailing newline and any placeholder text
  description_text = description_text:gsub("\n$", "")
  if description_text:match("%(No description") then
    description_text = ""
  end
  
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
    
    -- Refresh Linear data
    linear_state.refresh_data(config)
    
    -- Close the popup
    vim.cmd('close')
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


return M
