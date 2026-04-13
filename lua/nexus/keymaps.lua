--- Keymap coordinator for Nexus
--- Registers and coordinates all buffer-local keymaps with modular architecture
--- Delegates specific functionality to specialized keymap modules and UI components
---@module nexus.keymaps

local M = {}

local logger = require('nexus.logger')
local actions = require('nexus.actions')
local navigation = require('nexus.navigation')

-- Section-specific keymap handlers
local todo_keymaps = require('nexus.keymaps.todo')
local linear_keymaps = require('nexus.keymaps.linear')
local huly_keymaps = require('nexus.keymaps.huly')
local beads_keymaps = require('nexus.keymaps.beads')
local dashboard_keymaps = require('nexus.keymaps.dashboard')
local git_keymaps = require('nexus.keymaps.git')
local claude_keymaps = require('nexus.keymaps.claude')

-- UI components
local logo = require('nexus.ui.logo')
local commit_popup = require('nexus.ui.popups.commit')
local linear_popup = require('nexus.ui.popups.linear')

-- State and components for legacy compatibility
local linear_component = require('nexus.render.components.linear')
local linear_state = require('nexus.state.linear')
local todo_component = require('nexus.render.components.todo')
local claude = require('nexus.claude')
local tmux = require('nexus.tmux')
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
      -- Check for section headers (with or without fold indicators)
      if line:match("Linear Issues:%s*$") then
        return "linear"
      elseif line:match("Huly Issues:%s*$") then
        return "huly"
      elseif line:match("Beads Issues:%s*$") then
        return "beads"
      elseif line:match("Todo:%s*$") then
        return "todo"
      elseif line:match("Recent Commits:%s*$") then
        return "commits"
      elseif line:match("Git Status:%s*$") then
        return "git_status"
      elseif line:match("^%s*Dashboard:%s*$") or line:match("Find file") or line:match("Recently opened files") then
        return "dashboard"
      elseif line:match("^%s*Keyboard Shortcuts:%s*$") then
        return "shortcuts"
      end
    end
  end
  
  return "unknown"
end

--- Handle 'e' key press - context-sensitive editing (todo edit or commit review status)
---@param buf number Buffer number
---@param config table Nexus configuration
---@param render_callback function Function to re-render the buffer
function M.handle_e_key(buf, config, render_callback)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]

  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]

  if not current_line then return end

  -- Determine which section we're in
  local section = M.get_current_section(lines, line_num, config)

  if section == "todo" then
    -- Handle todo editing
    local todo_id = todo_component.get_todo_id_from_line_num(line_num)
    todo_keymaps.handle_edit(todo_id, buf, render_callback, config)

  elseif section == "beads" then
    -- Handle beads issue editing
    beads_keymaps.handle_edit(current_line, line_num, buf, render_callback, config)

  elseif section == "commits" and config.show_commit_review then
    -- Handle commit review status
    M.handle_commit_review_status(current_line, buf, render_callback, config)
    
  else
    logger.debug('KEYMAP', 'e key pressed in unsupported section', { 
      section = section, 
      line = current_line 
    })
  end
end

--- Handle Enter key press in Nexus buffer
---@param buf number Buffer number
---@param files table Git status files
---@param config table Nexus configuration
---@param is_git_repo boolean Whether current directory is a git repo
---@param render_callback function Function to re-render the buffer
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

  elseif section == "huly" then
    huly_keymaps.handle_enter(current_line, config, buf, render_callback)

  elseif section == "beads" then
    beads_keymaps.handle_enter(current_line, line_num, config, buf, render_callback)

  elseif section == "todo" then
    todo_keymaps.handle_enter(current_line, line_num, config)
    
  else
    logger.debug('KEYMAP', 'Enter key pressed in unknown section', { 
      section = section, 
      line = current_line 
    })
  end
end

--- Set up basic navigation keymaps (j/k/gg)
---@param buf number Buffer number
---@param logo_end_line number Last line of logo section
---@param section_ranges table Section ranges for navigation
local function setup_basic_navigation_keymaps(buf, logo_end_line, section_ranges)
  -- Override j/k to jump between actionable lines
  vim.api.nvim_buf_set_keymap(buf, 'n', 'j', '', {
    noremap = true,
    silent = true,
    callback = function() 
      navigation.move_to_next_actionable(1, logo_end_line, section_ranges) 
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'k', '', {
    noremap = true,
    silent = true,
    callback = function() 
      navigation.move_to_next_actionable(-1, logo_end_line, section_ranges) 
    end
  })
  
  -- Override gg to go to first actionable line but show logo in viewport
  vim.api.nvim_buf_set_keymap(buf, 'n', 'gg', '', {
    noremap = true,
    silent = true,
    callback = function()
      navigation.go_to_first_actionable(logo_end_line, section_ranges)
    end
  })
end

--- Set up fold toggle keymaps (za, Tab, Space)
---@param buf number Buffer number
local function setup_fold_keymaps(buf)
  local folding = require('nexus.ui.folding')

  -- Standard Vim fold toggle (za)
  vim.api.nvim_buf_set_keymap(buf, 'n', 'za', '', {
    noremap = true,
    silent = true,
    callback = function()
      folding.toggle_fold_at_cursor(buf)
    end
  })

  -- Tab key for fold toggle
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Tab>', '', {
    noremap = true,
    silent = true,
    callback = function()
      folding.toggle_fold_at_cursor(buf)
    end
  })

  -- Space key for fold toggle
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Space>', '', {
    noremap = true,
    silent = true,
    callback = function()
      folding.toggle_fold_at_cursor(buf)
    end
  })
end

--- Set up section navigation keymaps ({/})
---@param buf number Buffer number
---@param config table Nexus configuration
---@param logo_end_line number Last line of logo section
---@param section_ranges table Section ranges for navigation
local function setup_section_navigation_keymaps(buf, config, logo_end_line, section_ranges)
  -- Section navigation with { and } - jump to first actionable line of previous/next section
  vim.api.nvim_buf_set_keymap(buf, 'n', '{', '', {
    noremap = true,
    silent = true,
    callback = function()
      navigation.navigate_to_previous_section(M.get_current_section, config, logo_end_line, section_ranges)
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', '}', '', {
    noremap = true,
    silent = true,
    callback = function()
      navigation.navigate_to_next_section(M.get_current_section, config, logo_end_line, section_ranges)
    end
  })
end

--- Set up git-specific keymaps
---@param buf number Buffer number
---@param config table Nexus configuration
---@param render_callback function Function to re-render the buffer
local function setup_git_keymaps(buf, config, render_callback)
  vim.api.nvim_buf_set_keymap(buf, 'n', 'r', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Refresh Linear data if enabled
      if config.linear and config.linear.enabled then
        linear_state.refresh_data(config)
      end
      -- Refresh Huly data if enabled
      if config.huly and config.huly.enabled then
        local huly_state = require('nexus.state.huly')
        huly_state.refresh_data(config)
      end
      render_callback(buf)
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 's', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Context-aware 's' key - stage in git, update status in issue trackers
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local line_num = vim.api.nvim_win_get_cursor(0)[1]
      local section = M.get_current_section(lines, line_num, config)
      local current_line = lines[line_num]

      if section == "huly" and current_line then
        huly_keymaps.handle_status_update(current_line, buf, render_callback, config)
      elseif section == "beads" and current_line then
        beads_keymaps.handle_status_update(current_line, line_num, buf, render_callback, config)
      elseif section == "linear" then
        linear_keymaps.handle_status_update(buf, render_callback, config)
      else
        -- Default to git stage
        git_keymaps.handle_add(buf, render_callback)
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'u', '', {
    noremap = true,
    silent = true,
    callback = function()
      git_keymaps.handle_unstage(buf, render_callback)
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'c', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Handle 'c' key - could be commit or create todo
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local line_num = vim.api.nvim_win_get_cursor(0)[1]
      local section = M.get_current_section(lines, line_num, config)
      local config_module = require('nexus.config')

      if section == "linear" then
        linear_keymaps.handle_create(buf, render_callback, config)
      elseif section == "huly" then
        huly_keymaps.handle_create(buf, render_callback, config)
      elseif section == "beads" then
        beads_keymaps.handle_create(buf, render_callback, config)
      elseif section == "todo" or (config_module.is_section_enabled("todos") and section == "unknown") then
        todo_keymaps.handle_create(buf, render_callback, config)
      else
        -- Default to git commit
        git_keymaps.handle_commit(buf, render_callback, config)
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>g', '', {
    noremap = true,
    silent = true,
    callback = function()
      git_keymaps.handle_command_window(buf, render_callback, config)
    end
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', 'v', '', {
    noremap = false,
    silent = true,
    callback = function()
      -- Handle 'v' in commits and git_status sections, otherwise use default visual mode
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local line_num = vim.api.nvim_win_get_cursor(0)[1]
      local section = M.get_current_section(lines, line_num, config)

      if section == "commits" then
        local current_line = lines[line_num]
        if current_line then
          git_keymaps.handle_vgit_commit(current_line)
        end
      elseif section == "git_status" then
        local current_line = lines[line_num]
        if current_line then
          git_keymaps.handle_vgit_file_diff(current_line)
        end
      else
        -- Fall back to default visual mode behavior
        vim.cmd('normal! v')
      end
    end
  })
end

--- Set up context-sensitive keymaps (todo/commit review/beads)
---@param buf number Buffer number
---@param config table Nexus configuration
---@param render_callback function Function to re-render the buffer
local function setup_context_keymaps(buf, config, render_callback)
  local config_module = require('nexus.config')

  local todos_enabled = config_module.is_section_enabled("todos")
  local beads_enabled = config_module.is_section_enabled("beads_issues")

  -- Set up 'e' key if todos, beads, or commit review are enabled
  if todos_enabled or beads_enabled or config.show_commit_review then
    vim.api.nvim_buf_set_keymap(buf, 'n', 'e', '', {
      noremap = true,
      silent = true,
      callback = function()
        M.handle_e_key(buf, config, render_callback)
      end
    })
  end

  -- Set up 'd' key for context-aware "done" action (todos or beads)
  if todos_enabled or beads_enabled then
    vim.api.nvim_buf_set_keymap(buf, 'n', 'd', '', {
      noremap = true,
      silent = true,
      callback = function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local line_num = vim.api.nvim_win_get_cursor(0)[1]
        local section = M.get_current_section(lines, line_num, config)
        local current_line = lines[line_num]

        if section == "beads" and current_line then
          beads_keymaps.handle_done(current_line, line_num, buf, render_callback, config)
        elseif section == "todo" then
          local todo_id = todo_component.get_todo_id_from_line_num(line_num)
          if todo_id then
            todo_keymaps.handle_done(todo_id, buf, render_callback, config)
          end
        end
      end
    })
  end

  -- Set up todo-specific '!' key for toggle important (only if todos enabled)
  if todos_enabled then
    vim.api.nvim_buf_set_keymap(buf, 'n', '!', '', {
      noremap = true,
      silent = true,
      callback = function()
        local line_num = vim.api.nvim_win_get_cursor(0)[1]
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local section = M.get_current_section(lines, line_num, config)
        if section == "todo" then
          local todo_id = todo_component.get_todo_id_from_line_num(line_num)
          if todo_id then
            todo_keymaps.handle_important(todo_id, buf, render_callback, config)
          end
        end
      end
    })
  end

  -- Set up todo-specific 'D' key for delete (only if todos enabled)
  if todos_enabled then
    vim.api.nvim_buf_set_keymap(buf, 'n', 'D', '', {
      noremap = true,
      silent = true,
      callback = function()
        local line_num = vim.api.nvim_win_get_cursor(0)[1]
        local todo_id = todo_component.get_todo_id_from_line_num(line_num)
        todo_keymaps.handle_delete(todo_id, buf, render_callback, config)
      end
    })
  end

  -- Set up 'E' key for context-aware bulk action (todo edit-all or beads browse epics)
  if todos_enabled or beads_enabled then
    vim.api.nvim_buf_set_keymap(buf, 'n', 'E', '', {
      noremap = true,
      silent = true,
      callback = function()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local line_num = vim.api.nvim_win_get_cursor(0)[1]
        local section = M.get_current_section(lines, line_num, config)

        if section == "todo" then
          todo_keymaps.handle_edit_all(buf, render_callback, config)
        elseif section == "beads" then
          beads_keymaps.handle_browse_epics(buf, render_callback, config)
        end
      end
    })
  end
end

--- Set up Linear-specific keymaps
---@param buf number Buffer number
---@param config table Nexus configuration
---@param render_callback function Function to re-render the buffer
local function setup_linear_keymaps(buf, config, render_callback)
  if not (config.linear and config.linear.enabled) then return end

  vim.api.nvim_buf_set_keymap(buf, 'n', 'p', '', {
    noremap = true,
    silent = true,
    callback = function()
      linear_keymaps.handle_project_selection(buf, render_callback, config)
    end
  })
end

--- Set up Huly setup keymap (always available for initial configuration)
---@param buf number Buffer number
---@param config table Nexus configuration
---@param render_callback function Function to re-render the buffer
local function setup_huly_setup_keymap(buf, config, render_callback)
  vim.api.nvim_buf_set_keymap(buf, 'n', 'H', '', {
    noremap = true,
    silent = true,
    callback = function()
      huly_keymaps.handle_setup(buf, render_callback, config)
    end
  })
end

--- Set up Huly-specific keymaps
---@param buf number Buffer number
---@param config table Nexus configuration
---@param render_callback function Function to re-render the buffer
local function setup_huly_keymaps(buf, config, render_callback)
  if not (config.huly and config.huly.enabled) then return end

  vim.api.nvim_buf_set_keymap(buf, 'n', 'w', '', {
    noremap = true,
    silent = true,
    callback = function()
      huly_keymaps.handle_workspace_selection(buf, render_callback, config)
    end
  })

  vim.api.nvim_buf_set_keymap(buf, 'n', 'p', '', {
    noremap = true,
    silent = true,
    callback = function()
      huly_keymaps.handle_project_selection(buf, render_callback, config)
    end
  })
  -- Note: 's' key is handled in setup_git_keymaps with context-awareness
end

--- Set up Beads-specific keymaps
---@param buf number Buffer number
---@param config table Nexus configuration
---@param render_callback function Function to re-render the buffer
local function setup_beads_keymaps(buf, config, render_callback)
  local config_module = require('nexus.config')
  if not config_module.is_section_enabled("beads_issues") then return end

  -- Note: 'E' key moved to setup_context_keymaps for section-aware dispatch

  -- 'R' key - Show ready issues
  vim.api.nvim_buf_set_keymap(buf, 'n', 'R', '', {
    noremap = true,
    silent = true,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local line_num = vim.api.nvim_win_get_cursor(0)[1]
      local section = M.get_current_section(lines, line_num, config)

      if section == "beads" then
        beads_keymaps.handle_show_ready(buf, render_callback, config)
      end
    end
  })

  -- Note: 's', 'c', 'd', 'e' keys are handled in context-aware functions above
end

--- Set up exit keymaps (q/<Esc>)
---@param buf number Buffer number
local function setup_exit_keymaps(buf)
  -- Set up async quit keymaps
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.async_quit()
    end
  })

  -- Note: <Esc> keymap removed to prevent accidental quitting
end

--- Set up minimal keymaps for immediate interaction (before git data loads)
--- Only includes quit and refresh - no file navigation or context-sensitive keys
---@param buf number Buffer number
---@param config table Nexus configuration
function M.setup_minimal_keymaps(buf, config)
  -- Exit keymap - available immediately
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.async_quit()
    end
  })

  -- Refresh keymap - triggers full async reload
  vim.api.nvim_buf_set_keymap(buf, 'n', 'r', '', {
    noremap = true,
    silent = true,
    callback = function()
      local nexus = require('nexus')
      nexus.refresh_buffer(buf)
    end
  })

  logger.debug('KEYMAPS', 'Minimal keymaps set up for buffer ' .. buf)
end

--- Set up main Enter keymap
---@param buf number Buffer number
---@param files table Git status files
---@param config table Nexus configuration
---@param is_git_repo boolean Whether current directory is a git repo
---@param render_callback function Function to re-render the buffer
local function setup_enter_keymap(buf, files, config, is_git_repo, render_callback)
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.handle_enter_key(buf, files, config, is_git_repo, render_callback)
    end
  })
end

--- Main keymap setup function - coordinates all keymap registration
---@param buf number Buffer number
---@param files table Git status files
---@param config table Nexus configuration
---@param is_git_repo boolean Whether current directory is a git repo
---@param render_callback function Function to re-render the buffer
---@param section_ranges table Section ranges for navigation
function M.setup_keymaps(buf, files, config, is_git_repo, render_callback, section_ranges)
  -- Calculate logo section end
  local logo_lines = logo.get_neovim_logo(config)
  local logo_end_line = #logo_lines
  
  -- Set up all keymap categories
  setup_enter_keymap(buf, files, config, is_git_repo, render_callback)
  setup_exit_keymaps(buf)
  setup_basic_navigation_keymaps(buf, logo_end_line, section_ranges)
  setup_fold_keymaps(buf)
  setup_section_navigation_keymaps(buf, config, logo_end_line, section_ranges)
  
  -- Git-specific keymaps (only in git repositories)
  if is_git_repo then
    setup_git_keymaps(buf, config, render_callback)
    setup_context_keymaps(buf, config, render_callback)
    setup_linear_keymaps(buf, config, render_callback)
    setup_huly_keymaps(buf, config, render_callback)
    setup_beads_keymaps(buf, config, render_callback)
  end

  -- Huly setup keymap (always available, regardless of git repo or enabled state)
  local config_module = require('nexus.config')
  if config_module.is_section_enabled("huly_issues") then
    setup_huly_setup_keymap(buf, config, render_callback)
  end

  -- Config menu keymap (always available)
  vim.api.nvim_buf_set_keymap(buf, 'n', ',', '', {
    noremap = true,
    silent = true,
    callback = function()
      local config_menu = require('nexus.config_menu')
      config_menu.open()
    end
  })
end

--- Async quit function - only quits when Nexus is the only real buffer
function M.async_quit()
  -- Get list of all buffers
  local buffers = vim.api.nvim_list_bufs()
  local real_buffers = {}
  
  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local buftype = vim.api.nvim_buf_get_option(bufnr, 'buftype')
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      
      -- Count buffers that are not special (nofile, quickfix, etc.) and not empty unnamed buffers
      if buftype == '' and (bufname ~= '' or vim.api.nvim_buf_get_option(bufnr, 'modified')) then
        table.insert(real_buffers, bufnr)
      end
    end
  end
  
  -- If there are real buffers besides Nexus, just close Nexus
  if #real_buffers > 0 then
    vim.cmd('bdelete')
  else
    -- No other real buffers, quit Neovim
    vim.cmd('quit')
  end
end

--- Async esc function  
function M.async_esc()
  -- Currently disabled to prevent accidental quitting
  -- Could be implemented similar to async_quit if needed
end

--- Show commit details popup (legacy compatibility function)
---@param commit_line string The line containing commit information
function M.show_commit_details(commit_line)
  commit_popup.show_commit_details(commit_line)
end

--- Show Linear issue details popup (legacy compatibility function) 
---@param issue table The Linear issue object
---@param config table Nexus configuration
function M.show_linear_issue_details(issue, config)
  linear_popup.show_linear_issue_details(issue, config)
end

--- Handle commit review status
---@param commit_line string The line containing commit information
---@param buf number Buffer number
---@param render_callback function Function to re-render the buffer
---@param config table Nexus configuration
function M.handle_commit_review_status(commit_line, buf, render_callback, config)
  -- Extract commit hash from the line (accounting for review icons)
  local hash = commit_line:match("%s*[☐✓⚠]?%s*([a-f0-9]+)")
  if not hash then
    vim.notify("Could not extract commit hash from line", vim.log.levels.ERROR)
    return
  end
  
  -- Check current review status
  local git_commits = require('nexus.git.commits')
  local current_status = git_commits.get_commit_review_status(hash)
  
  -- Prepare action options based on current status
  local options = {}
  local actions = {}
  
  if current_status == "reviewed" then
    table.insert(options, "Mark as needs attention")
    table.insert(actions, "needs_attention")
    table.insert(options, "Mark as unreviewed")
    table.insert(actions, "unreviewed")
  elseif current_status == "needs_attention" then
    table.insert(options, "Mark as reviewed")
    table.insert(actions, "reviewed")
    table.insert(options, "Mark as unreviewed")
    table.insert(actions, "unreviewed")
  else -- unreviewed
    table.insert(options, "Mark as reviewed")
    table.insert(actions, "reviewed")
    table.insert(options, "Mark as needs attention")
    table.insert(actions, "needs_attention")
  end
  
  -- Show action selection dialog
  vim.ui.select(options, {
    prompt = string.format('Commit %s (%s):', hash:sub(1, 7), current_status:gsub('_', ' '))
  }, function(choice)
    if not choice then return end
    
    local choice_index = nil
    for i, option in ipairs(options) do
      if option == choice then
        choice_index = i
        break
      end
    end
    
    if not choice_index then return end
    
    local action = actions[choice_index]
    local success = false
    local status_message = ""
    
    if action == "reviewed" then
      success = git_commits.mark_commit_reviewed(hash)
      status_message = "marked as reviewed"
    elseif action == "needs_attention" then
      success = git_commits.mark_commit_needs_attention(hash)
      status_message = "marked as needs attention"
    elseif action == "unreviewed" then
      success = git_commits.mark_commit_unreviewed(hash)
      status_message = "marked as unreviewed"
    end
    
    if success then
      vim.notify(string.format("Commit %s %s", hash:sub(1, 7), status_message))
      -- Refresh git state and re-render
      git_state.force_refresh(config)
      render_callback(buf)
    else
      vim.notify("Failed to update commit review status", vim.log.levels.ERROR)
    end
  end)
end

return M
