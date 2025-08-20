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
  
  -- 5. Keyboard shortcuts highlighting
  M.apply_shortcuts_highlighting(buf, lines, config, section_ranges)
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

return M