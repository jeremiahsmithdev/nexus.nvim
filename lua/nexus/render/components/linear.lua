---@class LinearComponent
local M = {}

local linear_state = require('nexus.state.linear')
local logger = require('nexus.logger')

-- Icons for different states and priorities
local ICONS = {
  linear = "🔗",
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
  state = {
    backlog = "📋",
    unstarted = "⭕",
    started = "🔄",
    completed = "✅",
    canceled = "❌"
  }
}

-- Priority levels mapping (Linear uses 0-4)
local PRIORITY_LEVELS = {
  [0] = "none",
  [1] = "low",
  [2] = "medium", 
  [3] = "high",
  [4] = "urgent"
}

---Build Linear issues section
---@param config table Nexus configuration
---@return table section
function M.build_linear_section(config)
  logger.debug("LINEAR_COMPONENT", "Building Linear section", { enabled = config.linear and config.linear.enabled })
  
  if not config.linear or not config.linear.enabled then
    return {}
  end
  
  -- Refresh data if needed
  linear_state.refresh_if_needed(config)
  
  local lines = {}
  
  -- Section header
  table.insert(lines, "Linear Issues:")
  table.insert(lines, "")
  
  -- Check loading state
  if linear_state.is_loading() then
    table.insert(lines, "  " .. ICONS.spinner .. " Loading issues...")
    return lines
  end
  
  -- Check error state
  local error_msg = linear_state.get_error()
  if error_msg then
    table.insert(lines, "  " .. ICONS.error .. " " .. error_msg)
    return lines
  end
  
  -- Get issues from state
  local issues = linear_state.get_issues()
  if not issues or #issues == 0 then
    table.insert(lines, "  " .. ICONS.info .. " No issues found")
    return lines
  end
  
  -- Render each issue
  local max_issues = config.linear.max_issues or 10
  for i, issue in ipairs(issues) do
    if i > max_issues then
      break
    end
    
    local issue_line = M.format_issue_line(issue, config)
    table.insert(lines, "  " .. issue_line)
  end
  
  -- Show more indicator
  if #issues > max_issues then
    table.insert(lines, string.format("  ... and %d more", #issues - max_issues))
  end
  
  return lines
end

---Format single issue line
---@param issue table Linear issue data
---@param config table Nexus configuration
---@return string formatted_line
function M.format_issue_line(issue, config)
  local parts = {}
  
  -- State icon
  local state_icon = M.get_state_icon(issue.state)
  table.insert(parts, state_icon)
  
  -- Priority icon (only show for medium/high/urgent)
  if config.linear.show_priority ~= false and issue.priority and type(issue.priority) == "number" and issue.priority >= 2 then
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
  if config.linear.show_assignee ~= false and issue.assignee and type(issue.assignee) == "table" and issue.assignee.name then
    table.insert(parts, string.format("(@%s)", issue.assignee.name))
  end
  
  -- Estimate (if enabled and available)  
  if config.linear.show_estimates ~= false and issue.estimate and type(issue.estimate) == "number" and issue.estimate > 0 then
    table.insert(parts, string.format("(%dp)", issue.estimate))
  end
  
  -- Cycle info (if enabled and available)
  if config.linear.show_cycle ~= false and issue.cycle and type(issue.cycle) == "table" and issue.cycle.name then
    table.insert(parts, string.format("[%s]", issue.cycle.name))
  end
  
  return table.concat(parts, " ")
end

---Get priority icon
---@param priority number
---@return string icon
function M.get_priority_icon(priority)
  if not priority or type(priority) ~= "number" then
    return ""
  end
  local priority_name = PRIORITY_LEVELS[priority] or "none"
  return ICONS.priority[priority_name] or ""
end

---Get state icon
---@param state table Linear state
---@return string icon  
function M.get_state_icon(state)
  if not state or type(state) ~= "table" or not state.type then 
    return ICONS.state.unstarted 
  end
  
  -- Map Linear state types to our icons
  local state_type = tostring(state.type):lower()
  
  if state_type == "backlog" then
    return ICONS.state.backlog
  elseif state_type == "unstarted" then
    return ICONS.state.unstarted
  elseif state_type == "started" then
    return ICONS.state.started
  elseif state_type == "completed" then
    return ICONS.state.completed
  elseif state_type == "canceled" then
    return ICONS.state.canceled
  else
    -- Default for unknown states
    return ICONS.state.unstarted
  end
end

---Get status color for highlighting
---@param state table Linear state
---@return string color_group
function M.get_state_color(state)
  if not state or type(state) ~= "table" or not state.type then 
    return "Comment" 
  end
  
  local state_type = tostring(state.type):lower()
  
  if state_type == "backlog" then
    return "Comment"        -- Gray
  elseif state_type == "unstarted" then
    return "DiagnosticWarn" -- Yellow/Orange
  elseif state_type == "started" then
    return "DiagnosticInfo" -- Blue
  elseif state_type == "completed" then
    return "DiagnosticOk"   -- Green
  elseif state_type == "canceled" then
    return "DiagnosticError" -- Red
  else
    return "Comment"        -- Default gray
  end
end

---Get priority color for highlighting
---@param priority number
---@return string color_group
function M.get_priority_color(priority)
  if not priority or type(priority) ~= "number" then return "Comment" end
  
  if priority == 4 then      -- Urgent
    return "DiagnosticError"  -- Red
  elseif priority == 3 then  -- High
    return "DiagnosticWarn"   -- Orange/Yellow
  elseif priority == 2 then  -- Medium
    return "DiagnosticInfo"   -- Blue
  elseif priority == 1 then  -- Low
    return "DiagnosticHint"   -- Gray/Light
  else
    return "Comment"          -- None/Default
  end
end

---Check if line is a Linear issue line
---@param line string
---@return boolean is_issue_line
---@return string? issue_identifier
function M.is_linear_issue_line(line)
  if not line then return false, nil end
  
  -- Look for Linear issue pattern: starts with spaces, has emoji, then [IDENTIFIER]
  local pattern = "^%s*[🔗⚡❌ℹ️📋⭕🔄✅🟢🟡🟠🔴]*%s*%[([A-Z]+-[0-9]+)%]"
  local identifier = line:match(pattern)
  
  return identifier ~= nil, identifier
end

---Extract issue data from line
---@param line string
---@param issues table List of issues
---@return table? issue
function M.get_issue_from_line(line, issues)
  local is_issue, identifier = M.is_linear_issue_line(line)
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

return M