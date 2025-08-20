local M = {}

local logo = require('nexus.ui.logo')
local dashboard = require('nexus.ui.dashboard')
local shortcuts = require('nexus.ui.shortcuts')
local center = require('nexus.ui.center')
local git_utils = require('nexus.git.utils')
local git_status = require('nexus.git.status')
local git_commits = require('nexus.git.commits')
local folding = require('nexus.ui.folding')
local logger = require('nexus.logger')
local cursor = require('nexus.cursor')

function M.render_git_status(buf, config, cached_files)
  -- Check if we're in a git repository
  local is_git_repo = git_utils.is_git_repo()
  local files = {}
  
  if is_git_repo then
    files = cached_files or git_status.parse_git_status()
  end
  
  -- Get the actual display width (tmux pane width if in tmux, otherwise vim width)
  local width = vim.fn.winwidth(0) -- default to vim width
  
  if vim.env.TMUX then
    local pane_width = vim.fn.system("tmux display-message -p '#{pane_width}'"):gsub('\n', '')
    local tmux_width = tonumber(pane_width)
    if tmux_width then
      width = tmux_width
    end
  end
  
  -- Start with centered logo
  local logo_lines = logo.get_neovim_logo(config)
  local centered_logo = center.center_lines(logo_lines, width)
  local lines = {}
  
  -- Add centered logo lines to buffer
  for _, line in ipairs(centered_logo) do
    table.insert(lines, line)
  end
  
  -- Store logo section info for highlighting
  local logo_section = {
    start_line = 1,
    end_line = #centered_logo
  }
  
  -- Track section line ranges for highlighting
  local section_ranges = {}
  
  -- Build sections based on configuration order
  local sections = M.build_sections(config, is_git_repo, files)
  
  -- Separate button sections from git sections for different alignment
  local button_sections = {}
  local git_sections_data = {}
  
  for _, section_name in ipairs(config.section_order) do
    local section_data = sections[section_name]
    if section_data and #section_data > 0 then
      if section_name == "dashboard_buttons" or section_name == "keyboard_shortcuts" then
        table.insert(button_sections, {data = section_data, name = section_name})
      else
        table.insert(git_sections_data, section_data)
      end
    end
  end
  
  -- Add button sections with center alignment
  for _, section_info in ipairs(button_sections) do
    local centered_section
    if section_info.name == "keyboard_shortcuts" then
      -- Use individual centering for keyboard shortcuts (each line centered independently)
      centered_section = center.center_lines_individually(section_info.data, width)
    else
      -- Use block centering for other sections (like dashboard buttons)
      centered_section = center.center_lines(section_info.data, width)
    end
    
    local section_start = #lines + 1
    for _, line in ipairs(centered_section) do
      table.insert(lines, line)
    end
    local section_end = #lines
    
    -- Store section ranges for navigation
    section_ranges[section_info.name] = {
      start_line = section_start,
      end_line = section_end
    }
  end
  
  -- Find the longest line across all git sections to calculate common alignment
  local max_git_line_length = 0
  for _, section in ipairs(git_sections_data) do
    local section_max = center.longest_line(section)
    max_git_line_length = math.max(max_git_line_length, section_max)
  end
  
  -- Apply same left padding to all git sections
  if max_git_line_length > 0 then
    local left_padding = math.max(0, math.floor((width - max_git_line_length) / 2))
    local padding_str = string.rep(" ", left_padding)
    
    for _, section in ipairs(git_sections_data) do
      for _, line in ipairs(section) do
        table.insert(lines, padding_str .. line)
      end
    end
  end
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Render image logo if enabled (after buffer content is set)
  if config.logo_selection == "image" then
    logo.render_image_logo(buf, config, 0, 0)
  end
  
  -- Set up folding for git status overflow
  folding.setup_git_status_folding(buf, lines, config, files)
  
  -- Add syntax highlighting with section info
  M.apply_highlighting(buf, lines, config, is_git_repo, files, logo_section, section_ranges)
  
  -- Update cursor module with section ranges for dynamic shortcuts
  cursor.update_section_ranges(section_ranges)
  
  -- Set up dynamic shortcut updating on cursor movement (only if shortcuts are enabled)
  if config.show_keyboard_shortcuts then
    M.setup_dynamic_shortcuts(buf, config, is_git_repo, section_ranges)
  end
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  return files, section_ranges
end

-- Build all sections based on configuration
function M.build_sections(config, is_git_repo, files)
  local sections = {}
  
  -- Dashboard buttons section
  if config.show_dashboard_buttons then
    local button_lines = dashboard.get_dashboard_buttons(config)
    if #button_lines > 0 then
      sections.dashboard_buttons = button_lines
    end
  end
  
  -- Keyboard shortcuts section
  if config.show_keyboard_shortcuts then
    local shortcut_lines = shortcuts.get_keyboard_shortcuts(config, is_git_repo)
    if #shortcut_lines > 0 then
      sections.keyboard_shortcuts = shortcut_lines
    end
  end
  
  -- Recent commits section
  if is_git_repo and config.show_recent_commits then
    local commits = git_commits.get_git_log(config)
    if #commits > 0 then
      local commits_lines = {"Recent Commits:", ""}
      for i, commit in ipairs(commits) do
        local line
        if commit.decoration then
          line = string.format("  %s (%s) %s", commit.hash, commit.decoration, commit.message)
        else
          line = string.format("  %s %s", commit.hash, commit.message)
        end
        table.insert(commits_lines, line)
      end
      table.insert(commits_lines, "")
      sections.recent_commits = commits_lines
    end
  end
  
  -- Git status section
  if is_git_repo and config.show_git_status then
    if #files == 0 then
      local no_changes_lines = {"No changes detected", ""}
      sections.git_status = no_changes_lines
    else
      local git_status_lines = {"Git Status:", ""}
      
      -- Process files with optional limit
      local processed = folding.process_git_files(files, config.git_status_count)
      
      -- Render visible files
      for i, data in ipairs(processed.visible) do
        local padding = string.rep(" ", processed.max_filename_width - #data.full_name)
        local diff_stat = git_status.create_diff_stat(data.added, data.deleted, 40)
        
        local line = string.format("  %s%s%s", data.full_name, padding, diff_stat)
        table.insert(git_status_lines, line)
      end
      
      -- Add folded overflow content if files were hidden
      if #processed.hidden > 0 then
        logger.debug("GIT_STATUS", "Adding fold for hidden files", {
          total_files = #files,
          visible_count = #processed.visible,
          hidden_count = #processed.hidden
        })
        
        -- Add the hidden files directly (they will be folded with custom fold text)
        for i, data in ipairs(processed.hidden) do
          local padding = string.rep(" ", processed.max_filename_width - #data.full_name)
          local diff_stat = git_status.create_diff_stat(data.added, data.deleted, 40)
          local line = string.format("  %s%s%s", data.full_name, padding, diff_stat)
          table.insert(git_status_lines, line)
        end
      end
      
      sections.git_status = git_status_lines
    end
  end
  
  -- Claude conversations section (placeholder for future implementation)
  if config.show_claude_conversations then
    -- This would be implemented when the feature is added
    sections.claude_conversations = {"Claude Conversations:", "", "  (Feature not yet implemented)", ""}
  end
  
  return sections
end


function M.apply_highlighting(buf, lines, config, is_git_repo, files, logo_section, section_ranges)
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)
  
  -- 1. Logo highlighting - highlight entire logo section
  local logo_ns = vim.api.nvim_create_namespace('nexus_logo')
  local logo_color = config.logo_color or "String"
  if logo_section then
    for i = logo_section.start_line, logo_section.end_line do
      local line_content = lines[i]
      if line_content and #line_content > 0 then -- Only highlight non-empty lines
        vim.api.nvim_buf_add_highlight(buf, logo_ns, logo_color, i - 1, 0, -1)
      end
    end
  end
  
  -- 2. Button highlighting - find button lines
  if config.show_dashboard_buttons then
    local button_ns = vim.api.nvim_create_namespace('nexus_buttons')
    for i, line in ipairs(lines) do
      if line:match('Find file') or line:match('Recently opened') or line:match('Find word') or 
         line:match('New file') or line:match('Bookmarks') or line:match('Restore session') then
        -- Highlight the entire line gray
        vim.api.nvim_buf_add_highlight(buf, button_ns, 'Comment', i - 1, 0, -1)
        
        -- Find and highlight the icon green
        local icon_start, icon_end = line:find('[󰈞󰋚󰊄󰈔󰃃󰁯]')
        if icon_start then
          vim.api.nvim_buf_add_highlight(buf, button_ns, 'String', i - 1, icon_start - 1, icon_end)
        end
      end
    end
  end
  
  -- 3. Commits highlighting
  if is_git_repo and config.show_recent_commits then
    local commits_ns = vim.api.nvim_create_namespace('nexus_commits')
    for i, line in ipairs(lines) do
      -- Look for commit hash pattern (7+ hex chars after spaces)
      local hash_start, hash_end = line:find('%s+([a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+)')
      if hash_start and hash_end then
        vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Number', i - 1, hash_start, hash_end)
        
        -- Look for HEAD decoration
        local head_start, head_end = line:find('HEAD')
        if head_start then
          vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Title', i - 1, head_start - 1, head_end)
        end
        
        -- Look for branch names (simple approach)
        local paren_start, paren_end = line:find('%(.*%)')
        if paren_start and paren_end then
          -- Skip highlighting if it contains HEAD (already highlighted above)
          if not line:sub(paren_start, paren_end):match('HEAD') then
            vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Function', i - 1, paren_start - 1, paren_end)
          end
        end
      end
    end
  end
  
  -- 4. Git status highlighting  
  M.apply_git_status_highlighting(buf, lines, config, is_git_repo, files)
  
  -- 5. Keyboard shortcuts highlighting
  M.apply_shortcuts_highlighting(buf, lines, config, section_ranges)
end

-- Separate function for git status highlighting that works with processed data
function M.apply_git_status_highlighting(buf, lines, config, is_git_repo, files)
  if not is_git_repo or not config.show_git_status or not files or #files == 0 then
    return
  end

  local git_ns = vim.api.nvim_create_namespace('nexus_git_status')
  local git_status_start = nil
  
  -- Find Git Status section
  for i, line in ipairs(lines) do
    if line:match('Git Status:') then
      git_status_start = i
      break
    end
  end
  
  if not git_status_start then
    return
  end
  
  -- Process files to understand display order
  local processed = folding.process_git_files(files, config.git_status_count)
  local display_files = {}
  
  -- Add visible files first
  for _, data in ipairs(processed.visible) do
    table.insert(display_files, data)
  end
  
  -- Add hidden files (they are in the buffer even if folded)
  for _, data in ipairs(processed.hidden) do
    table.insert(display_files, data)
  end
  
  -- Apply highlighting to displayed files in correct order
  for display_index, data in ipairs(display_files) do
    local line_num = git_status_start + 1 + display_index -- +1 for empty line after "Git Status:"
    local line_content = lines[line_num]
    
    if line_content then
      -- Find the status characters in the line
      local status_start = line_content:find('[MADRCU?]')
      if status_start then
        local color_group = git_status.get_status_color(data.item.status)
        vim.api.nvim_buf_add_highlight(buf, git_ns, color_group, line_num - 1, status_start - 1, status_start + 1)
      end
      
      -- Highlight diff stats (+ and - chars)
      for j = 1, #line_content do
        local char = line_content:sub(j, j)
        if char == '+' then
          vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticOk', line_num - 1, j - 1, j)
        elseif char == '-' then
          vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticError', line_num - 1, j - 1, j)
        end
      end
    end
  end
end

-- Function to highlight keyboard shortcuts section in Comment color
function M.apply_shortcuts_highlighting(buf, lines, config, section_ranges)
  if not config.show_keyboard_shortcuts or not section_ranges or not section_ranges.keyboard_shortcuts then
    return
  end
  
  local shortcuts_ns = vim.api.nvim_create_namespace('nexus_shortcuts')
  local shortcuts_section = section_ranges.keyboard_shortcuts
  
  -- Highlight entire keyboard shortcuts section
  for i = shortcuts_section.start_line, shortcuts_section.end_line do
    local line_content = lines[i]
    if line_content and #line_content > 0 then -- Only highlight non-empty lines
      vim.api.nvim_buf_add_highlight(buf, shortcuts_ns, 'Comment', i - 1, 0, -1)
    end
  end
end

-- Set up dynamic shortcut updating on cursor movement
function M.setup_dynamic_shortcuts(buf, config, is_git_repo, section_ranges)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  -- Clear any existing autocommands for this buffer
  vim.api.nvim_clear_autocmds({
    group = vim.api.nvim_create_augroup("nexus_dynamic_shortcuts_" .. buf, { clear = true }),
    buffer = buf,
  })
  
  -- Set up autocommand to update shortcuts on cursor movement
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = vim.api.nvim_create_augroup("nexus_dynamic_shortcuts_" .. buf, { clear = false }),
    buffer = buf,
    callback = function()
      -- Only update if we're still in the correct buffer
      if vim.api.nvim_get_current_buf() == buf then
        shortcuts.update_contextual_shortcuts(buf, config, is_git_repo, section_ranges)
        
        -- Re-apply highlighting to the updated line
        M.apply_shortcuts_highlighting(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false), config, section_ranges)
      end
    end,
  })
  
  -- Initial update of contextual shortcuts
  shortcuts.update_contextual_shortcuts(buf, config, is_git_repo, section_ranges)
end

return M