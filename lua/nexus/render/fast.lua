local M = {}

local logger = require('nexus.logger')
local layout = require('nexus.render.layout')
local sections_component = require('nexus.render.components.sections')
local highlighting = require('nexus.render.components.highlighting')

-- Cache for section building to avoid redundant computation
local section_cache = {}
local last_cache_key = nil

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

  -- Create cache key for section building optimization
  local cache_key = string.format("%s_%d_%d_%d",
    is_git_repo and "git" or "nogit",
    #files,
    #commits,
    width
  )

  -- Build sections using component with caching
  local sections
  if section_cache[cache_key] and last_cache_key == cache_key then
    sections = section_cache[cache_key]
    logger.debug('RENDER_FAST', 'Using cached sections')
  else
    sections = sections_component.build_sections(config, is_git_repo, files, commits)
    -- Cache only last result to prevent memory growth
    section_cache = {}
    section_cache[cache_key] = sections
    last_cache_key = cache_key
  end

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

  -- Set up folding for git status overflow (only if needed)
  if files and #files > 0 then
    sections_component.setup_folding(buf, lines, config, files)
  end

  -- Update state with section ranges and logo info
  ui_state.update_section_ranges(section_ranges)
  ui_state.update_logo_section(logo_section)

  -- Batch highlight operations for better performance
  M.apply_highlights_batch(buf, lines, config, is_git_repo, files, logo_section, section_ranges)

  -- Set up dynamic shortcut updating on cursor movement (only if shortcuts are enabled)
  local config_module = require('nexus.config')
  if config_module.is_section_enabled("keyboard_shortcuts") then
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

-- Cache for highlight operations to avoid redundant computation
local highlight_cache = {}
local last_highlight_key = nil

-- Batched highlight operations using extmarks for better performance
function M.apply_highlights_batch(buf, lines, config, is_git_repo, files, logo_section, section_ranges)
  local ns_id = vim.api.nvim_create_namespace('nexus_highlights')

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  -- Create cache key for highlight optimization
  local highlight_key = string.format("%s_%d_%d",
    is_git_repo and "git" or "nogit",
    #files,
    #lines
  )

  -- Use cached highlight operations if available
  local highlight_ops
  if highlight_cache[highlight_key] and last_highlight_key == highlight_key then
    highlight_ops = highlight_cache[highlight_key]
    logger.debug('RENDER_FAST', 'Using cached highlights')
  else
    -- Collect all highlight operations into batch
    highlight_ops = {}

    -- Logo highlights (only if logo section exists)
    if logo_section and logo_section.start_line and logo_section.end_line then
      for i = logo_section.start_line, logo_section.end_line do
        table.insert(highlight_ops, {
          line = i - 1, -- 0-indexed for API
          col_start = 0,
          col_end = -1,
          hl_group = config.logo_color or 'Type'
        })
      end
    end

    -- Git file highlights (only if files exist and git status section exists)
    if files and #files > 0 and section_ranges and section_ranges.git_status then
      local git_range = section_ranges.git_status
      local line_offset = git_range.start_line - 1

      -- Pre-allocate highlight ops for files to avoid table reallocation
      local file_count = math.min(#files, git_range.end_line - git_range.start_line + 1)
      for i = 1, file_count do
        local file = files[i]
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

    -- Cache only last result to prevent memory growth
    highlight_cache = {}
    highlight_cache[highlight_key] = highlight_ops
    last_highlight_key = highlight_key
  end

  -- Apply all highlights in batch using extmarks (optimized single pass)
  if #highlight_ops > 0 then
    -- Get buffer lines once for efficiency
    local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    -- Pre-calculate extmark data for batch application
    local extmark_data = {}
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
          table.insert(extmark_data, {
            line = op.line,
            col_start = op.col_start,
            end_col = end_col,
            hl_group = op.hl_group
          })
        end
      end
    end

    -- Apply all extmarks in single batch
    for _, data in ipairs(extmark_data) do
      vim.api.nvim_buf_set_extmark(buf, ns_id, data.line, data.col_start, {
        end_col = data.end_col,
        hl_group = data.hl_group,
        strict = false
      })
    end

    logger.debug('RENDER_FAST', string.format('Applied %d highlights in batch', #extmark_data))
  end
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