--- Beads section render component for Nexus
--- Builds and formats the Beads Issues section display
---@module nexus.render.components.beads

local M = {}

local logger = require('nexus.logger')

-- Status icons
local STATUS_ICONS = {
  open = "○",
  in_progress = "●",
  blocked = "◐",
  deferred = "◇",
  closed = "✓"
}

-- Priority labels
local PRIORITY_LABELS = {
  [0] = "P0",
  [1] = "P1",
  [2] = "P2",
  [3] = "P3",
  [4] = "P4"
}

-- Priority colors (highlight groups)
local PRIORITY_COLORS = {
  [0] = "DiagnosticError",   -- Critical - red
  [1] = "DiagnosticWarn",    -- High - orange/yellow
  [2] = "DiagnosticInfo",    -- Medium - blue
  [3] = "Comment",           -- Low - gray
  [4] = "Comment"            -- Backlog - gray
}

-- Status colors
local STATUS_COLORS = {
  open = "DiagnosticInfo",
  in_progress = "String",
  blocked = "DiagnosticError",
  deferred = "Comment",
  closed = "DiagnosticOk"
}

-- Line to issue mapping for navigation
local _line_to_issue_map = {}
local _section_start_line = 0

--- Get status icon for a status string
---@param status string Issue status
---@return string icon
function M.get_status_icon(status)
  return STATUS_ICONS[status] or "○"
end

--- Get priority label for priority number
---@param priority number Priority (0-4)
---@return string label
function M.get_priority_label(priority)
  return PRIORITY_LABELS[priority] or "P2"
end

--- Get highlight group for priority
---@param priority number Priority (0-4)
---@return string highlight_group
function M.get_priority_color(priority)
  return PRIORITY_COLORS[priority] or "Comment"
end

--- Get highlight group for status
---@param status string Issue status
---@return string highlight_group
function M.get_status_color(status)
  return STATUS_COLORS[status] or "Comment"
end

--- Format a single issue line
---@param issue table Issue data from beads
---@param config table Nexus config
---@return string formatted_line
function M.format_issue_line(issue, config)
  local beads_config = config.beads or {}

  local parts = {}

  -- Status icon
  local status = issue.status or 'open'
  table.insert(parts, M.get_status_icon(status))

  -- Priority (if enabled)
  if beads_config.show_priority ~= false then
    local priority = issue.priority or 2
    table.insert(parts, M.get_priority_label(priority))
  end

  -- Issue ID in brackets
  table.insert(parts, string.format("[%s]", issue.id or "???"))

  -- Title (truncate if too long)
  local title = issue.title or "Untitled"
  if #title > 50 then
    title = title:sub(1, 47) .. "..."
  end
  table.insert(parts, title)

  -- Status in parentheses (if enabled)
  if beads_config.show_status ~= false then
    table.insert(parts, string.format("(%s)", status))
  end

  -- Blocked by info (if enabled and blocked)
  if beads_config.show_blocked_by ~= false and status == 'blocked' then
    if issue.blockedBy and #issue.blockedBy > 0 then
      local blockers = {}
      for _, blocker in ipairs(issue.blockedBy) do
        if type(blocker) == 'string' then
          table.insert(blockers, blocker)
        elseif type(blocker) == 'table' and blocker.id then
          table.insert(blockers, blocker.id)
        end
      end
      if #blockers > 0 then
        table.insert(parts, string.format("[blocked by %s]", table.concat(blockers, ", ")))
      end
    end
  end

  return table.concat(parts, " ")
end

--- Build the beads section content
---@param config table Nexus config
---@return table lines Array of display lines
function M.build_beads_section(config)
  local beads_state = require('nexus.state.beads')
  local lines = {}
  _line_to_issue_map = {}

  -- Section header
  table.insert(lines, "Beads Issues:")
  table.insert(lines, "")

  local cli = require('nexus.config').get().beads.cli or 'br'

  -- Check if beads is available
  if not beads_state.is_beads_available() then
    table.insert(lines, "  No .beads directory found")
    table.insert(lines, "  Run '" .. cli .. " init' to initialize beads")
    return lines
  end
  if not beads_state.is_cli_installed() then
    table.insert(lines, "  " .. cli .. " CLI not installed")
    table.insert(lines, "  Install from: github.com/anthropics/beads")
    return lines
  end

  -- Check loading state
  if beads_state.is_loading() then
    table.insert(lines, "  Loading issues...")
    return lines
  end

  -- Check for errors
  local error = beads_state.get_error()
  if error then
    table.insert(lines, "  Error: " .. error)
    table.insert(lines, "  Press 'r' to retry")
    return lines
  end

  -- Get issues (will use cache or refresh as needed)
  beads_state.refresh_if_needed(config)
  local issues = beads_state.get_cached_issues()

  if not issues or #issues == 0 then
    local filter = (config.beads and config.beads.filter) or 'ready'
    if filter == 'ready' then
      table.insert(lines, "  No ready issues (all blocked or completed)")
    else
      table.insert(lines, "  No issues found")
    end
    table.insert(lines, "  Press 'c' to create a new issue")
    return lines
  end

  -- Limit issues shown
  local max_issues = (config.beads and config.beads.max_issues) or 10
  local shown_count = 0

  for i, issue in ipairs(issues) do
    if shown_count >= max_issues then
      local remaining = #issues - shown_count
      if remaining > 0 then
        table.insert(lines, string.format("  ... and %d more issues", remaining))
      end
      break
    end

    local line = "  " .. M.format_issue_line(issue, config)
    table.insert(lines, line)

    -- Track line mapping (will be adjusted when we know section start)
    _line_to_issue_map[#lines] = issue.id
    shown_count = shown_count + 1
  end

  -- Update state with line mapping
  beads_state.set_line_mapping(_line_to_issue_map)

  return lines
end

--- Check if a line is a beads issue line
---@param line string Line content
---@return boolean is_issue
---@return string|nil issue_id
function M.is_beads_issue_line(line)
  if not line then return false, nil end

  -- Pattern: starts with optional whitespace, status icon, and contains [bd-xxx] or [Prefix-xxx]
  -- Match patterns like: "  ● P0 [bd-a3f8] Title"
  local issue_id = line:match("%[([%w%-]+)%]")

  if issue_id then
    -- Check if it looks like a beads issue ID (has hyphen, starts with letters)
    if issue_id:match("^%a+%-") then
      return true, issue_id
    end
  end

  return false, nil
end

--- Get issue ID from line content
---@param line string Line content
---@return string|nil issue_id
function M.get_issue_id_from_line(line)
  local _, issue_id = M.is_beads_issue_line(line)
  return issue_id
end

--- Get issue from line by looking up in cached issues
---@param line string Line content
---@param issues table|nil Issues array (optional, will fetch from state if nil)
---@return table|nil issue
function M.get_issue_from_line(line, issues)
  local issue_id = M.get_issue_id_from_line(line)
  if not issue_id then return nil end

  issues = issues or require('nexus.state.beads').get_cached_issues()

  for _, issue in ipairs(issues) do
    if issue.id == issue_id then
      return issue
    end
  end

  return nil
end

--- Apply beads-specific highlighting to buffer
---@param buf number Buffer number
---@param section_start number Starting line of beads section
function M.apply_beads_highlighting(buf, section_start)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local ns_id = vim.api.nvim_create_namespace('nexus_beads')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Find beads section
  local in_beads_section = false
  local section_end = #lines

  for i, line in ipairs(lines) do
    if line:match("^%s*Beads Issues:") or line:match("^%s*[▼▶] Beads Issues:") then
      in_beads_section = true
      section_start = i
    elseif in_beads_section and line:match("^%s*[%w]+ [%w]+:") and not line:match("Beads") then
      -- Next section header
      section_end = i - 1
      break
    end

    if in_beads_section and i > section_start then
      M.highlight_beads_line(buf, ns_id, i - 1, line)
    end
  end
end

--- Highlight a single beads issue line
---@param buf number Buffer number
---@param ns_id number Namespace ID
---@param line_idx number 0-indexed line number
---@param line string Line content
function M.highlight_beads_line(buf, ns_id, line_idx, line)
  if not line or line == '' then return end

  -- Highlight issue ID [xxx-yyy]
  local id_start, id_end = line:find("%[[%w%-]+%]")
  if id_start then
    vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, id_start - 1, {
      end_col = id_end,
      hl_group = 'Number',
      strict = false
    })
  end

  -- Highlight priority (P0, P1, etc.)
  local p_start, p_end, priority = line:find("(P[0-4])")
  if p_start and priority then
    local p_num = tonumber(priority:sub(2))
    local hl_group = M.get_priority_color(p_num)
    vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, p_start - 1, {
      end_col = p_end,
      hl_group = hl_group,
      strict = false
    })
  end

  -- Highlight status in parentheses
  local status_start, status_end, status = line:find("%(([%w_]+)%)%s*$")
  if status_start and status then
    local hl_group = M.get_status_color(status)
    vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, status_start - 1, {
      end_col = status_end,
      hl_group = hl_group,
      strict = false
    })
  end

  -- Highlight blocked by info
  local blocked_start, blocked_end = line:find("%[blocked by [^%]]+%]")
  if blocked_start then
    vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, blocked_start - 1, {
      end_col = blocked_end,
      hl_group = 'DiagnosticError',
      strict = false
    })
  end

  -- Highlight status icons
  for icon, hl in pairs({
    ["●"] = "String",           -- in_progress
    ["○"] = "DiagnosticInfo",   -- open
    ["◐"] = "DiagnosticError",  -- blocked
    ["◇"] = "Comment",          -- deferred
    ["✓"] = "DiagnosticOk"      -- closed
  }) do
    local icon_start = line:find(icon, 1, true)
    if icon_start then
      -- Icons are multi-byte, need to handle correctly
      local byte_start = icon_start - 1
      local byte_end = byte_start + #icon
      vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, byte_start, {
        end_col = byte_end,
        hl_group = hl,
        strict = false
      })
      break
    end
  end
end

--- Update line mapping with actual section start line
---@param section_start number Starting line of beads section in buffer
function M.update_line_mapping(section_start)
  _section_start_line = section_start

  -- Update the mapping in state with adjusted line numbers
  local beads_state = require('nexus.state.beads')
  local adjusted_mapping = {}

  for relative_line, issue_id in pairs(_line_to_issue_map) do
    local absolute_line = section_start + relative_line - 1
    adjusted_mapping[absolute_line] = issue_id
  end

  beads_state.set_line_mapping(adjusted_mapping)
end

return M
