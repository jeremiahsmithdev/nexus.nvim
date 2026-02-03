---@class HulyComponent
local M = {}

local huly_state = require('nexus.state.huly')
local logger = require('nexus.logger')

-- Icons for different states and priorities
local ICONS = {
  huly = "🔷",
  spinner = "⚡",
  error = "❌",
  info = "ℹ️",
  priority = {
    none = "",
    low = "🟢",
    medium = "🟡",
    high = "🟠",
    urgent = "🔴"
  },
  status = {
    todo = "📋",
    in_progress = "🔄",
    done = "✅",
    canceled = "❌",
    backlog = "📝"
  }
}

-- Priority levels mapping (Huly uses string-based priorities)
local PRIORITY_MAPPING = {
  ["low"] = "low",
  ["medium"] = "medium",
  ["high"] = "high",
  ["urgent"] = "urgent",
  ["none"] = "none"
}

-- Status mapping for Huly
local STATUS_MAPPING = {
  ["todo"] = "todo",
  ["in progress"] = "in_progress",
  ["done"] = "done",
  ["canceled"] = "canceled",
  ["backlog"] = "backlog"
}

---Check if Huly is configured (has token and workspace)
---@param config table Nexus configuration
---@return boolean has_token
---@return boolean has_workspace
local function check_huly_config(config)
  local huly_config = config.huly or {}
  local has_token = (huly_config.token and huly_config.token ~= "") or (os.getenv("HULY_TOKEN") and os.getenv("HULY_TOKEN") ~= "")
  local has_workspace = (huly_config.workspace and huly_config.workspace ~= "") or (os.getenv("HULY_WORKSPACE") and os.getenv("HULY_WORKSPACE") ~= "")
  return has_token, has_workspace
end

---Build Huly issues section
---@param config table Nexus configuration
---@return table section
function M.build_huly_section(config)
  local has_token, has_workspace = check_huly_config(config)
  logger.debug("HULY", "Building Huly section", {
    enabled = config.huly and config.huly.enabled,
    has_token = has_token,
    has_workspace = has_workspace
  })

  local lines = {}

  -- Section header
  table.insert(lines, "Huly Issues:")
  table.insert(lines, "")

  -- Check if Huly needs setup
  if not has_token or not has_workspace then
    if not has_token then
      table.insert(lines, "  " .. ICONS.info .. " Huly token not configured")
    end
    if not has_workspace then
      table.insert(lines, "  " .. ICONS.info .. " Huly workspace not configured")
    end
    table.insert(lines, "")
    table.insert(lines, "  Press 'H' to configure Huly integration")
    return lines
  end

  -- Check if explicitly disabled
  if not config.huly or not config.huly.enabled then
    table.insert(lines, "  " .. ICONS.info .. " Huly integration disabled")
    table.insert(lines, "  Press 'H' to enable and configure")
    return lines
  end

  -- Refresh data if needed
  huly_state.refresh_if_needed(config)

  -- Check loading state
  if huly_state.is_loading() then
    table.insert(lines, "  " .. ICONS.spinner .. " Loading issues...")
    return lines
  end

  -- Check error state
  local error_msg = huly_state.get_error()
  if error_msg then
    table.insert(lines, "  " .. ICONS.error .. " " .. error_msg)
    return lines
  end

  -- Get issues from state
  local issues = huly_state.get_issues()
  if not issues or #issues == 0 then
    table.insert(lines, "  " .. ICONS.info .. " No issues found")
    return lines
  end

  -- Filter out completed/cancelled issues
  local active_issues = {}
  for _, issue in ipairs(issues) do
    local status = issue.status and issue.status:lower() or ""
    if not status:match("done") and not status:match("cancelled") and not status:match("canceled") then
      table.insert(active_issues, issue)
    end
  end

  -- Sort issues by last updated (most recent first)
  table.sort(active_issues, function(a, b)
    local updated_a = a.updatedOn or 0
    local updated_b = b.updatedOn or 0
    return updated_a > updated_b
  end)

  -- Render each issue
  local max_issues = config.huly.max_issues or 10
  local shown = 0
  for _, issue in ipairs(active_issues) do
    if shown >= max_issues then
      break
    end

    local issue_line = M.format_issue_line(issue, config)
    table.insert(lines, "  " .. issue_line)
    shown = shown + 1
  end

  -- Show more indicator
  if #active_issues > max_issues then
    table.insert(lines, string.format("  ... and %d more", #active_issues - max_issues))
  end

  return lines
end

---Format single issue line
---@param issue table Huly issue data
---@param config table Nexus configuration
---@return string formatted_line
function M.format_issue_line(issue, config)
  local parts = {}

  -- Status icon
  local status_icon = M.get_status_icon(issue.status)
  table.insert(parts, status_icon)

  -- Priority icon (only show for medium/high/urgent)
  if config.huly.show_priority ~= false and issue.priority then
    local priority_icon = M.get_priority_icon(issue.priority)
    if priority_icon and priority_icon ~= "" then
      table.insert(parts, priority_icon)
    end
  end

  -- Issue identifier and title
  local title = issue.title or "No title"
  if #title > 50 then
    title = title:sub(1, 47) .. "..."
  end
  table.insert(parts, string.format("[%s] %s", issue.identifier or "???", title))

  -- Assignee (if enabled and available)
  if config.huly.show_assignee ~= false and issue.assignee and type(issue.assignee) == "table" and issue.assignee.name then
    table.insert(parts, string.format("(@%s)", issue.assignee.name))
  end

  -- Project info (if enabled and available)
  if config.huly.show_project ~= false and issue.project and type(issue.project) == "table" and issue.project.name then
    table.insert(parts, string.format("[%s]", issue.project.name))
  end

  return table.concat(parts, " ")
end

---Get priority icon
---@param priority string|number
---@return string icon
function M.get_priority_icon(priority)
  if not priority then
    return ""
  end

  -- Convert to string if it's a number
  local priority_str = tostring(priority):lower()
  local priority_name = PRIORITY_MAPPING[priority_str] or "none"
  return ICONS.priority[priority_name] or ""
end

---Get status icon
---@param status string|table Huly status
---@return string icon
function M.get_status_icon(status)
  if not status then
    return ICONS.status.backlog
  end

  -- Handle if status is a table (for backward compatibility)
  if type(status) == "table" then
    if status.name then
      status = status.name
    elseif status.type then
      status = status.type
    else
      return ICONS.status.backlog
    end
  end

  -- Convert to lowercase for mapping
  local status_str = tostring(status):lower()
  local status_key = STATUS_MAPPING[status_str] or status_str

  return ICONS.status[status_key] or ICONS.status.backlog
end

---Get status color for highlighting
---@param status string|table Huly status
---@return string color_group
function M.get_status_color(status)
  if not status then
    return "Comment"
  end

  -- Handle if status is a table
  if type(status) == "table" then
    if status.name then
      status = status.name
    elseif status.type then
      status = status.type
    else
      return "Comment"
    end
  end

  -- Convert to lowercase for mapping
  local status_str = tostring(status):lower()

  if status_str:match("todo") or status_str:match("backlog") then
    return "Comment"        -- Gray
  elseif status_str:match("in progress") or status_str:match("progress") then
    return "DiagnosticInfo" -- Blue
  elseif status_str:match("done") or status_str:match("completed") then
    return "DiagnosticOk"   -- Green
  elseif status_str:match("cancel") then
    return "DiagnosticError" -- Red
  else
    return "Comment"        -- Default gray
  end
end

---Get priority color for highlighting
---@param priority string|number
---@return string color_group
function M.get_priority_color(priority)
  if not priority then
    return "Comment"
  end

  -- Convert to string if it's a number
  local priority_str = tostring(priority):lower()

  if priority_str:match("urgent") then
    return "DiagnosticError"  -- Red
  elseif priority_str:match("high") then
    return "DiagnosticWarn"   -- Orange/Yellow
  elseif priority_str:match("medium") then
    return "DiagnosticInfo"   -- Blue
  elseif priority_str:match("low") then
    return "DiagnosticHint"   -- Gray/Light
  else
    return "Comment"          -- None/Default
  end
end

---Check if line is a Huly issue line
---@param line string
---@return boolean is_issue_line
---@return string? issue_identifier
function M.is_huly_issue_line(line)
  if not line then return false, nil end

  -- Look for Huly issue pattern: starts with spaces, has emoji, then [IDENTIFIER]
  -- Huly identifiers are typically in format like "HULY-123" or similar
  local pattern = "^%s*[🔷⚡❌ℹ️📋🔄✅❌📝🟢🟡🟠🔴]*%s*%[([A-Z]+-[0-9]+)%]"
  local identifier = line:match(pattern)

  return identifier ~= nil, identifier
end

---Extract issue data from line
---@param line string
---@param issues table List of issues
---@return table? issue
function M.get_issue_from_line(line, issues)
  local is_issue, identifier = M.is_huly_issue_line(line)
  if not is_issue or not identifier or not issues then
    return nil
  end

  -- Find the issue by identifier
  for _, issue in ipairs(issues) do
    if issue.identifier == identifier then
      return issue
    end
  end

  return nil
end

---Create syntax highlighting for Huly section
---@param bufnr number Buffer number
function M.apply_syntax_highlighting(bufnr)
  local namespace = vim.api.nvim_create_namespace("nexus_huly")

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  -- Get all lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Apply highlights to each line
  for i, line in ipairs(lines) do
    local line_num = i - 1  -- Convert to 0-based

    -- Check if this is an issue line
    local is_issue_line, identifier = M.is_huly_issue_line(line)
    if is_issue_line and identifier then
      -- Get the issue from current state
      local issues = huly_state.get_issues()
      local issue = M.get_issue_from_line(line, issues)

      if issue then
        -- Highlight status icon
        local status_start = line:find("[🔷⚡❌ℹ️📋🔄✅❌📝]")
        if status_start then
          vim.api.nvim_buf_add_highlight(bufnr, namespace, M.get_status_color(issue.status), line_num, status_start - 1, status_start)
        end

        -- Highlight priority icon
        if issue.priority then
          local priority_start = line:find("[🟢🟡🟠🔴]", status_start or 1)
          if priority_start then
            vim.api.nvim_buf_add_highlight(bufnr, namespace, M.get_priority_color(issue.priority), line_num, priority_start - 1, priority_start)
          end
        end

        -- Highlight identifier
        local id_start, id_end = line:find("%[" .. identifier .. "%]")
        if id_start and id_end then
          vim.api.nvim_buf_add_highlight(bufnr, namespace, "Number", line_num, id_start - 1, id_end)
        end

        -- Highlight assignee name
        if issue.assignee and issue.assignee.name then
          local assignee_start, assignee_end = line:find("@[^%s)]+")
          if assignee_start and assignee_end then
            vim.api.nvim_buf_add_highlight(bufnr, namespace, "Function", line_num, assignee_start - 1, assignee_end)
          end
        end
      end
    elseif line:match("^Huly Issues:") or line:match("^[▼▶] Huly Issues:") then
      -- Highlight section header
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "Title", line_num, 0, -1)
    elseif line:match("Workspace:") or line:match("Project:") then
      -- Highlight context information
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "Comment", line_num, 2, -1)
    end
  end
end

return M