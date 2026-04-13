--- Beads keymap handlers for Nexus
--- Context-aware key handling for Beads Issues section
---@module nexus.keymaps.beads

local M = {}

local logger = require('nexus.logger')

--- Handle Enter key - show issue details or navigate epic children
---@param current_line string Current line content
---@param line_num number Line number
---@param config table Nexus config
---@param buf number Buffer number
---@param render_callback function Callback to re-render buffer
function M.handle_enter(current_line, line_num, config, buf, render_callback)
  local beads_state = require('nexus.state.beads')

  -- Check for setup/error messages
  if current_line:match("No %.beads directory") then
    vim.notify("Run 'br init' in your project root to initialize beads", vim.log.levels.INFO)
    return
  end

  if current_line:match("CLI not installed") then
    vim.notify("Install beads from: github.com/anthropics/beads", vim.log.levels.INFO)
    return
  end

  -- Get issue ID from line number mapping (reliable, not parsing text!)
  local issue_id = beads_state.get_issue_id_for_line(line_num)
  if not issue_id then
    -- Not on an issue line
    logger.debug('BEADS_KEYMAPS', 'No issue mapping for line: ' .. line_num)
    return
  end

  -- Fetch full issue details
  local issue = beads_state.get_issue_by_id(issue_id)
  if not issue then
    vim.notify("Could not fetch issue: " .. issue_id, vim.log.levels.WARN)
    return
  end

  -- If it's an epic, show children navigation
  if issue.type == 'epic' then
    M.show_epic_children_popup(issue, config, buf, render_callback)
  else
    -- Show issue details popup
    M.show_issue_popup(issue, config, buf, render_callback)
  end
end

--- Handle 'c' key - create new issue
---@param buf number Buffer number
---@param render_callback function Callback to re-render buffer
---@param config table Nexus config
function M.handle_create(buf, render_callback, config)
  local beads_state = require('nexus.state.beads')

  -- Check prerequisites
  if not beads_state.is_beads_available() then
    vim.notify("No .beads directory found. Run 'br init' first.", vim.log.levels.WARN)
    return
  end

  if not beads_state.is_cli_installed() then
    vim.notify("Beads CLI not installed (looking for: " .. (require('nexus.config').get().beads.cli or 'br') .. ")", vim.log.levels.WARN)
    return
  end

  -- Prompt for title
  vim.ui.input({ prompt = 'Issue title: ' }, function(title)
    if not title or title == '' then return end

    -- Prompt for type
    vim.ui.select({ 'task', 'bug', 'feature', 'chore', 'epic' }, {
      prompt = 'Issue type:',
    }, function(issue_type)
      if not issue_type then return end

      -- Prompt for priority
      vim.ui.select({
        'P0 (Critical)',
        'P1 (High)',
        'P2 (Medium)',
        'P3 (Low)',
        'P4 (Backlog)'
      }, {
        prompt = 'Priority:',
      }, function(priority_choice)
        local priority = 2 -- Default to medium
        if priority_choice then
          priority = tonumber(priority_choice:match('P(%d)')) or 2
        end

        -- Create the issue
        local issue, err = beads_state.create_issue(title, {
          type = issue_type,
          priority = priority
        })

        if err then
          vim.notify("Failed to create issue: " .. err, vim.log.levels.ERROR)
          return
        end

        vim.notify(string.format("Created issue: %s", issue and issue.id or title), vim.log.levels.INFO)
        render_callback(buf)
      end)
    end)
  end)
end

--- Handle 's' key - update status
---@param current_line string Current line content
---@param line_num number Line number
---@param buf number Buffer number
---@param render_callback function Callback to re-render buffer
---@param config table Nexus config
function M.handle_status_update(current_line, line_num, buf, render_callback, config)
  local beads_state = require('nexus.state.beads')

  -- Get issue ID from line mapping
  local issue_id = beads_state.get_issue_id_for_line(line_num)
  if not issue_id then
    vim.notify("No issue found on current line", vim.log.levels.WARN)
    return
  end

  local issue = beads_state.get_issue_by_id(issue_id)
  local current_status = issue and issue.status or 'unknown'

  local status_options = {
    'open',
    'in_progress',
    'blocked',
    'deferred'
  }

  vim.ui.select(status_options, {
    prompt = string.format('Update status for %s (current: %s):', issue_id, current_status),
  }, function(new_status)
    if not new_status then return end

    local _, err = beads_state.update_issue(issue_id, { status = new_status })
    if err then
      vim.notify("Failed to update status: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.notify(string.format("%s -> %s", issue_id, new_status), vim.log.levels.INFO)
    render_callback(buf)
  end)
end

--- Handle 'd' key - close issue (mark done)
---@param current_line string Current line content
---@param line_num number Line number
---@param buf number Buffer number
---@param render_callback function Callback to re-render buffer
---@param config table Nexus config
function M.handle_done(current_line, line_num, buf, render_callback, config)
  local beads_state = require('nexus.state.beads')

  -- Get issue ID from line mapping
  local issue_id = beads_state.get_issue_id_for_line(line_num)
  if not issue_id then
    vim.notify("No issue found on current line", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = 'Close reason (optional): ' }, function(reason)
    local success, err = beads_state.close_issue(issue_id, reason or 'Completed')
    if not success then
      vim.notify("Failed to close issue: " .. (err or 'unknown error'), vim.log.levels.ERROR)
      return
    end

    vim.notify(string.format("Closed %s", issue_id), vim.log.levels.INFO)
    render_callback(buf)
  end)
end

--- Handle 'e' key - edit issue
---@param current_line string Current line content
---@param line_num number Line number
---@param buf number Buffer number
---@param render_callback function Callback to re-render buffer
---@param config table Nexus config
function M.handle_edit(current_line, line_num, buf, render_callback, config)
  local beads_state = require('nexus.state.beads')

  -- Get issue ID from line mapping
  local issue_id = beads_state.get_issue_id_for_line(line_num)
  if not issue_id then
    vim.notify("No issue found on current line", vim.log.levels.WARN)
    return
  end

  local issue = beads_state.get_issue_by_id(issue_id)
  if not issue then
    vim.notify("Could not fetch issue: " .. issue_id, vim.log.levels.WARN)
    return
  end

  vim.ui.select({
    'Change priority',
    'Add note',
  }, {
    prompt = string.format('Edit %s:', issue_id),
  }, function(choice)
    if not choice then return end

    if choice == 'Change priority' then
      M.handle_priority_change(issue_id, buf, render_callback, config)
    elseif choice == 'Add note' then
      M.handle_add_note(issue_id, buf, render_callback, config)
    end
  end)
end

--- Handle priority change
---@param issue_id string Issue ID
---@param buf number Buffer number
---@param render_callback function Callback to re-render buffer
---@param config table Nexus config
function M.handle_priority_change(issue_id, buf, render_callback, config)
  local beads_state = require('nexus.state.beads')

  vim.ui.select({
    'P0 (Critical)',
    'P1 (High)',
    'P2 (Medium)',
    'P3 (Low)',
    'P4 (Backlog)'
  }, {
    prompt = 'New priority:',
  }, function(choice)
    if not choice then return end

    local priority = tonumber(choice:match('P(%d)')) or 2
    local _, err = beads_state.update_issue(issue_id, { priority = priority })
    if err then
      vim.notify("Failed to update priority: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.notify(string.format("%s priority -> %s", issue_id, choice), vim.log.levels.INFO)
    render_callback(buf)
  end)
end

--- Handle adding a note to an issue
---@param issue_id string Issue ID
---@param buf number Buffer number
---@param render_callback function Callback to re-render buffer
---@param config table Nexus config
function M.handle_add_note(issue_id, buf, render_callback, config)
  local beads_state = require('nexus.state.beads')

  vim.ui.input({ prompt = 'Note: ' }, function(note)
    if not note or note == '' then return end

    local _, err = beads_state.update_issue(issue_id, { notes = note })
    if err then
      vim.notify("Failed to add note: " .. err, vim.log.levels.ERROR)
      return
    end

    vim.notify(string.format("Added note to %s", issue_id), vim.log.levels.INFO)
    render_callback(buf)
  end)
end

--- Show issue details in a popup
---@param issue table Issue data
---@param config table Nexus config
---@param buf number Parent buffer number
---@param render_callback function Callback to re-render buffer
function M.show_issue_popup(issue, config, buf, render_callback)
  -- Build popup content
  local lines = {}
  local width = 60

  -- Header
  local title_line = string.format("%s - %s", issue.id or "???", issue.title or "Untitled")
  table.insert(lines, title_line)
  table.insert(lines, string.rep("─", math.min(#title_line, width)))
  table.insert(lines, "")

  -- Metadata
  local meta_parts = {}
  if issue.type then
    table.insert(meta_parts, "Type: " .. issue.type)
  end
  if issue.priority ~= nil then
    local priority_labels = { [0]="P0 (Critical)", [1]="P1 (High)", [2]="P2 (Medium)", [3]="P3 (Low)", [4]="P4 (Backlog)" }
    table.insert(meta_parts, "Priority: " .. (priority_labels[issue.priority] or "P" .. issue.priority))
  end
  if issue.status then
    table.insert(meta_parts, "Status: " .. issue.status)
  end
  if #meta_parts > 0 then
    table.insert(lines, table.concat(meta_parts, " | "))
    table.insert(lines, "")
  end

  -- Description
  if issue.description and issue.description ~= '' then
    table.insert(lines, "Description:")
    -- Wrap description text
    for _, desc_line in ipairs(vim.split(issue.description, '\n')) do
      if #desc_line > width - 2 then
        -- Simple word wrap
        local remaining = desc_line
        while #remaining > 0 do
          local chunk = remaining:sub(1, width - 2)
          local space_pos = chunk:reverse():find(' ')
          if space_pos and #remaining > width - 2 then
            chunk = remaining:sub(1, width - 2 - space_pos + 1)
          end
          table.insert(lines, "  " .. chunk)
          remaining = remaining:sub(#chunk + 1):gsub("^%s+", "")
        end
      else
        table.insert(lines, "  " .. desc_line)
      end
    end
    table.insert(lines, "")
  end

  -- Notes
  if issue.notes and issue.notes ~= '' then
    table.insert(lines, "Notes:")
    for _, note_line in ipairs(vim.split(issue.notes, '\n')) do
      table.insert(lines, "  " .. note_line)
    end
    table.insert(lines, "")
  end

  -- Dependencies
  if issue.blockedBy and #issue.blockedBy > 0 then
    table.insert(lines, "Blocked by:")
    for _, blocker in ipairs(issue.blockedBy) do
      local blocker_id = type(blocker) == 'string' and blocker or (blocker.id or '?')
      table.insert(lines, "  - " .. blocker_id)
    end
    table.insert(lines, "")
  end

  if issue.blocks and #issue.blocks > 0 then
    table.insert(lines, "Blocks:")
    for _, blocked in ipairs(issue.blocks) do
      local blocked_id = type(blocked) == 'string' and blocked or (blocked.id or '?')
      table.insert(lines, "  - " .. blocked_id)
    end
    table.insert(lines, "")
  end

  -- Actions
  table.insert(lines, "Actions:")
  table.insert(lines, "  s - Update status")
  table.insert(lines, "  p - Change priority")
  table.insert(lines, "  d - Close issue")
  table.insert(lines, "  q/Esc - Close popup")

  -- Calculate dimensions
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, #line)
  end
  width = math.min(max_width + 4, 80)
  local height = math.min(#lines + 2, 30)

  -- Create popup buffer
  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(popup_buf, 'buftype', 'nofile')

  -- Calculate position (centered)
  local win_width = vim.api.nvim_get_option('columns')
  local win_height = vim.api.nvim_get_option('lines')
  local row = math.floor((win_height - height) / 2)
  local col = math.floor((win_width - width) / 2)

  -- Create popup window
  local popup_win = vim.api.nvim_open_win(popup_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Beads Issue ',
    title_pos = 'center',
  })

  -- Apply highlighting
  local ns_id = vim.api.nvim_create_namespace('nexus_beads_popup')
  -- Highlight header
  vim.api.nvim_buf_set_extmark(popup_buf, ns_id, 0, 0, {
    end_col = #lines[1],
    hl_group = 'Title',
  })

  -- Set up keymaps for popup
  local opts = { noremap = true, silent = true, buffer = popup_buf }

  local function close_popup()
    if vim.api.nvim_win_is_valid(popup_win) then
      vim.api.nvim_win_close(popup_win, true)
    end
  end

  vim.keymap.set('n', 'q', close_popup, opts)
  vim.keymap.set('n', '<Esc>', close_popup, opts)

  vim.keymap.set('n', 's', function()
    close_popup()
    local line = "  [" .. issue.id .. "]"  -- Fake line for handler
    M.handle_status_update(line, buf, render_callback, config)
  end, opts)

  vim.keymap.set('n', 'p', function()
    close_popup()
    M.handle_priority_change(issue.id, buf, render_callback, config)
  end, opts)

  vim.keymap.set('n', 'd', function()
    close_popup()
    local line = "  [" .. issue.id .. "]"
    M.handle_done(line, buf, render_callback, config)
  end, opts)
end

--- Handle 'E' key - browse epics
---@param buf number Buffer number
---@param render_callback function Callback to re-render buffer
---@param config table Nexus config
function M.handle_browse_epics(buf, render_callback, config)
  local beads_state = require('nexus.state.beads')

  -- Check prerequisites
  if not beads_state.is_beads_available() then
    vim.notify("No .beads directory found. Run 'br init' first.", vim.log.levels.WARN)
    return
  end

  if not beads_state.is_cli_installed() then
    vim.notify("Beads CLI not installed", vim.log.levels.WARN)
    return
  end

  -- Get sorted epics (in_progress first, then with in_progress children, then others)
  local epics = beads_state.get_sorted_epics(true)

  if not epics or #epics == 0 then
    vim.notify("No epics found", vim.log.levels.INFO)
    return
  end

  -- Build selection options
  local options = {}
  for _, epic in ipairs(epics) do
    local status_icon = require('nexus.render.components.beads').get_status_icon(epic.status or 'open')
    local title = epic.title or "Untitled"
    if #title > 60 then
      title = title:sub(1, 57) .. "..."
    end
    table.insert(options, string.format("%s [%s] %s", status_icon, epic.id, title))
  end

  -- Show selection
  vim.ui.select(options, {
    prompt = 'Select epic:',
    format_item = function(item) return item end
  }, function(choice, idx)
    if not choice or not idx then return end

    local epic = epics[idx]
    M.show_epic_children_popup(epic, config, buf, render_callback)
  end)
end

--- Handle 'R' key - show ready issues
---@param buf number Buffer number
---@param render_callback function Callback to re-render buffer
---@param config table Nexus config
function M.handle_show_ready(buf, render_callback, config)
  local beads_state = require('nexus.state.beads')

  -- Check prerequisites
  if not beads_state.is_beads_available() then
    vim.notify("No .beads directory found. Run 'br init' first.", vim.log.levels.WARN)
    return
  end

  if not beads_state.is_cli_installed() then
    vim.notify("Beads CLI not installed", vim.log.levels.WARN)
    return
  end

  -- Get ready issues
  local ready = beads_state.get_ready_issues(true)

  if not ready or #ready == 0 then
    vim.notify("No ready issues (all blocked or completed)", vim.log.levels.INFO)
    return
  end

  -- Build selection options
  local options = {}
  for _, issue in ipairs(ready) do
    local status_icon = require('nexus.render.components.beads').get_status_icon(issue.status or 'open')
    local priority = require('nexus.render.components.beads').get_priority_label(issue.priority or 2)
    local title = issue.title or "Untitled"
    if #title > 50 then
      title = title:sub(1, 47) .. "..."
    end
    table.insert(options, string.format("%s %s [%s] %s", status_icon, priority, issue.id, title))
  end

  -- Show selection
  vim.ui.select(options, {
    prompt = 'Ready issues (no blockers):',
    format_item = function(item) return item end
  }, function(choice, idx)
    if not choice or not idx then return end

    local issue = ready[idx]
    M.show_issue_popup(issue, config, buf, render_callback)
  end)
end

--- Show epic with children navigation popup
---@param epic table Epic data
---@param config table Nexus config
---@param buf number Parent buffer number
---@param render_callback function Callback to re-render buffer
function M.show_epic_children_popup(epic, config, buf, render_callback)
  local beads_state = require('nexus.state.beads')
  local beads_component = require('nexus.render.components.beads')

  -- Get children
  local children = beads_state.get_epic_children(epic.id)

  -- Build popup content
  local lines = {}
  local width = 70

  -- Header
  local title_line = string.format("[%s] %s", epic.id or "???", epic.title or "Untitled Epic")
  table.insert(lines, title_line)
  table.insert(lines, string.rep("─", math.min(#title_line, width)))
  table.insert(lines, "")

  -- Epic metadata
  local meta_parts = {}
  if epic.status then
    table.insert(meta_parts, "Status: " .. epic.status)
  end
  if epic.priority ~= nil then
    local priority_labels = { [0]="P0 (Critical)", [1]="P1 (High)", [2]="P2 (Medium)", [3]="P3 (Low)", [4]="P4 (Backlog)" }
    table.insert(meta_parts, "Priority: " .. (priority_labels[epic.priority] or "P" .. epic.priority))
  end
  if #meta_parts > 0 then
    table.insert(lines, table.concat(meta_parts, " | "))
    table.insert(lines, "")
  end

  -- Description
  if epic.description and epic.description ~= '' then
    table.insert(lines, "Description:")
    for _, desc_line in ipairs(vim.split(epic.description, '\n')) do
      table.insert(lines, "  " .. desc_line)
    end
    table.insert(lines, "")
  end

  -- Children section
  if #children > 0 then
    table.insert(lines, string.format("Children (%d):", #children))
    table.insert(lines, "")

    for i, child in ipairs(children) do
      local status_icon = beads_component.get_status_icon(child.status or 'open')
      local priority = beads_component.get_priority_label(child.priority or 2)
      local title = child.title or "Untitled"
      if #title > 45 then
        title = title:sub(1, 42) .. "..."
      end

      local child_line = string.format("%d. %s %s [%s] %s", i, status_icon, priority, child.id, title)

      -- Mark closed children with strikethrough visual indicator
      if child._is_closed or child.status == 'closed' then
        child_line = child_line .. " (closed)"
      end

      table.insert(lines, "  " .. child_line)
    end
    table.insert(lines, "")
    table.insert(lines, "Enter number to view child issue")
  else
    table.insert(lines, "No children found")
    table.insert(lines, "")
  end

  -- Actions
  table.insert(lines, "Actions:")
  table.insert(lines, "  s - Update epic status")
  table.insert(lines, "  p - Change priority")
  table.insert(lines, "  c - Create child issue")
  table.insert(lines, "  q/Esc - Close")

  -- Calculate dimensions
  local max_width = 0
  for _, line in ipairs(lines) do
    max_width = math.max(max_width, #line)
  end
  width = math.min(max_width + 4, 90)
  local height = math.min(#lines + 2, 35)

  -- Create popup buffer
  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(popup_buf, 'buftype', 'nofile')

  -- Calculate position (centered)
  local win_width = vim.api.nvim_get_option('columns')
  local win_height = vim.api.nvim_get_option('lines')
  local row = math.floor((win_height - height) / 2)
  local col = math.floor((win_width - width) / 2)

  -- Create popup window
  local popup_win = vim.api.nvim_open_win(popup_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = ' Epic: ' .. (epic.id or '???') .. ' ',
    title_pos = 'center',
  })

  -- Apply highlighting
  local ns_id = vim.api.nvim_create_namespace('nexus_beads_epic_popup')
  vim.api.nvim_buf_set_extmark(popup_buf, ns_id, 0, 0, {
    end_col = #lines[1],
    hl_group = 'Title',
  })

  -- Set up keymaps for popup
  local opts = { noremap = true, silent = true, buffer = popup_buf }

  local function close_popup()
    if vim.api.nvim_win_is_valid(popup_win) then
      vim.api.nvim_win_close(popup_win, true)
    end
  end

  vim.keymap.set('n', 'q', close_popup, opts)
  vim.keymap.set('n', '<Esc>', close_popup, opts)

  -- Number keymaps for selecting children
  if #children > 0 then
    for i = 1, math.min(#children, 9) do
      vim.keymap.set('n', tostring(i), function()
        close_popup()
        local child = children[i]
        M.show_issue_popup(child, config, buf, render_callback)
      end, opts)
    end
  end

  vim.keymap.set('n', 's', function()
    close_popup()
    local line = "  [" .. epic.id .. "]"
    M.handle_status_update(line, buf, render_callback, config)
  end, opts)

  vim.keymap.set('n', 'p', function()
    close_popup()
    M.handle_priority_change(epic.id, buf, render_callback, config)
  end, opts)

  vim.keymap.set('n', 'c', function()
    close_popup()
    M.handle_create_child(epic.id, buf, render_callback, config)
  end, opts)
end

--- Handle creating a child issue for an epic
---@param parent_id string Parent epic ID
---@param buf number Buffer number
---@param render_callback function Callback to re-render buffer
---@param config table Nexus config
function M.handle_create_child(parent_id, buf, render_callback, config)
  local beads_state = require('nexus.state.beads')

  vim.ui.input({ prompt = 'Child issue title: ' }, function(title)
    if not title or title == '' then return end

    -- Prompt for type
    vim.ui.select({ 'task', 'bug', 'feature', 'chore' }, {
      prompt = 'Issue type:',
    }, function(issue_type)
      if not issue_type then return end

      -- Prompt for priority
      vim.ui.select({
        'P0 (Critical)',
        'P1 (High)',
        'P2 (Medium)',
        'P3 (Low)',
        'P4 (Backlog)'
      }, {
        prompt = 'Priority:',
      }, function(priority_choice)
        local priority = 2 -- Default to medium
        if priority_choice then
          priority = tonumber(priority_choice:match('P(%d)')) or 2
        end

        -- Create the child issue
        local issue, err = beads_state.create_issue(title, {
          type = issue_type,
          priority = priority,
          parent = parent_id
        })

        if err then
          vim.notify("Failed to create child issue: " .. err, vim.log.levels.ERROR)
          return
        end

        vim.notify(string.format("Created child: %s", issue and issue.id or title), vim.log.levels.INFO)
        render_callback(buf)
      end)
    end)
  end)
end

return M
