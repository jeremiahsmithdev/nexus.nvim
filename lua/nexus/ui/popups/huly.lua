--- DORMANT MODULE: Huly integration is currently disabled.
--- Provider implementation is broken (assumes GraphQL; Huly uses WebSocket via Node client).
--- Awaiting Node bridge implementation. See HULY_INTEGRATION_STATUS.md.
---@module nexus.ui.popups.huly
local M = {}

local huly_component = require('nexus.render.components.huly')
local huly_state = require('nexus.state.huly')
local logger = require('nexus.logger')

--- Show Huly issue details in a popup window
---@param issue table Huly issue data
---@param config table Nexus configuration
function M.show_issue_details(issue, config)
  if not issue then
    logger.warn('HULY', 'Cannot show issue details - no issue provided')
    return
  end

  logger.info('HULY', 'Creating issue details popup', {
    identifier = issue.identifier,
    id = issue.id,
    has_description = issue.description ~= nil and issue.description ~= "",
    description_type = type(issue.description),
    description_length = issue.description and #issue.description or 0,
    description_preview = issue.description and tostring(issue.description):sub(1, 100) or "nil/empty"
  })

  -- Calculate popup dimensions
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(20, vim.o.lines - 4)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  -- Create popup buffer
  local buf = vim.api.nvim_create_buf(false, true)
  local popup_win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. (issue.identifier or issue.id) .. ' - Huly Issue ',
    title_pos = 'center'
  })

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)

  -- Build content lines
  local lines = M._build_issue_content(issue, config, width)

  -- Set content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Apply syntax highlighting
  M._apply_issue_highlighting(buf, issue)

  -- Set buffer to non-modifiable after content is set
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  -- Setup keymaps for the popup
  M._setup_popup_keymaps(buf, popup_win, issue, config)

  -- Set local options for better display
  vim.api.nvim_win_set_option(popup_win, 'wrap', true)
  vim.api.nvim_win_set_option(popup_win, 'linebreak', true)
  vim.api.nvim_win_set_option(popup_win, 'breakindent', true)

  logger.debug('HULY', 'Issue details popup created', {
    win_id = popup_win,
    buf_id = buf,
    dimensions = { width = width, height = height }
  })
end

--- Build issue content for popup
---@param issue table Huly issue data
---@param config table Nexus configuration
---@param width number Popup width
---@return table content_lines
function M._build_issue_content(issue, config, width)
  local lines = {}
  local separator = string.rep('─', width - 4)

  -- Title
  table.insert(lines, "📋 " .. (issue.title or "No title"))
  table.insert(lines, "")

  -- Basic info
  table.insert(lines, "Identifier: " .. (issue.identifier or "N/A"))
  table.insert(lines, "Status: " .. (issue.status or "Unknown"))
  table.insert(lines, "Priority: " .. (issue.priority or "None"))
  table.insert(lines, "")

  -- Assignee (check type to avoid userdata/null issues)
  if issue.assignee and type(issue.assignee) == "table" and issue.assignee.name then
    table.insert(lines, "Assignee: " .. issue.assignee.name)
    if issue.assignee.email then
      table.insert(lines, "Email: " .. issue.assignee.email)
    end
    table.insert(lines, "")
  end

  -- Project info (check type to avoid userdata/null issues)
  if issue.project and type(issue.project) == "table" and issue.project.name then
    table.insert(lines, "Project: " .. issue.project.name)
    if issue.project.identifier then
      table.insert(lines, "Project ID: " .. issue.project.identifier)
    end
    table.insert(lines, "")
  end

  -- Workspace info (check type to avoid userdata/null issues)
  if issue.workspace and type(issue.workspace) == "table" and issue.workspace.name then
    table.insert(lines, "Workspace: " .. issue.workspace.name)
    table.insert(lines, "")
  end

  -- Description
  if issue.description and issue.description ~= "" then
    table.insert(lines, separator)
    table.insert(lines, "Description:")
    table.insert(lines, "")
    local desc = issue.description
    if type(desc) == "string" then
      local wrapped_lines = M._wrap_text(desc, width - 4)
      for _, line in ipairs(wrapped_lines) do
        table.insert(lines, line)
      end
    else
      table.insert(lines, tostring(desc))
    end
    table.insert(lines, "")
  end

  -- Timestamps
  table.insert(lines, separator)
  if issue.createdOn then
    local created_date = vim.fn.strftime('%Y-%m-%d %H:%M', math.floor(issue.createdOn / 1000))
    table.insert(lines, "Created: " .. created_date)
  end
  if issue.updatedOn then
    local updated_date = vim.fn.strftime('%Y-%m-%d %H:%M', math.floor(issue.updatedOn / 1000))
    table.insert(lines, "Updated: " .. updated_date)
  end

  -- Actions hint
  table.insert(lines, "")
  table.insert(lines, separator)
  table.insert(lines, "Actions:")
  table.insert(lines, "  Ctrl-O: Open in browser")
  table.insert(lines, "  e: Edit issue")
  table.insert(lines, "  s: Change status")
  table.insert(lines, "  q/Esc: Close")

  return lines
end

--- Apply syntax highlighting to issue popup
---@param buf number Buffer number
---@param issue table Issue data
function M._apply_issue_highlighting(buf, issue)
  local namespace = vim.api.nvim_create_namespace("huly_issue_popup")

  -- Get all lines
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Apply highlights to each line
  for i, line in ipairs(lines) do
    local line_num = i - 1  -- Convert to 0-based

    if line:match("^📋") then
      vim.api.nvim_buf_set_extmark(buf, namespace, line_num, 0, { end_col = #line, hl_group = "Title" })
    elseif line:match("^Identifier:") then
      local id_start = line:find(": ") + 2
      if id_start then
        vim.api.nvim_buf_set_extmark(buf, namespace, line_num, id_start - 1, { end_col = #line, hl_group = "Number" })
      end
    elseif line:match("^Status:") then
      local status_start = line:find(": ") + 2
      if status_start then
        vim.api.nvim_buf_set_extmark(buf, namespace, line_num, status_start - 1, { end_col = #line, hl_group = huly_component.get_status_color(issue.status) })
      end
    elseif line:match("^Priority:") then
      local priority_start = line:find(": ") + 2
      if priority_start then
        vim.api.nvim_buf_set_extmark(buf, namespace, line_num, priority_start - 1, { end_col = #line, hl_group = huly_component.get_priority_color(issue.priority) })
      end
    elseif line:match("^Assignee:") then
      local assignee_start = line:find(": ") + 2
      if assignee_start then
        vim.api.nvim_buf_set_extmark(buf, namespace, line_num, assignee_start - 1, { end_col = #line, hl_group = "Function" })
      end
    elseif line:match("^Project:") or line:match("^Workspace:") then
      local name_start = line:find(": ") + 2
      if name_start then
        vim.api.nvim_buf_set_extmark(buf, namespace, line_num, name_start - 1, { end_col = #line, hl_group = "Type" })
      end
    elseif line:match("^Created:") or line:match("^Updated:") then
      vim.api.nvim_buf_set_extmark(buf, namespace, line_num, 0, { end_col = #line, hl_group = "Comment" })
    elseif line:match("^Actions:") then
      vim.api.nvim_buf_set_extmark(buf, namespace, line_num, 0, { end_col = #line, hl_group = "Special" })
    elseif line:match("^  [A-Za-z]") then
      vim.api.nvim_buf_set_extmark(buf, namespace, line_num, 2, { end_col = 3, hl_group = "Keyword" })
    end
  end
end

--- Setup keymaps for popup window
---@param buf number Buffer number
---@param win number Window number
---@param issue table Issue data
---@param config table Nexus configuration
function M._setup_popup_keymaps(buf, win, issue, config)
  -- Local function to get the current render callback
  local function get_render_callback()
    -- This should be passed in or retrieved from the main nexus module
    -- For now, we'll create a simple refresh function
    return function()
      -- This would typically refresh the main nexus buffer
    end
  end

  -- Close popup
  local function close_popup()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, false)
    end
  end

  -- Keymaps
  vim.keymap.set('n', 'q', close_popup, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set('n', '<Esc>', close_popup, { buffer = buf, nowait = true, silent = true })

  -- Open in browser
  vim.keymap.set('n', '<C-o>', function()
    -- Get issue data to construct URL
    local issues = huly_state.get_issues()
    local target_issue = nil

    for _, issue_data in ipairs(issues) do
      if issue_data.identifier == issue.identifier then
        target_issue = issue_data
        break
      end
    end

    if target_issue and target_issue.workspace and target_issue.identifier then
      local url = string.format("https://huly.app/workspace/%s/tracker/issue/%s",
        target_issue.workspace.name or "default", target_issue.identifier)
      vim.ui.open(url)
      logger.info('HULY', 'Opened issue in browser', { url = url })
    else
      logger.error('HULY', 'Could not construct URL for issue', { identifier = issue.identifier })
    end
  end, { buffer = buf, nowait = true, silent = true })

  -- Edit issue (placeholder - would need editing functionality)
  vim.keymap.set('n', 'e', function()
    vim.notify("Issue editing not yet implemented", vim.log.levels.INFO)
  end, { buffer = buf, nowait = true, silent = true })

  -- Change status
  vim.keymap.set('n', 's', function()
    close_popup()

    -- Show status selection dialog
    local status_options = {"todo", "in progress", "done"}
    vim.ui.select(status_options, {
      prompt = string.format('Change status for issue %s:', issue.identifier)
    }, function(choice)
      if not choice then return end

      -- Update the issue
      huly_state.update_issue(issue.id, { status = choice }, function(updated_issue, error)
        if error then
          logger.error('HULY', 'Failed to update issue status', { error = error })
          vim.notify("Failed to update issue status", vim.log.levels.ERROR)
        else
          logger.info('HULY', 'Issue status updated successfully', {
            id = issue.id,
            new_status = choice
          })
          vim.notify(string.format("Issue %s status changed to %s", issue.identifier, choice))
        end
      end)
    end)
  end, { buffer = buf, nowait = true, silent = true })

  -- Window resize handling
  vim.api.nvim_create_autocmd('VimResized', {
    buffer = buf,
    callback = function()
      close_popup()
      M.show_issue_details(issue, config)
    end
  })

  -- Clean up on buffer close
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, false)
      end
    end
  })
end

--- Simple text wrapping helper
---@param text string Text to wrap
---@param width number Maximum line width
---@return table wrapped_lines
function M._wrap_text(text, width)
  local lines = {}
  local current_line = ""
  local words = vim.split(text, "%s+")

  for _, word in ipairs(words) do
    if #current_line + #word + 1 <= width then
      if #current_line > 0 then
        current_line = current_line .. " " .. word
      else
        current_line = word
      end
    else
      if #current_line > 0 then
        table.insert(lines, current_line)
      end
      current_line = word
    end
  end

  if #current_line > 0 then
    table.insert(lines, current_line)
  end

  return lines
end

--- Show a simple notification popup
---@param message string Message to display
---@param level string Log level (info, warn, error)
function M.show_notification(message, level)
  level = level or "info"

  local log_levels = {
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR
  }

  vim.notify(message, log_levels[level] or vim.log.levels.INFO)
end

return M