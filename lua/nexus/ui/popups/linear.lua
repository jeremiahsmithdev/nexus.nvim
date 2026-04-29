--- Linear issue popup UI module
--- Handles rendering and interaction for Linear issue detail popups
--- Provides popups showing Linear issue details with syntax highlighting and edit capabilities
---@module nexus.ui.popups.linear

local M = {}

local logger = require('nexus.logger')
local actions = require('nexus.actions')
local linear_state = require('nexus.state.linear')

--- Show Linear issue details in popup window with editing capabilities
---@param issue table The Linear issue object
---@param config table Nexus configuration
function M.show_linear_issue_details(issue, config)
  logger.info('LINEAR', 'Showing Linear issue details', { 
    identifier = issue.identifier,
    title = issue.title
  })
  
  -- Format issue details
  local issue_details = {}
  
  -- Header with issue identifier and title
  local title = (issue.title and type(issue.title) == "string") and issue.title or "No title"
  table.insert(issue_details, string.format("%s - %s", issue.identifier, title))
  table.insert(issue_details, string.rep("=", #issue_details[1]))
  table.insert(issue_details, "")
  
  -- Basic info
  local description_start_line = nil
  local description_end_line = nil
  
  if issue.description and type(issue.description) == "string" and issue.description ~= "" then
    table.insert(issue_details, "Description:")
    description_start_line = #issue_details + 1 -- Next line after "Description:" header
    -- Split description by lines
    for line in issue.description:gmatch("[^\r\n]+") do
      table.insert(issue_details, "  " .. line)
    end
    description_end_line = #issue_details
    table.insert(issue_details, "")
  else
    table.insert(issue_details, "Description:")
    description_start_line = #issue_details + 1
    table.insert(issue_details, "  ") -- Add empty line for editing
    description_end_line = #issue_details
    table.insert(issue_details, "")
  end
  
  -- Status and Priority
  local status_line = "Status: " .. (issue.state and issue.state.name or "Unknown")
  if issue.priority and type(issue.priority) == "number" and issue.priority > 0 then
    local priority_names = { [1] = "Low", [2] = "Medium", [3] = "High", [4] = "Urgent" }
    local priority_name = priority_names[issue.priority] or "None"
    status_line = status_line .. " | Priority: " .. priority_name
  end
  table.insert(issue_details, status_line)
  
  -- Assignee
  if issue.assignee and type(issue.assignee) == "table" and issue.assignee.name then
    table.insert(issue_details, "Assignee: " .. issue.assignee.name)
  end
  
  -- Estimate
  if issue.estimate and type(issue.estimate) == "number" and issue.estimate > 0 then
    table.insert(issue_details, "Estimate: " .. issue.estimate .. " points")
  end
  
  -- Cycle
  if issue.cycle and type(issue.cycle) == "table" and issue.cycle.name then
    table.insert(issue_details, "Cycle: " .. issue.cycle.name)
  end
  
  -- Team
  if issue.team and type(issue.team) == "table" and issue.team.name then
    table.insert(issue_details, "Team: " .. issue.team.name)
  end
  
  -- Labels
  if issue.labels and type(issue.labels) == "table" and #issue.labels > 0 then
    local label_names = {}
    for _, label in ipairs(issue.labels) do
      if type(label) == "table" and label.name then
        table.insert(label_names, label.name)
      end
    end
    if #label_names > 0 then
      table.insert(issue_details, "Labels: " .. table.concat(label_names, ", "))
    end
  end
  
  -- Dates
  if issue.createdAt and type(issue.createdAt) == "string" then
    table.insert(issue_details, "Created: " .. issue.createdAt)
  end
  
  if issue.updatedAt and type(issue.updatedAt) == "string" then
    table.insert(issue_details, "Updated: " .. issue.updatedAt)
  end
  
  -- URL (for reference)
  if issue.url and type(issue.url) == "string" then
    table.insert(issue_details, "")
    table.insert(issue_details, "URL: " .. issue.url)
  end
  
  -- Create a new buffer for the popup
  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(popup_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(popup_buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', true)
  
  -- Set buffer content
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, issue_details)
  
  -- Apply syntax highlighting
  M.apply_linear_popup_highlighting(popup_buf, issue_details, issue)
  
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', false)
  
  -- Calculate popup size
  local max_width = 100
  local max_height = 30
  local actual_width = math.min(max_width, math.max(50, #issue_details > 0 and math.max(unpack(vim.tbl_map(function(line) return #line end, issue_details))) or 50))
  local actual_height = math.min(max_height, math.max(10, #issue_details))
  
  -- Calculate popup position (center of screen)
  local screen_width = vim.api.nvim_get_option('columns')
  local screen_height = vim.api.nvim_get_option('lines')
  local col = math.floor((screen_width - actual_width) / 2)
  local row = math.floor((screen_height - actual_height) / 2)
  
  -- Create popup window
  local popup_opts = {
    relative = 'editor',
    width = actual_width,
    height = actual_height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' Linear Issue: ' .. issue.identifier .. ' ',
    title_pos = 'center'
  }
  
  local popup_win = vim.api.nvim_open_win(popup_buf, true, popup_opts)

  -- Recenter (and clamp) the popup on terminal resize without rebuilding it.
  -- Preserves cursor, edit mode (e.g. mid-description-edit), and extmarks.
  vim.api.nvim_create_autocmd('VimResized', {
    buffer = popup_buf,
    callback = function()
      if not vim.api.nvim_win_is_valid(popup_win) then
        return
      end
      local new_width = math.min(actual_width, vim.o.columns - 4)
      local new_height = math.min(actual_height, vim.o.lines - 4)
      vim.api.nvim_win_set_config(popup_win, {
        relative = 'editor',
        width = new_width,
        height = new_height,
        col = math.floor((vim.o.columns - new_width) / 2),
        row = math.floor((vim.o.lines - new_height) / 2),
      })
    end
  })

  -- Set popup window options
  vim.api.nvim_win_set_option(popup_win, 'wrap', true)
  vim.api.nvim_win_set_option(popup_win, 'number', false)
  vim.api.nvim_win_set_option(popup_win, 'relativenumber', false)
  vim.api.nvim_win_set_option(popup_win, 'cursorline', true)
  
  -- Add virtual text hint in top right corner
  local hint_ns = vim.api.nvim_create_namespace('nexus_linear_hint')
  local hint_text = 'e -> edit desc | Ctrl-O -> open'
  local hint_col = actual_width - #hint_text
  vim.api.nvim_buf_set_extmark(popup_buf, hint_ns, 0, 0, {
    virt_text = {{ hint_text, 'Comment' }},
    virt_text_pos = 'overlay',
    virt_text_win_col = hint_col,
    hl_mode = 'combine'
  })
  
  -- Set up keymaps to close popup
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'q', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<Esc>', '<cmd>close<CR>', {noremap = true, silent = true})
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<CR>', '<cmd>close<CR>', {noremap = true, silent = true})
  
  -- Add keybinding to open issue in browser with Ctrl-O
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<C-o>', '', {
    noremap = true, 
    silent = true,
    callback = function()
      -- Close the popup first
      vim.cmd('close')
      -- Then open the issue in browser using action system
      actions.execute('linear.browse', { issue = issue })
    end
  })
  
  -- Add keybinding to edit description with 'e'
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'e', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.edit_linear_issue_description(popup_buf, issue, description_start_line, description_end_line, config)
    end
  })
  
  logger.info('LINEAR', 'Showing details for Linear issue: ' .. issue.identifier)
end

--- Edit Linear issue description in-place
---@param popup_buf number The popup buffer
---@param issue table The Linear issue object
---@param description_start_line number Starting line of description content
---@param description_end_line number Ending line of description content  
---@param config table Nexus configuration
function M.edit_linear_issue_description(popup_buf, issue, description_start_line, description_end_line, config)
  logger.info('LINEAR', 'Editing description for issue: ' .. issue.identifier)
  
  -- Make buffer modifiable for editing and set up for :w to work
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', true)
  vim.api.nvim_buf_set_option(popup_buf, 'buftype', 'acwrite') -- Allow custom write behavior
  
  -- Clear any existing buffer with this name first
  local buffer_name = 'linear-desc-' .. issue.identifier
  pcall(function()
    local existing_buf = vim.fn.bufnr('^' .. buffer_name .. '$')
    if existing_buf ~= -1 and existing_buf ~= popup_buf then
      vim.api.nvim_buf_delete(existing_buf, { force = true })
    end
  end)
  
  vim.api.nvim_buf_set_name(popup_buf, buffer_name)
  
  -- Find the Description: line and position cursor appropriately
  local all_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  local desc_line_num = nil
  
  for i, line in ipairs(all_lines) do
    if line:match("^Description:") then
      desc_line_num = i
      break
    end
  end
  
  if desc_line_num then
    -- Always position cursor on the line AFTER Description: (where content should go)
    if desc_line_num < #all_lines and all_lines[desc_line_num + 1] then
      -- Move to next line if it exists
      vim.api.nvim_win_set_cursor(0, {desc_line_num + 1, 2})
    else
      -- Fallback to original positioning
      vim.api.nvim_win_set_cursor(0, {description_start_line, 2})
    end
  else
    -- Fallback to original positioning
    vim.api.nvim_win_set_cursor(0, {description_start_line, 2})
  end
  
  -- Clear existing keymaps that would close the buffer
  pcall(vim.api.nvim_buf_del_keymap, popup_buf, 'n', 'q')
  pcall(vim.api.nvim_buf_del_keymap, popup_buf, 'n', '<Esc>')
  pcall(vim.api.nvim_buf_del_keymap, popup_buf, 'n', '<CR>')
  
  -- Add editing keymaps to the popup buffer
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<C-s>', '', {
    noremap = true,
    silent = true,
    callback = function()
      M.save_linear_issue_description(popup_buf, issue, description_start_line, description_end_line, config)
    end
  })
  
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<Esc>', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Clean up the edit buffer using our cleanup function
      M.cleanup_edit_buffer(popup_buf, buffer_name)
      
      -- Cancel editing - close popup
      vim.cmd('close')
      -- Schedule buffer deletion to avoid issues
      vim.schedule(function()
        pcall(vim.api.nvim_buf_delete, popup_buf, { force = true })
      end)
    end
  })
  
  -- Add :w command support by intercepting the write command
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = popup_buf,
    callback = function()
      M.save_linear_issue_description(popup_buf, issue, description_start_line, description_end_line, config)
    end,
    desc = 'Save Linear issue description with :w'
  })
  
  -- Add cleanup on window close to ensure no leftover files
  vim.api.nvim_create_autocmd({'WinClosed', 'BufUnload'}, {
    buffer = popup_buf,
    callback = function()
      M.cleanup_edit_buffer(popup_buf, buffer_name)
    end,
    desc = 'Clean up Linear edit buffer on close'
  })
  
  -- Extract current description content
  local desc_content = ""
  local found_desc = false
  
  for _, line in ipairs(all_lines) do
    if line:match("^Description:") then
      found_desc = true
      -- Check if there's content on same line
      local same_line_content = line:match("^Description:%s*(.+)")
      if same_line_content and same_line_content:gsub("%s", "") ~= "" then
        desc_content = desc_content .. same_line_content .. "\n"
      end
    elseif found_desc and line:match("^[%w%s]+:") then
      break -- Stop at next field
    elseif found_desc then
      -- Remove indentation and add to content - preserve empty lines
      local clean_line = line:gsub("^  ", "")
      desc_content = desc_content .. clean_line .. "\n"
    end
  end
  
  -- Remove trailing newline
  desc_content = desc_content:gsub("\n$", "")
  
  -- Set the description content (split by lines) 
  local desc_lines = desc_content ~= "" and vim.split(desc_content, '\n') or {""}
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, desc_lines)
  
  -- Change the window title to indicate editing mode
  vim.api.nvim_win_set_config(0, {
    title = " New Description: " .. issue.identifier .. " ",
    title_pos = "center"
  })
  
  -- Add save hint using a different approach - create an autocmd to maintain it
  vim.schedule(function()
    local hint_ns = vim.api.nvim_create_namespace('nexus_linear_edit_hint')
    
    local function add_hint()
      vim.api.nvim_buf_clear_namespace(popup_buf, hint_ns, 0, -1)
      
      -- Always add to line 0, even if it's empty
      local actual_width = vim.api.nvim_win_get_width(0)
      local hint_text = 'Ctrl-S -> save'
      local hint_col = actual_width - #hint_text - 2
      
      -- Use virt_text_pos = 'right_align' to keep it at the right edge
      vim.api.nvim_buf_set_extmark(popup_buf, hint_ns, 0, 0, {
        virt_text = {{hint_text, 'Comment'}},
        virt_text_pos = 'right_align',
        hl_mode = 'combine'
      })
    end
    
    -- Add initially
    add_hint()
    
    -- Re-add after any text changes
    vim.api.nvim_create_autocmd({'TextChanged', 'TextChangedI', 'BufEnter'}, {
      buffer = popup_buf,
      callback = add_hint,
      once = false
    })
    
    -- Position cursor at start of first line in normal mode
    vim.api.nvim_win_set_cursor(0, {1, 0})
  end)
  
  vim.notify("Edit description - Ctrl-S to save, Esc to cancel", vim.log.levels.INFO)
end

--- Clean up edit buffer and any temporary files
---@param popup_buf number The popup buffer
---@param buffer_name string The buffer name to clean up
function M.cleanup_edit_buffer(popup_buf, buffer_name)
  -- Reset buffer to prevent file creation
  pcall(vim.api.nvim_buf_set_name, popup_buf, '')
  pcall(vim.api.nvim_buf_set_option, popup_buf, 'buftype', 'nofile')
  
  -- Clean up any existing temp files
  pcall(vim.fn.delete, '"no current target"')
  if buffer_name then
    pcall(vim.fn.delete, buffer_name)
  end
end

--- Save edited Linear issue description
---@param popup_buf number The popup buffer
---@param issue table The Linear issue object
---@param description_start_line number Starting line of description content (unused but kept for compatibility)
---@param description_end_line number Ending line of description content (unused but kept for compatibility)
---@param config table Nexus configuration
function M.save_linear_issue_description(popup_buf, issue, description_start_line, description_end_line, config)
  logger.info('LINEAR', 'Saving description for issue: ' .. issue.identifier)
  
  -- Get all lines from the edit buffer and preserve empty lines
  local all_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
  local description_text = table.concat(all_lines, '\n')
  -- Only trim whitespace from the very beginning and end, preserve internal empty lines
  description_text = description_text:gsub("^%s*", ""):gsub("%s*$", "")
  
  -- Get cached provider
  local provider = linear_state.get_cached_provider(config)
  
  if not provider then
    vim.notify("❌ Failed to get Linear provider", vim.log.levels.ERROR)
    return
  end
  
  vim.notify("Saving description...", vim.log.levels.INFO)
  
  -- Update the issue using the provider
  local updated_issue, error_msg = provider:update_issue(issue.id, {
    description = description_text
  })
  
  if updated_issue then
    logger.info('LINEAR', 'Description updated successfully', {
      identifier = updated_issue.identifier
    })
    
    vim.notify("✅ Description saved successfully!", vim.log.levels.INFO)
    
    -- Clean up the edit buffer using our cleanup function
    local buffer_name = 'linear-desc-' .. issue.identifier
    M.cleanup_edit_buffer(popup_buf, buffer_name)
    
    -- Refresh Linear data
    linear_state.refresh_data(config)
    
    -- Close the popup and clean up buffer
    vim.cmd('close')
    -- Schedule buffer deletion to avoid issues
    vim.schedule(function()
      pcall(vim.api.nvim_buf_delete, popup_buf, { force = true })
    end)
  else
    logger.error('LINEAR', 'Failed to update description', {
      identifier = issue.identifier,
      error = error_msg
    })
    
    vim.notify("❌ Failed to save description: " .. (error_msg or "Unknown error"), vim.log.levels.ERROR)
  end
end

--- Apply syntax highlighting to Linear issue details popup
---@param buf number The buffer number
---@param lines table Array of lines to highlight
---@param issue table The Linear issue object for context
function M.apply_linear_popup_highlighting(buf, lines, issue)
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)
  
  -- Create namespace for Linear popup highlighting
  local linear_ns = vim.api.nvim_create_namespace('nexus_linear_popup')
  
  for i, line in ipairs(lines) do
    if line and #line > 0 then
      -- 1. Highlight the header line (issue identifier and title)
      if i == 1 and line:match('[A-Z]+-[0-9]+') then
        -- Highlight the identifier
        local id_start, id_end = line:find('[A-Z]+-[0-9]+')
        if id_start then
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, id_start - 1, { end_col = id_end, hl_group = 'Number' })
        end

        -- Highlight the rest as title
        local dash_pos = line:find(' - ')
        if dash_pos then
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, dash_pos + 2, { end_col = #line, hl_group = 'Title' })
        end
      end

      -- 2. Highlight the separator line (===)
      if line:match('^=+$') then
        vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, 0, { end_col = #line, hl_group = 'Comment' })
      end
      
      -- 3. Highlight field names (Status:, Assignee:, etc.)
      local field_patterns = {
        'Description:', 'Status:', 'Priority:', 'Assignee:', 'Estimate:', 
        'Cycle:', 'Team:', 'Labels:', 'Created:', 'Updated:', 'URL:'
      }
      
      for _, pattern in ipairs(field_patterns) do
        local field_start, field_end = line:find(pattern)
        if field_start then
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, field_start - 1, { end_col = field_end, hl_group = 'Keyword' })
          break
        end
      end

      -- 4. Highlight priority levels with colors
      if line:match('Priority:') then
        if line:match('Urgent') then
          local urgent_start, urgent_end = line:find('Urgent')
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, urgent_start - 1, { end_col = urgent_end, hl_group = 'DiagnosticError' })
        elseif line:match('High') then
          local high_start, high_end = line:find('High')
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, high_start - 1, { end_col = high_end, hl_group = 'DiagnosticWarn' })
        elseif line:match('Medium') then
          local medium_start, medium_end = line:find('Medium')
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, medium_start - 1, { end_col = medium_end, hl_group = 'DiagnosticInfo' })
        elseif line:match('Low') then
          local low_start, low_end = line:find('Low')
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, low_start - 1, { end_col = low_end, hl_group = 'DiagnosticHint' })
        end
      end

      -- 5. Highlight status with colors
      if line:match('Status:') then
        if line:match('Completed') then
          local completed_start, completed_end = line:find('Completed')
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, completed_start - 1, { end_col = completed_end, hl_group = 'DiagnosticOk' })
        elseif line:match('Started') then
          local started_start, started_end = line:find('Started')
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, started_start - 1, { end_col = started_end, hl_group = 'DiagnosticInfo' })
        elseif line:match('Canceled') then
          local canceled_start, canceled_end = line:find('Canceled')
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, canceled_start - 1, { end_col = canceled_end, hl_group = 'DiagnosticError' })
        end
      end

      -- 6. Highlight URLs
      if line:match('https?://[%w.-/]+') then
        local url_start, url_end = line:find('https?://[%w.-/]+')
        vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, url_start - 1, { end_col = url_end, hl_group = 'Underlined' })
      end

      -- 7. Highlight numbers (estimates, dates)
      if line:match('Estimate:') or line:match('points') then
        for num_start, num_end in line:gmatch('()(%d+)()') do
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, num_start - 1, { end_col = num_end - 1, hl_group = 'Number' })
        end
      end

      -- 8. Highlight names (assignee names, team names)
      if line:match('Assignee:') or line:match('Team:') or line:match('Cycle:') then
        local colon_pos = line:find(':')
        if colon_pos and colon_pos < #line then
          local value_start = line:find('[^%s:]', colon_pos + 1)
          if value_start then
            vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, value_start - 1, { end_col = #line, hl_group = 'String' })
          end
        end
      end
    end
  end
end

return M