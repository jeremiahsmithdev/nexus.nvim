local M = {}

local logo = require('gboard.ui.logo')
local dashboard = require('gboard.ui.dashboard')
local center = require('gboard.ui.center')
local git_utils = require('gboard.git.utils')
local git_status = require('gboard.git.status')
local git_commits = require('gboard.git.commits')

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
  
  -- Start with centered Neovim logo
  local logo_lines = logo.get_neovim_logo()
  local lines = center.center_lines(logo_lines, width)
  
  -- Add dashboard buttons if enabled
  local button_lines = dashboard.get_dashboard_buttons(config)
  if #button_lines > 0 then
    local centered_buttons = center.center_lines(button_lines, width)
    for _, line in ipairs(centered_buttons) do
      table.insert(lines, line)
    end
  end
  
  -- Calculate common alignment for git sections
  local git_sections_data = {}
  
  -- Prepare commits section if enabled
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
      table.insert(git_sections_data, commits_lines)
    end
  end
  
  -- Prepare git status section if enabled
  if is_git_repo and config.show_git_status then
    if #files == 0 then
      local no_changes_lines = {"No changes detected", ""}
      table.insert(git_sections_data, no_changes_lines)
    else
      local git_status_lines = {"Git Status:", ""}
      
      -- Calculate max filename width for alignment
      local max_filename_width = 0
      local file_data = {}
      for i, item in ipairs(files) do
        local added, deleted = git_status.get_diff_stats(item.file, item.status)
        local status_icon = git_status.format_status_icon(item.status)
        local full_name = status_icon .. " " .. item.file
        max_filename_width = math.max(max_filename_width, #full_name)
        table.insert(file_data, {
          item = item,
          added = added,
          deleted = deleted,
          status_icon = status_icon,
          full_name = full_name
        })
      end
      
      for i, data in ipairs(file_data) do
        local padding = string.rep(" ", max_filename_width - #data.full_name)
        local diff_stat = git_status.create_diff_stat(data.added, data.deleted, 40)
        
        local line = string.format("  %s%s%s", data.full_name, padding, diff_stat)
        table.insert(git_status_lines, line)
      end
      
      table.insert(git_sections_data, git_status_lines)
    end
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
  
  -- Add syntax highlighting with simple pattern matching
  M.apply_highlighting(buf, lines, config, is_git_repo, files)
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  return files
end

function M.apply_highlighting(buf, lines, config, is_git_repo, files)
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)
  
  -- 1. Logo highlighting - find logo lines (they contain ASCII art characters)
  local logo_ns = vim.api.nvim_create_namespace('gboard_logo')
  for i, line in ipairs(lines) do
    if line:match('[_/\\`\'"]') and line:match('__') then -- Logo contains these ASCII art patterns
      vim.api.nvim_buf_add_highlight(buf, logo_ns, 'Type', i - 1, 0, -1)
    end
  end
  
  -- 2. Button highlighting - find button lines
  if config.show_dashboard_buttons then
    local button_ns = vim.api.nvim_create_namespace('gboard_buttons')
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
    local commits_ns = vim.api.nvim_create_namespace('gboard_commits')
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
  if is_git_repo and config.show_git_status and files then
    local git_ns = vim.api.nvim_create_namespace('gboard_git_status')
    local git_status_line = nil
    for i, line in ipairs(lines) do
      if line:match('Git Status:') then
        git_status_line = i
        break
      end
    end
    
    if git_status_line then
      for i, file_item in ipairs(files) do
        local line_num = git_status_line + 1 + i -- +1 for empty line after "Git Status:", +i for file index
        local line_content = lines[line_num]
        
        if line_content then
          -- Find the status characters in the line
          local status_start = line_content:find('[MADRCU?]')
          if status_start then
            local color_group = git_status.get_status_color(file_item.status)
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
  end
end

return M