local M = {}

local logger = require('nexus.logger')

-- Async loading state
local loading_jobs = {}
local loading_buffers = {}

-- Show immediate UI with loading placeholders
function M.render_immediate_ui(buf, config)
  local logo = require('nexus.ui.logo')
  local center = require('nexus.ui.center')
  local layout = require('nexus.render.layout')
  
  -- Get display width
  local width = layout.get_display_width()
  
  -- Build immediate content (no git operations)
  local lines = {}
  
  -- Add logo immediately
  local logo_lines = logo.get_neovim_logo(config)
  local centered_logo = center.center_lines(logo_lines, width)
  for _, line in ipairs(centered_logo) do
    table.insert(lines, line)
  end
  
  -- Add some spacing
  table.insert(lines, "")
  
  -- Add dashboard buttons if enabled
  local config_module = require('nexus.config')
  if config_module.is_section_enabled("dashboard_buttons") then
    local buttons = {
      "  Find file",
      "  Recently opened files", 
      "  Find word",
      "  New file",
      "  Bookmarks",
      "  Restore session"
    }
    
    local centered_buttons = center.center_lines(buttons, width)
    for _, line in ipairs(centered_buttons) do
      table.insert(lines, line)
    end
    
    table.insert(lines, "")
  end
  
  -- Add loading placeholders for git data (with centering to match final layout)
  local loading_sections = {}

  if config_module.is_section_enabled("recent_commits") then
    table.insert(loading_sections, "Recent Commits:")
    table.insert(loading_sections, "")
    table.insert(loading_sections, "  Loading commits...")
    table.insert(loading_sections, "")
  end

  if config_module.is_section_enabled("git_status") then
    table.insert(loading_sections, "Git Status:")
    table.insert(loading_sections, "")
    table.insert(loading_sections, "  Loading git status...")
    table.insert(loading_sections, "")
  end

  -- Apply centering to loading sections (similar to layout.lua git sections)
  if #loading_sections > 0 then
    local max_loading_line = 0
    for _, line in ipairs(loading_sections) do
      max_loading_line = math.max(max_loading_line, #line)
    end

    -- Estimate typical git section width for better alignment (status lines are ~40-60 chars)
    local estimated_width = math.max(max_loading_line, 50)
    local left_padding = math.max(0, math.floor((width - estimated_width) / 2))
    local padding_str = string.rep(" ", left_padding)

    for _, line in ipairs(loading_sections) do
      table.insert(lines, padding_str .. line)
    end
  end
  
  -- Set buffer content immediately
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Apply immediate highlighting
  M.apply_immediate_highlighting(buf, logo_lines, config)
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  logger.debug('ASYNC_LOADER', 'Immediate UI rendered')
  return lines
end

-- Apply highlighting for immediate content
function M.apply_immediate_highlighting(buf, logo_lines, config)
  local ns_id = vim.api.nvim_create_namespace('nexus_immediate')
  
  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  
  -- Get current buffer lines for safe highlighting
  local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  
  -- Highlight logo
  for i = 1, #logo_lines do
    if i <= #current_lines and current_lines[i] then
      local line_len = #current_lines[i]
      if line_len > 0 then
        vim.api.nvim_buf_set_extmark(buf, ns_id, i - 1, 0, {
          end_col = line_len,
          hl_group = config.logo_color or 'Type',
          strict = false
        })
      end
    end
  end
  
  -- Highlight loading text with subtle color
  for i, line in ipairs(current_lines) do
    if line:match("Loading") then
      local line_len = #line
      if line_len > 0 then
        vim.api.nvim_buf_set_extmark(buf, ns_id, i - 1, 0, {
          end_col = line_len,
          hl_group = 'Comment',
          strict = false
        })
      end
    end
  end
end

-- Start async git data loading
function M.load_git_data_async(buf, config, callback)
  -- Cancel any existing job for this buffer
  if loading_jobs[buf] then
    vim.fn.jobstop(loading_jobs[buf])
    loading_jobs[buf] = nil
  end
  
  -- Mark buffer as loading
  loading_buffers[buf] = true
  
  -- Create async git command
  -- Handle nil/0 count as "show default 3 commits"
  local commit_count = config.recent_commits_count
  if not commit_count or commit_count < 1 then
    commit_count = 3
  end

  local cmd = {
    'sh', '-c',
    'git rev-parse --is-inside-work-tree 2>/dev/null && echo "---STATUS---" && ' ..
    'git status --porcelain=v1 2>/dev/null && echo "---COMMITS---" && ' ..
    'git log --oneline --decorate -' .. commit_count .. ' 2>/dev/null && ' ..
    'echo "---DIFFSTAT---" && git diff --numstat 2>/dev/null'
  }
  
  local output = {}
  
  -- Start async job
  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= '' then
            table.insert(output, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        logger.warn('ASYNC_LOADER', 'Git command stderr: ' .. table.concat(data, ' '))
      end
    end,
    on_exit = function(_, exit_code)
      loading_jobs[buf] = nil
      loading_buffers[buf] = nil
      
      if exit_code == 0 then
        -- Parse the output asynchronously
        vim.schedule(function()
          local parsed_data = M.parse_async_git_output(output)
          if callback then
            callback(parsed_data)
          end
        end)
      else
        logger.warn('ASYNC_LOADER', 'Git command failed with exit code: ' .. exit_code)
        -- Still call callback with empty data
        vim.schedule(function()
          if callback then
            callback({files = {}, commits = {}, is_git_repo = false})
          end
        end)
      end
    end
  })
  
  if job_id <= 0 then
    logger.error('ASYNC_LOADER', 'Failed to start git job')
    loading_buffers[buf] = nil
    if callback then
      callback({files = {}, commits = {}, is_git_repo = false})
    end
    return
  end
  
  loading_jobs[buf] = job_id
  logger.debug('ASYNC_LOADER', 'Started async git job: ' .. job_id)
end

-- Parse async git output
function M.parse_async_git_output(output)
  local sections = {}
  local current_section = nil
  local current_content = {}
  local is_git_repo = false
  
  for _, line in ipairs(output) do
    if line == '---STATUS---' then
      if current_section then
        sections[current_section] = current_content
      end
      current_section = 'status'
      current_content = {}
    elseif line == '---COMMITS---' then
      if current_section then
        sections[current_section] = current_content
      end
      current_section = 'commits'
      current_content = {}
    elseif line == '---DIFFSTAT---' then
      if current_section then
        sections[current_section] = current_content
      end
      current_section = 'diffstat'
      current_content = {}
    else
      if current_section then
        table.insert(current_content, line)
      elseif line:match('true') then
        is_git_repo = true
      end
    end
  end
  
  -- Don't forget the last section
  if current_section then
    sections[current_section] = current_content
  end
  
  -- Parse files
  local files = {}
  if sections.status then
    local diffstats = M.parse_diffstats_async(sections.diffstat or {})
    for _, line in ipairs(sections.status) do
      if line ~= '' then
        local status = line:sub(1, 2)
        local file = line:sub(4)
        local stats = diffstats[file] or {added = 0, deleted = 0}
        
        table.insert(files, {
          status = status,
          file = file,
          added = stats.added,
          deleted = stats.deleted
        })
      end
    end
  end
  
  -- Parse commits
  local commits = {}
  if sections.commits then
    for _, line in ipairs(sections.commits) do
      if line ~= '' then
        -- First extract hash and rest of line
        local hash, rest = line:match('^([%w]+)%s+(.*)')
        if hash and rest then
          -- Check if rest starts with decoration (parentheses)
          local decoration, message = rest:match('^(%([^%)]+%))%s*(.*)')
          if not decoration then
            -- No decoration, rest is the message
            message = rest
          end
          table.insert(commits, {
            hash = hash,
            message = message or '',
            decoration = decoration
          })
        end
      end
    end
  end
  
  return {
    files = files,
    commits = commits,
    is_git_repo = is_git_repo
  }
end

-- Parse diff stats from async output
function M.parse_diffstats_async(diffstat_lines)
  local stats = {}
  
  for _, line in ipairs(diffstat_lines) do
    local added, deleted, file = line:match('(%d+)%s+(%d+)%s+(.+)')
    if added and deleted and file then
      stats[file] = {
        added = tonumber(added) or 0,
        deleted = tonumber(deleted) or 0
      }
    end
  end
  
  return stats
end

-- Update buffer with loaded git data
function M.update_buffer_with_git_data(buf, config, git_data)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  -- Use the regular render system with pre-loaded data
  local render = require('nexus.render')

  -- Create a temporary git state for rendering
  local cached_files = git_data.files

  -- Re-render with actual data
  render.render_git_status(buf, config, cached_files)
  
  logger.debug('ASYNC_LOADER', string.format('Updated buffer with %d files, %d commits', 
    #git_data.files, #git_data.commits))
end

-- Check if buffer is currently loading
function M.is_loading(buf)
  return loading_buffers[buf] == true
end

-- Cancel loading for a buffer
function M.cancel_loading(buf)
  if loading_jobs[buf] then
    vim.fn.jobstop(loading_jobs[buf])
    loading_jobs[buf] = nil
  end
  loading_buffers[buf] = nil
end

-- Clean up completed jobs
function M.cleanup()
  -- Remove completed jobs
  for buf, job_id in pairs(loading_jobs) do
    if vim.fn.jobwait({job_id}, 0)[1] ~= -1 then
      loading_jobs[buf] = nil
    end
  end
  
  -- Remove invalid buffers
  for buf, _ in pairs(loading_buffers) do
    if not vim.api.nvim_buf_is_valid(buf) then
      loading_buffers[buf] = nil
    end
  end
end

return M