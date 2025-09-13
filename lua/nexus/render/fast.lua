local M = {}

local logger = require('nexus.logger')
local layout = require('nexus.render.layout')
local sections_component = require('nexus.render.components.sections')
local highlighting = require('nexus.render.components.highlighting')

-- Fast incremental rendering with batched operations
function M.render_git_status_fast(buf, config, cached_files)
  local start_time = vim.uv.hrtime()
  
  -- Update configuration in state
  local ui_state = require('nexus.state.ui')
  ui_state.update_config(config or {})
  
  -- Use batched git operations
  local git_state = require('nexus.state.git')
  local files, commits = git_state.update_git_data_batch(config, not cached_files)
  local is_git_repo = git_state.is_git_repo()
  
  -- Use cached files if provided
  if cached_files then
    files = cached_files
  end
  
  -- Get display width once
  local width = layout.get_display_width()
  
  -- Build sections using component (minimal allocation)
  local sections = sections_component.build_sections(config, is_git_repo, files, commits)
  
  -- Pre-calculate total line count for buffer pre-allocation
  local total_lines = M.calculate_total_lines(sections, config, width)
  
  -- Layout sections with pre-allocated arrays
  local lines, section_ranges, logo_section = layout.layout_sections(sections, config, width)
  
  -- Single buffer operation for all content
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Render image logo if enabled (after buffer content is set)
  if config.logo_selection == "image" then
    local logo = require('nexus.ui.logo')
    logo.render_image_logo(buf, config, 0, 0)
  end
  
  -- Set up folding for git status overflow
  sections_component.setup_folding(buf, lines, config, files)
  
  -- Update state with section ranges and logo info
  ui_state.update_section_ranges(section_ranges)
  ui_state.update_logo_section(logo_section)
  
  -- Batch highlight operations for better performance
  M.apply_highlights_batch(buf, lines, config, is_git_repo, files, logo_section, section_ranges)
  
  -- Set up dynamic shortcut updating on cursor movement (only if shortcuts are enabled)
  if config.show_keyboard_shortcuts then
    local events = require('nexus.render.components.events')
    events.setup_dynamic_shortcuts(buf, config, is_git_repo, section_ranges)
  end
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  local end_time = vim.uv.hrtime()
  local render_time = (end_time - start_time) / 1000000
  logger.debug('RENDER_FAST', string.format('Fast render completed in %.2fms', render_time))
  
  return files, section_ranges
end

-- Pre-calculate total lines needed to avoid buffer reallocations
function M.calculate_total_lines(sections, config, width)
  local total = 0
  
  -- Logo lines
  local logo = require('nexus.ui.logo')
  local logo_lines = logo.get_neovim_logo(config)
  total = total + #logo_lines
  
  -- Add estimated lines for sections
  for _, section_name in ipairs(config.section_order) do
    local section_data = sections[section_name]
    if section_data and #section_data > 0 then
      total = total + #section_data + 2 -- section + spacing
    end
  end
  
  return total
end

-- Batched highlight operations using extmarks for better performance
function M.apply_highlights_batch(buf, lines, config, is_git_repo, files, logo_section, section_ranges)
  local ns_id = vim.api.nvim_create_namespace('nexus_highlights')
  
  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  
  -- Collect all highlight operations into batch
  local highlight_ops = {}
  
  -- Logo highlights
  if logo_section then
    for i = logo_section.start_line, logo_section.end_line do
      table.insert(highlight_ops, {
        line = i - 1, -- 0-indexed for API
        col_start = 0,
        col_end = -1,
        hl_group = config.logo_color or 'Type'
      })
    end
  end
  
  -- Git file highlights
  if section_ranges and section_ranges.git_status then
    local git_range = section_ranges.git_status
    local line_offset = git_range.start_line - 1
    
    for i, file in ipairs(files) do
      local line_num = line_offset + i
      if line_num <= git_range.end_line then
        local status_color = M.get_status_color(file.status)
        table.insert(highlight_ops, {
          line = line_num - 1,
          col_start = 0,
          col_end = 2, -- Status column
          hl_group = status_color
        })
      end
    end
  end
  
  -- Apply all highlights in batch using extmarks
  local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, op in ipairs(highlight_ops) do
    if op.line + 1 <= #current_lines and current_lines[op.line + 1] then
      local line_len = #current_lines[op.line + 1]
      local end_col = op.col_end
      
      -- Handle -1 end_col (full line) safely
      if end_col == -1 then
        end_col = line_len
      elseif end_col > line_len then
        end_col = line_len
      end
      
      -- Only highlight if there's content and valid range
      if line_len > 0 and op.col_start <= line_len and end_col > op.col_start then
        vim.api.nvim_buf_set_extmark(buf, ns_id, op.line, op.col_start, {
          end_col = end_col,
          hl_group = op.hl_group,
          strict = false
        })
      end
    end
  end
  
  logger.debug('RENDER_FAST', string.format('Applied %d highlights in batch', #highlight_ops))
end

-- Fast status color lookup
function M.get_status_color(status)
  local first = status:sub(1, 1)
  if first == '?' then
    return 'DiagnosticError'  -- red for untracked
  elseif first ~= ' ' then
    return 'DiagnosticOk'     -- green for staged
  else
    return 'DiagnosticError'  -- red for unstaged
  end
end

-- Progressive rendering for very large repositories
function M.render_progressive(buf, config, files, chunk_size)
  chunk_size = chunk_size or 50
  
  local total_files = #files
  local chunks = math.ceil(total_files / chunk_size)
  
  logger.debug('RENDER_FAST', string.format('Progressive render: %d files in %d chunks', total_files, chunks))
  
  -- Render in chunks with yielding between chunks
  local function render_chunk(chunk_num)
    if chunk_num > chunks then
      logger.debug('RENDER_FAST', 'Progressive render completed')
      return
    end
    
    local start_idx = (chunk_num - 1) * chunk_size + 1
    local end_idx = math.min(chunk_num * chunk_size, total_files)
    local chunk_files = {}
    
    for i = start_idx, end_idx do
      table.insert(chunk_files, files[i])
    end
    
    -- Render this chunk
    M.render_git_status_fast(buf, config, chunk_files)
    
    -- Schedule next chunk
    vim.defer_fn(function()
      render_chunk(chunk_num + 1)
    end, 0)
  end
  
  -- Start progressive rendering
  render_chunk(1)
end

return M