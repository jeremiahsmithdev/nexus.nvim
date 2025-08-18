local M = {}

local logo = require('gboard.ui.logo')
local dashboard = require('gboard.ui.dashboard')
local center = require('gboard.ui.center')
local git_status = require('gboard.git.status')
local git_commits = require('gboard.git.commits')

function M.render_git_status(buf, config)
  local files = git_status.parse_git_status()
  
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
  
  -- Add recent commits section
  if config.show_claude_conversations then
    -- Claude conversations disabled for now
    local claude = require('gboard.claude')
    local conversations = claude.get_claude_conversations(config)
    if #conversations > 0 then
      table.insert(lines, "Recent Claude Conversations:")
      table.insert(lines, "")
      
      -- Add column headers
      table.insert(lines, "    Modified     Created      Messages  Summary")
      
      local max_conversations = config.recent_commits_count or 3
      for i = 1, math.min(max_conversations, #conversations) do
        local conv = conversations[i]
        local summary = conv.content:sub(1, 50) -- Truncate long summaries
        if #conv.content > 50 then
          summary = summary .. "..."
        end
        
        local line = string.format(" %d. %-12s %-12s %8d  %s", 
          i, conv.modified, conv.created, conv.messages, summary)
        table.insert(lines, line)
      end
      table.insert(lines, "")
    end
  elseif config.show_recent_commits then
    -- Show recent git commits
    local commits = git_commits.get_git_log(config)
    if #commits > 0 then
      table.insert(lines, "Recent Commits:")
      table.insert(lines, "")
      
      for i, commit in ipairs(commits) do
        local line
        if commit.decoration then
          line = string.format("  %s (%s) %s", commit.hash, commit.decoration, commit.message)
        else
          line = string.format("  %s %s", commit.hash, commit.message)
        end
        table.insert(lines, line)
      end
      table.insert(lines, "")
    end
  end
  
  if config.show_git_status then
    if #files == 0 then
      table.insert(lines, "No changes detected")
      table.insert(lines, "")
    else
      table.insert(lines, "Git Status:")
      table.insert(lines, "")
      
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
        table.insert(lines, line)
      end
    end
  end
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Add syntax highlighting with isolated sections
  M.apply_highlighting(buf, lines, config)
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  return files
end

function M.apply_highlighting(buf, lines, config)
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)
  
  local line_offset = 0
  
  -- 1. Neovim logo section
  local logo_ns = vim.api.nvim_create_namespace('gboard_logo')
  local logo_lines = logo.get_neovim_logo()
  for i = 1, #logo_lines do
    if i <= 6 then -- Only highlight the actual logo lines, not the empty line
      vim.api.nvim_buf_add_highlight(buf, logo_ns, 'Type', line_offset + i - 1, 0, -1)
    end
  end
  line_offset = line_offset + #logo_lines
  
  -- 2. Dashboard buttons section - ALL GRAY
  if config.show_dashboard_buttons then
    local button_ns = vim.api.nvim_create_namespace('gboard_buttons')
    local button_lines = dashboard.get_dashboard_buttons(config)
    local button_start_line = #logo_lines  -- Start right after logo (0-indexed)
    
    for i, button_line in ipairs(button_lines) do
      if button_line ~= "" then -- Skip empty lines
        local line_num = button_start_line + i - 1
        
        -- Make entire line gray
        vim.api.nvim_buf_add_highlight(buf, button_ns, 'Comment', line_num, 0, -1)
      end
    end
    line_offset = line_offset + #button_lines
  end
  
  -- 3. Commits section
  if not config.show_claude_conversations then
    local commits_ns = vim.api.nvim_create_namespace('gboard_commits')
    local commits_start_line = nil
    for i, line in ipairs(lines) do
      if line == "Recent Commits:" then
        commits_start_line = i + 1 -- +1 for empty line after "Recent Commits:"
        break
      end
    end
    
    if commits_start_line then
      local commits = git_commits.get_git_log(config)
      for i, commit in ipairs(commits) do
        local line_num = commits_start_line + i - 1
        local line_content = lines[line_num + 1]
        
        if line_content then
          -- Highlight commit hash in yellow
          local hash_end = line_content:find(' ', 3) -- Find space after hash
          if hash_end then
            vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Number', line_num, 2, hash_end - 1)
          end
          
          -- Highlight decoration (HEAD, branches) in different colors
          if commit.decoration then
            local decoration_start = line_content:find('(', 1, true)
            local decoration_end = line_content:find(')', 1, true)
            if decoration_start and decoration_end then
              -- Highlight the parentheses in default color, content inside in cyan
              vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Special', line_num, decoration_start - 1, decoration_start)
              vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Special', line_num, decoration_end - 1, decoration_end)
              
              -- Highlight HEAD in bold/bright
              local decoration_content = commit.decoration
              if decoration_content:match('HEAD') then
                local head_start = line_content:find('HEAD', decoration_start)
                if head_start then
                  vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Title', line_num, head_start - 1, head_start + 3)
                end
              end
              
              -- Highlight branch names in cyan
              local branch_parts = vim.split(decoration_content, ', ')
              for _, part in ipairs(branch_parts) do
                if not part:match('HEAD') and not part:match('tag:') then
                  local branch_start = line_content:find(part, decoration_start, true)
                  if branch_start then
                    vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Function', line_num, branch_start - 1, branch_start + #part - 1)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  
  -- 4. Git Status section
  local git_ns = vim.api.nvim_create_namespace('gboard_git_status')
  local git_status_line = nil
  for i, line in ipairs(lines) do
    if line == "Git Status:" then
      git_status_line = i
      break
    end
  end
  
  if git_status_line then
    local files = git_status.parse_git_status()
    for i, item in ipairs(files) do
      local line_num = git_status_line + 1 + i - 1 -- +1 for empty line after "Git Status:"
      local line_content = lines[line_num + 1]
      
      -- Highlight status (beginning of line)
      local status_end = 5  -- "  XX "
      local color_group = git_status.get_status_color(item.status)
      vim.api.nvim_buf_add_highlight(buf, git_ns, color_group, line_num, 0, status_end)
      
      -- Highlight + and - chars (and their numbers)
      for i = 1, #line_content do
        local char = line_content:sub(i, i)
        if char == '+' then
          vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticOk', line_num, i - 1, i)
        elseif char == '-' then
          vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticError', line_num, i - 1, i)
        elseif char:match('%d') then
          -- Color numbers based on preceding + or -
          local j = i - 1
          while j > 0 and line_content:sub(j, j):match('%d') do
            j = j - 1
          end
          if j > 0 then
            local sign = line_content:sub(j, j)
            if sign == '+' then
              vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticOk', line_num, i - 1, i)
            elseif sign == '-' then
              vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticError', line_num, i - 1, i)
            end
          end
        end
      end
    end
  end
end

return M