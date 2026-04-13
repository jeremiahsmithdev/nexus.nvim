local M = {}

local logger = require('nexus.logger')

-- Helper function to categorize hidden files
local function categorize_hidden_files(hidden_files)
  local untracked_count = 0
  local unstaged_count = 0
  
  for _, file in ipairs(hidden_files) do
    if file.status == "??" then
      untracked_count = untracked_count + 1
    else
      unstaged_count = unstaged_count + 1
    end
  end
  
  return untracked_count, unstaged_count
end

-- Helper function to build overflow text for fold
local function build_overflow_text(untracked_count, unstaged_count)
  local overflow_parts = {}
  
  if untracked_count > 0 then
    table.insert(overflow_parts, string.format("%d Untracked files", untracked_count))
  end
  if unstaged_count > 0 then
    table.insert(overflow_parts, string.format("%d Changes not staged for commit", unstaged_count))
  end
  
  if #overflow_parts > 0 then
    return "+ " .. table.concat(overflow_parts, ", + ")
  end
  
  return nil
end

-- Process git files with optional limit, returns processed data in single pass
function M.process_git_files(files, limit)
  local git_status = require('nexus.git.status')
  local visible_files = {}
  local hidden_files = {}
  local all_file_data = {}
  
  -- Calculate max filename width across ALL files first
  local max_filename_width = 0
  for i, item in ipairs(files) do
    local status_icon = git_status.format_status_icon(item.status)
    local full_name = status_icon .. " " .. item.file
    max_filename_width = math.max(max_filename_width, #full_name)
  end
  
  -- Single pass: build data and separate visible/hidden
  for i, item in ipairs(files) do
    local added, deleted = git_status.get_diff_stats(item.file, item.status)
    local status_icon = git_status.format_status_icon(item.status)
    local full_name = status_icon .. " " .. item.file
    
    local file_data = {
      item = item,
      added = added,
      deleted = deleted,
      status_icon = status_icon,
      full_name = full_name,
      display_index = i -- Track original index for highlighting
    }
    
    table.insert(all_file_data, file_data)
    
    if not limit or i <= limit then
      table.insert(visible_files, file_data)
    else
      table.insert(hidden_files, file_data)
    end
  end
  
  return {
    visible = visible_files,
    hidden = hidden_files,
    all = all_file_data,
    max_filename_width = max_filename_width
  }
end

-- Main function to setup git status folding
function M.setup_git_status_folding(buf, lines, config, files)
  -- Early validation
  if not config.git_status_count or not files or #files <= config.git_status_count then
    return
  end
  
  -- Validate buffer
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    logger.error("FOLD", "Invalid buffer provided for folding setup")
    return
  end
  
  local success, result = pcall(function()
    -- Find the git status fold range
    local fold_start_line = nil
    local fold_end_line = nil
    local git_status_start = nil
    
    -- Find Git Status section
    for i, line in ipairs(lines) do
      if line:match('Git Status:') then
        git_status_start = i
        break
      end
    end
    
    if not git_status_start then
      logger.warn("FOLD", "Could not find Git Status section for folding")
      return
    end
    
    -- Calculate fold range - from first hidden file to last hidden file
    local visible_count = math.min(config.git_status_count, #files)
    fold_start_line = git_status_start + 2 + visible_count -- +2 for title and empty line, +visible_count for shown files
    
    -- Validate fold range
    local hidden_count = #files - config.git_status_count
    fold_end_line = fold_start_line + hidden_count - 1
    
    -- Additional bounds checking
    local total_lines = vim.api.nvim_buf_line_count(buf)
    if fold_start_line > total_lines or fold_end_line > total_lines then
      logger.warn("FOLD", "Calculated fold range exceeds buffer bounds", {
        fold_start = fold_start_line,
        fold_end = fold_end_line,
        total_lines = total_lines
      })
      return
    end
    
    if fold_start_line <= fold_end_line then
      -- Process files to get categorized counts
      local processed = M.process_git_files(files, config.git_status_count)
      local untracked_count, unstaged_count = categorize_hidden_files(processed.hidden)
      local fold_text = build_overflow_text(untracked_count, unstaged_count)
      
      if fold_text then
        logger.debug("FOLD", "Setting up fold", {
          start_line = fold_start_line,
          end_line = fold_end_line,
          hidden_count = #processed.hidden,
          fold_text = fold_text
        })
        
        -- Set up folding options on the window (not buffer defaults)
        vim.api.nvim_buf_call(buf, function()
          vim.wo[0].foldmethod = 'manual'
          vim.wo[0].foldtext = 'v:lua.require("nexus.ui.folding").get_fold_text(' .. fold_start_line .. ', "' .. fold_text .. '")'
        end)
        
        -- Create the fold (vim uses 1-based line numbers)
        local cmd = string.format('%d,%dfold', fold_start_line, fold_end_line)
        vim.api.nvim_buf_call(buf, function()
          vim.cmd(cmd)
        end)
      end
    end
  end)
  
  if not success then
    logger.error("FOLD", "Failed to setup git status folding", {
      error = result,
      buf = buf,
      files_count = files and #files or 0,
      config_limit = config.git_status_count
    })
  end
end

-- Function to generate fold text with proper padding (with error handling)
function M.get_fold_text(fold_start_line, base_text)
  local success, result = pcall(function()
    -- Get the line above the fold to extract its padding
    local prev_line = vim.api.nvim_buf_get_lines(0, fold_start_line - 2, fold_start_line - 1, false)[1] or ""
    local padding = prev_line:match("^(%s*)") or ""
    return padding .. base_text
  end)

  if success then
    return result
  else
    -- Fallback to base text if padding extraction fails
    logger.warn("FOLD", "Failed to extract padding for fold text", {
      error = result,
      fold_start_line = fold_start_line
    })
    return base_text
  end
end

-- Sections that can be folded (skip project_name and keyboard_shortcuts)
M.foldable_sections = {
  'dashboard_buttons',
  'todos',
  'recent_commits',
  'git_status',
  'linear_issues',
  'huly_issues',
  'beads_issues',
  'claude_conversations'
}

-- Set window-local fold options reliably via vim.wo inside nvim_buf_call.
-- Using vim.wo[0] ensures these are set on the CURRENT WINDOW, not as
-- buffer-local defaults. The deprecated nvim_buf_set_option API is unreliable
-- for window-local options like foldmethod/foldenable/foldlevel.
-- Note: foldopen/foldclose are global options - we don't set them here to
-- avoid affecting other buffers.
local function set_fold_window_options(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.wo[0].foldmethod = 'manual'
    vim.wo[0].foldenable = true
    vim.wo[0].foldlevel = 99
    vim.wo[0].foldtext = 'v:lua.require("nexus.ui.folding").get_section_fold_text()'
  end)
end

-- Setup folds for all collapsible sections
function M.setup_section_folds(buf, section_ranges)
  -- Validate buffer
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    logger.error("FOLD", "Invalid buffer provided for section folding setup")
    return
  end

  if not section_ranges or vim.tbl_isempty(section_ranges) then
    logger.debug("FOLD", "No section ranges provided for folding")
    return
  end

  -- Set fold options on the window displaying this buffer (not buffer-local defaults)
  set_fold_window_options(buf)

  local foldable_sections = M.foldable_sections

  -- Build a sorted list of ALL section start lines to use as boundaries
  local all_section_starts = {}
  for _, range in pairs(section_ranges) do
    if range and range.start_line then
      table.insert(all_section_starts, range.start_line)
    end
  end
  table.sort(all_section_starts)

  local total_lines = vim.api.nvim_buf_line_count(buf)
  local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Create folds for each foldable section
  for _, section_name in ipairs(foldable_sections) do
    local range = section_ranges[section_name]

    if range and range.start_line and range.end_line then
      local fold_start = range.start_line + 2  -- Skip header and empty line

      -- Find the next section's start_line to use as upper boundary
      local max_fold_end = total_lines
      for _, start in ipairs(all_section_starts) do
        if start > range.start_line then
          -- Fold must end before the next section's header line
          max_fold_end = start - 1
          break
        end
      end

      local fold_end = math.min(range.end_line, max_fold_end)

      -- Trim trailing empty lines from fold range
      while fold_end >= fold_start do
        local line = buf_lines[fold_end]
        if line and line:match("^%s*$") then
          fold_end = fold_end - 1
        else
          break
        end
      end

      if fold_start <= fold_end then
        local success, err = pcall(function()
          vim.api.nvim_buf_call(buf, function()
            local cmd = string.format('%d,%dfold', fold_start, fold_end)
            vim.cmd(cmd)
          end)
        end)

        if not success then
          logger.warn("FOLD", "Failed to create fold for section", {
            section = section_name,
            start = fold_start,
            end_line = fold_end,
            error = err
          })
        else
          logger.debug("FOLD", "Created fold for section", {
            section = section_name,
            fold_start = fold_start,
            fold_end = fold_end,
            range_end = range.end_line,
            clamped_to = max_fold_end
          })
        end
      end
    end
  end
end

-- Apply saved fold states from persistent storage
function M.apply_fold_states(buf, section_ranges)
  local fold_state = require('nexus.state.folds')

  -- Validate buffer
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    logger.error("FOLD", "Invalid buffer for applying fold states")
    return
  end

  if not section_ranges or vim.tbl_isempty(section_ranges) then
    logger.debug("FOLD", "No section ranges for applying fold states")
    return
  end

  -- Build a lookup set of foldable section names for fast checking
  local foldable_set = {}
  for _, name in ipairs(M.foldable_sections) do
    foldable_set[name] = true
  end

  -- Save initial cursor position
  local initial_cursor = vim.api.nvim_win_get_cursor(0)

  -- Apply fold states only for foldable sections (skip keyboard_shortcuts, project_name, etc.)
  for section_name, range in pairs(section_ranges) do
    if foldable_set[section_name] and range and range.start_line and range.end_line then
      local is_open = fold_state.is_section_open(section_name)

      -- Calculate actual fold start (header + empty line are not part of fold)
      local fold_line = range.start_line + 2

      -- Apply fold state
      local success = pcall(function()
        vim.api.nvim_buf_call(buf, function()
          -- Move cursor to the fold start line
          vim.api.nvim_win_set_cursor(0, {fold_line, 0})

          -- Open or close the fold
          if is_open then
            vim.cmd('silent! normal! zo')  -- Open fold
          else
            vim.cmd('silent! normal! zc')  -- Close fold
          end
        end)
      end)

      if not success then
        logger.debug("FOLD", "Could not apply fold state (section may not be foldable)", {
          section = section_name,
          is_open = is_open
        })
      end
    end
  end

  -- Restore initial cursor position
  pcall(function()
    vim.api.nvim_win_set_cursor(0, initial_cursor)
  end)
end

-- Get section name from line number
function M.get_section_at_line(line_num, section_ranges)
  if not section_ranges then
    return nil
  end

  for section_name, range in pairs(section_ranges) do
    if range and range.start_line and range.end_line then
      if line_num >= range.start_line and line_num <= range.end_line then
        return section_name
      end
    end
  end

  return nil
end

-- Toggle fold for section at cursor
function M.toggle_fold_at_cursor(buf)
  local ui_state = require('nexus.state.ui')
  local fold_state_module = require('nexus.state.folds')

  -- Get cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]

  -- Get section ranges
  local section_ranges = ui_state.get_section_ranges()

  -- Find which section the cursor is in
  local section_name = M.get_section_at_line(line_num, section_ranges)

  if not section_name then
    return false
  end

  local range = section_ranges[section_name]
  if not range or not range.start_line then
    return false
  end

  -- Calculate actual fold start (header + empty line are not part of fold)
  local fold_line = range.start_line + 2

  -- Use explicit zo/zc instead of za to toggle.
  -- za has a side-effect of changing foldlevel which closes ALL folds,
  -- not just the targeted one.
  local ok = pcall(vim.api.nvim_buf_call, buf, function()
    local is_closed = vim.fn.foldclosed(fold_line) ~= -1
    vim.api.nvim_win_set_cursor(0, {fold_line, 0})
    if is_closed then
      vim.cmd('normal! zo')
    else
      vim.cmd('normal! zc')
    end
    vim.api.nvim_win_set_cursor(0, cursor)
  end)

  if not ok then
    return false
  end

  -- Update arrow and save state
  M.update_section_arrows(buf, section_ranges)
  local foldclosed = vim.fn.foldclosed(fold_line)
  local is_open = foldclosed == -1
  fold_state_module.set_section_state(section_name, is_open)

  return true
end

-- Custom fold text function for sections
function M.get_section_fold_text()
  -- Get fold level info
  local fold_lines = vim.v.foldend - vim.v.foldstart

  -- Show just the line count
  return string.format("    (%d lines hidden)", fold_lines)
end

-- Update section header arrows based on fold state
function M.update_section_arrows(buf, section_ranges)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  if not section_ranges or vim.tbl_isempty(section_ranges) then
    return
  end

  vim.api.nvim_buf_call(buf, function()
    for section_name, range in pairs(section_ranges) do
      if range and range.start_line then
        local header_line = range.start_line
        local fold_line = header_line + 2  -- Where the fold actually starts

        -- Check if fold exists and its state
        local foldclosed = vim.fn.foldclosed(fold_line)
        local is_folded = foldclosed ~= -1

        -- Get current header text
        local current_line = vim.api.nvim_buf_get_lines(buf, header_line - 1, header_line, false)[1]
        if current_line then
          local new_line

          -- Check if line already has an arrow (use find with plain=true for UTF-8 safety)
          if current_line:find("▼", 1, true) or current_line:find("▶", 1, true) then
            -- Replace existing arrow
            if is_folded then
              new_line = current_line:gsub("▼", "▶", 1)
            else
              new_line = current_line:gsub("▶", "▼", 1)
            end
          else
            -- Add arrow, replacing 2 spaces of padding to maintain alignment
            local padding, content = current_line:match("^(%s+)(.+)$")
            if padding and #padding >= 2 then
              -- Take 2 spaces from padding for the arrow
              local arrow = is_folded and "▶ " or "▼ "
              new_line = padding:sub(1, -3) .. arrow .. content
            else
              -- No padding, just add arrow at start
              local arrow = is_folded and "▶ " or "▼ "
              new_line = arrow .. current_line:gsub("^%s*", "")
            end
          end

          -- Update the line (make buffer modifiable temporarily)
          if new_line and new_line ~= current_line then
            local was_modifiable = vim.api.nvim_buf_get_option(buf, 'modifiable')
            vim.api.nvim_buf_set_option(buf, 'modifiable', true)
            vim.api.nvim_buf_set_lines(buf, header_line - 1, header_line, false, {new_line})
            vim.api.nvim_buf_set_option(buf, 'modifiable', was_modifiable)
          end
        end
      end
    end
  end)
end

return M