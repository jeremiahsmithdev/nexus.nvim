local M = {}

local git_status = require('nexus.git.status')
local folding = require('nexus.ui.folding')

-- Main highlighting function - applies all highlighting types
function M.apply_highlighting(buf, lines, config, is_git_repo, files, logo_section, section_ranges)
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)
  
  -- 1. Logo highlighting - highlight entire logo section
  M.apply_logo_highlighting(buf, lines, config, logo_section)
  
  -- 2. Button highlighting - find button lines
  M.apply_button_highlighting(buf, lines, config)
  
  -- 3. Commits highlighting
  M.apply_commits_highlighting(buf, lines, config, is_git_repo)
  
  -- 4. Git status highlighting  
  M.apply_git_status_highlighting(buf, lines, config, is_git_repo, files)
  
  -- 5. Linear issues highlighting
  M.apply_linear_highlighting(buf, lines, config)
  
  -- 6. Keyboard shortcuts highlighting
  M.apply_shortcuts_highlighting(buf, lines, config, section_ranges)
  
  -- 7. Todo highlighting
  M.apply_todo_highlighting(buf, lines, config)
end

-- Logo highlighting
function M.apply_logo_highlighting(buf, lines, config, logo_section)
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
end

-- Button highlighting
function M.apply_button_highlighting(buf, lines, config)
  if not config.show_dashboard_buttons then
    return
  end
  
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

-- Commits highlighting
function M.apply_commits_highlighting(buf, lines, config, is_git_repo)
  if not is_git_repo or not config.show_recent_commits then
    return
  end
  
  local commits_ns = vim.api.nvim_create_namespace('nexus_commits')
  for i, line in ipairs(lines) do
    -- Check for review status icons first
    if config.show_commit_review then
      local review_check = line:find('✓')
      local review_box = line:find('☐')
      
      if review_check then
        vim.api.nvim_buf_add_highlight(buf, commits_ns, 'DiagnosticOk', i - 1, review_check - 1, review_check)
      elseif review_box then
        vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Comment', i - 1, review_box - 1, review_box)
      end
    end
    
    -- Look for commit hash pattern (7+ hex chars after spaces, accounting for review icons)
    local hash_start, hash_end = line:find('%s+[☐✓]?%s*([a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+)')
    if hash_start and hash_end then
      -- Find the actual hash position within the captured group
      local actual_hash_start = line:find('[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+', hash_start)
      if actual_hash_start then
        local actual_hash_end = actual_hash_start + 6 -- 7 char hash - 1
        vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Number', i - 1, actual_hash_start - 1, actual_hash_end)
      end
      
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

-- Git status highlighting that works with processed data
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
        -- Special case for MM (staged + unstaged): first M green, second M red
        if data.item.status == 'MM' then
          vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticOk', line_num - 1, status_start - 1, status_start)  -- First M green
          vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticError', line_num - 1, status_start, status_start + 1)  -- Second M red
        else
          local color_group = git_status.get_status_color(data.item.status)
          vim.api.nvim_buf_add_highlight(buf, git_ns, color_group, line_num - 1, status_start - 1, status_start + 1)
        end
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

-- Linear issues highlighting
function M.apply_linear_highlighting(buf, lines, config)
  if not config.linear or not config.linear.enabled then
    return
  end
  
  local linear_ns = vim.api.nvim_create_namespace('nexus_linear')
  local linear_component = require('nexus.render.components.linear')
  local linear_state = require('nexus.state.linear')
  
  -- Get current issues for reference
  local issues = linear_state.get_issues()
  if not issues then
    return
  end
  
  -- Find Linear Issues section
  local linear_section_start = nil
  for i, line in ipairs(lines) do
    if line:match('Linear Issues:') then
      linear_section_start = i
      break
    end
  end
  
  if not linear_section_start then
    return
  end
  
  -- Apply highlighting to each issue line
  for i = linear_section_start + 2, #lines do -- +2 to skip header and empty line
    local line_content = lines[i]
    if not line_content or line_content == "" then
      break -- End of section
    end
    
    local is_issue, identifier = linear_component.is_linear_issue_line(line_content)
    if is_issue and identifier then
      local issue = linear_component.get_issue_from_line(line_content, issues)
      if issue then
        -- Highlight state icon at the beginning
        local state_icon_end = line_content:find('%s', 3) or 4 -- Find first space after icons
        if state_icon_end > 3 then
          local state_color = linear_component.get_state_color(issue.state)
          vim.api.nvim_buf_add_highlight(buf, linear_ns, state_color, i - 1, 2, state_icon_end - 1)
        end
        
        -- Highlight priority icon if present (after state, before identifier)
        if issue.priority and type(issue.priority) == "number" and issue.priority >= 2 then
          local priority_start = line_content:find('[🟢🟡🟠🔴]', state_icon_end or 4)
          if priority_start then
            local priority_color = linear_component.get_priority_color(issue.priority)
            vim.api.nvim_buf_add_highlight(buf, linear_ns, priority_color, i - 1, priority_start - 1, priority_start)
          end
        end
        
        -- Highlight identifier [LIN-123]
        local id_start, id_end = line_content:find('%[' .. vim.pesc(identifier) .. '%]')
        if id_start then
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'Number', i - 1, id_start - 1, id_end)
        end
        
        -- Highlight assignee (@username)
        local assignee_start, assignee_end = line_content:find('@[^)]+')
        if assignee_start then
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'Function', i - 1, assignee_start - 1, assignee_end)
        end
        
        -- Highlight estimate (Np)
        local estimate_start, estimate_end = line_content:find('%(%d+p%)')
        if estimate_start then
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'String', i - 1, estimate_start - 1, estimate_end)
        end
        
        -- Highlight cycle [CycleName]
        local cycle_start, cycle_end = line_content:find('%[[^]]+%]', (id_end or 0) + 1)
        if cycle_start then
          vim.api.nvim_buf_add_highlight(buf, linear_ns, 'Type', i - 1, cycle_start - 1, cycle_end)
        end
      end
    elseif line_content:match("Loading issues") then
      -- Highlight loading message
      vim.api.nvim_buf_add_highlight(buf, linear_ns, 'DiagnosticInfo', i - 1, 0, -1)
    elseif line_content:match("No issues found") then
      -- Highlight no issues message
      vim.api.nvim_buf_add_highlight(buf, linear_ns, 'Comment', i - 1, 0, -1)
    elseif line_content:match("No API key found") or line_content:match("Invalid API key") then
      -- Highlight API key setup messages as actionable
      vim.api.nvim_buf_add_highlight(buf, linear_ns, 'DiagnosticWarn', i - 1, 0, -1)
      -- Highlight the action hint
      local enter_start, enter_end = line_content:find("<Enter>")
      if enter_start then
        vim.api.nvim_buf_add_highlight(buf, linear_ns, 'String', i - 1, enter_start - 1, enter_end)
      end
    elseif line_content:match("❌") then
      -- Highlight other error messages
      vim.api.nvim_buf_add_highlight(buf, linear_ns, 'DiagnosticError', i - 1, 0, -1)
    end
  end
end

-- Keyboard shortcuts highlighting
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

-- Todo highlighting
function M.apply_todo_highlighting(buf, lines, config)
  if not config.show_todos then
    return
  end
  
  local todo_component = require('nexus.render.components.todo')
  
  -- Find Todo section
  for i, line in ipairs(lines) do
    if line:match('^%s*Todo:') then
      todo_component.apply_todo_highlighting(buf, i)
      break
    end
  end
end

return M