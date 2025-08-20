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
        
        -- Set up buffer folding options
        vim.api.nvim_buf_set_option(buf, 'foldmethod', 'manual')
        vim.api.nvim_buf_set_option(buf, 'foldtext', 'v:lua.require("nexus.ui.folding").get_fold_text(' .. fold_start_line .. ', "' .. fold_text .. '")')
        
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

return M