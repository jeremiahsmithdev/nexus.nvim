# Linear Integration Implementation Plan

## Executive Summary

This document provides a comprehensive implementation roadmap for integrating Linear API with Nexus.nvim, building upon the **completed refactored architecture**. The integration leverages the existing provider system, action pattern, centralized state management, and component-based rendering to create a seamless developer dashboard that connects git workflows with Linear project management.

## Integration Goals

### Primary Objectives
1. **Seamless Issue Management** - View, update, and create Linear issues directly from Neovim
2. **Git-Linear Synchronization** - Automatic branch/commit linking with Linear issues
3. **Productivity Enhancement** - Reduce context switching between tools
4. **Developer Experience** - Intuitive interface matching Neovim workflows

### Success Metrics
- Issue operations complete in < 500ms (cached) / < 2s (fresh)
- 95% uptime with graceful degradation when Linear API is unavailable
- Zero blocking operations on Neovim UI thread
- Support for teams with 100+ issues without performance degradation

## Technical Architecture

### Linear Provider Implementation

**Updated Architecture (Aligned with Existing Codebase):**
```
lua/nexus/providers/
├── linear.lua              -- Main Linear provider (existing, needs enhancement)
├── base.lua               -- Base provider class (existing)
└── manager.lua            -- Provider manager (existing)

lua/nexus/state/
└── linear.lua             -- Linear state management (new)

lua/nexus/actions/linear/
├── browse.lua             -- Open issues in browser
├── create.lua             -- Create new issues  
├── update.lua             -- Update issue state
└── sync.lua               -- Git-Linear synchronization

lua/nexus/render/components/
└── linear.lua             -- Linear dashboard component (new)
```

**Key Changes from Original Plan:**
- ✅ Use existing provider base class and manager
- ✅ Integrate HTTP client directly into provider
- ✅ Use centralized state management instead of local caching
- ✅ Follow established action pattern
- ✅ Component-based rendering architecture

### Data Flow Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   User Input    │───▶│  Linear Action   │───▶│ Linear Provider │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │                        │
                                ▼                        ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │ Linear State     │    │  Linear API     │
                       │ (Centralized)    │    │ (HTTP/GraphQL)  │
                       └──────────────────┘    └─────────────────┘
                                │                        │
                                ▼                        ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │ Linear Component │    │ Cache State     │
                       │ (Render)         │    │ (Centralized)   │
                       └──────────────────┘    └─────────────────┘
```

**Architecture Benefits:**
- ✅ Leverages existing refactored systems
- ✅ Consistent with current codebase patterns  
- ✅ Minimal new architectural concepts
- ✅ Reuses state management and caching infrastructure

## Implementation Phases

## Phase 1: Enhanced Linear Provider (Week 1)

### 1.1 HTTP Client Integration

**File: `lua/nexus/providers/linear.lua` (Enhancement)**
```lua
-- Enhanced _make_request implementation using vim.fn.system
function LinearProvider:_make_request(data)
  if not data or not data.query then
    return false, { errors = { { message = "No query provided" } } }
  end
  
  local payload = vim.json.encode({
    query = data.query,
    variables = data.variables or {}
  })
  
  -- Use curl via vim.fn.system for HTTP requests
  local curl_command = string.format([[
    curl -X POST "https://api.linear.app/graphql" \
    -H "Content-Type: application/json" \
    -H "Authorization: %s" \
    -d '%s' \
    --silent \
    --max-time 10
  ]], self.api_key, payload:gsub("'", "'\\''"))
  
  local response = vim.fn.system(curl_command)
  local exit_code = vim.v.shell_error
  
  if exit_code ~= 0 then
    return false, { errors = { { message = "HTTP request failed: " .. response } } }
  end
  
  local ok, decoded = pcall(vim.json.decode, response)
  if not ok then
    return false, { errors = { { message = "Failed to parse JSON response" } } }
  end
  
  if decoded.errors then
    return false, decoded
  end
  
  return true, decoded
end
```

### 1.2 Linear State Management

**File: `lua/nexus/state/linear.lua` (New)**
```lua
---@class LinearState
local M = {}

local logger = require('nexus.logger')
local cache_state = require('nexus.state.cache')

-- Linear state keys
local STATE_KEYS = {
  ISSUES = 'linear.issues',
  USER_INFO = 'linear.user_info',
  TEAMS = 'linear.teams',
  LOADING = 'linear.loading',
  ERROR = 'linear.error',
  LAST_SYNC = 'linear.last_sync'
}

---Initialize Linear state
function M.init()
  local state_manager = require('nexus.state.manager')
  
  -- Register Linear state fields
  for key, state_key in pairs(STATE_KEYS) do
    state_manager.register_field(state_key, nil)
  end
  
  logger.info("LINEAR_STATE", "Linear state initialized")
end

---Get Linear issues from state
---@return table? issues
function M.get_issues()
  local state_manager = require('nexus.state.manager')
  return state_manager.get_field(STATE_KEYS.ISSUES)
end

---Set Linear issues in state
---@param issues table
function M.set_issues(issues)
  local state_manager = require('nexus.state.manager')
  state_manager.set_field(STATE_KEYS.ISSUES, issues)
  state_manager.set_field(STATE_KEYS.LAST_SYNC, os.time())
end

---Get loading state
---@return boolean
function M.is_loading()
  local state_manager = require('nexus.state.manager')
  return state_manager.get_field(STATE_KEYS.LOADING) or false
end

---Set loading state  
---@param loading boolean
function M.set_loading(loading)
  local state_manager = require('nexus.state.manager')
  state_manager.set_field(STATE_KEYS.LOADING, loading)
end

---Get error state
---@return string? error
function M.get_error()
  local state_manager = require('nexus.state.manager')
  return state_manager.get_field(STATE_KEYS.ERROR)
end

---Set error state
---@param error string?
function M.set_error(error)
  local state_manager = require('nexus.state.manager')
  state_manager.set_field(STATE_KEYS.ERROR, error)
end

---Clear all Linear state
function M.clear()
  local state_manager = require('nexus.state.manager')
  for key, state_key in pairs(STATE_KEYS) do
    state_manager.set_field(state_key, nil)
  end
end

return M
```

### 1.3 Enhanced Configuration Schema

**File: `lua/nexus/config.lua` (Enhancement)**
```lua
-- Enhanced Linear configuration (expand existing linear section)
linear = {
  enabled = false,                    -- Enable Linear integration
  api_key = vim.env.LINEAR_API_KEY,   -- Linear API key (prefer env var)
  default_team_id = nil,              -- Default team for new issues
  max_issues = 10,                    -- Maximum issues to show in dashboard
  show_assignee = true,               -- Show assignee information
  show_priority = true,               -- Show issue priorities
  show_estimates = true,              -- Show story point estimates
  show_cycle = true,                  -- Show cycle/sprint information
  auto_refresh = 300,                 -- Auto-refresh interval in seconds (0 to disable)
  
  -- Branch integration settings
  branch_integration = {
    enabled = true,                   -- Enable branch-issue linking
    auto_create_from_issue = false,   -- Auto-create branches from issues
    branch_naming_pattern = "feat/%s-%s", -- identifier-title-slug
    require_issue_link = false,       -- Require Linear issue link in branches
  },
  
  -- Commit integration settings  
  commit_integration = {
    enabled = true,                   -- Enable commit-issue linking
    auto_add_issue_id = true,         -- Auto-add issue ID to commit messages
    validate_against_issue = true,    -- Validate commits against Linear issues
    auto_update_status = true,        -- Auto-update issue status on commits
    completion_keywords = {           -- Keywords that trigger issue completion
      "fix", "fixes", "fixed",
      "close", "closes", "closed",
      "resolve", "resolves", "resolved",
      "complete", "completes", "completed"
    },
  },
  
  -- Cache settings
  cache = {
    issues_ttl = 300,                 -- Issues cache TTL (5 minutes)
    teams_ttl = 3600,                 -- Teams cache TTL (1 hour)  
    user_info_ttl = 3600,             -- User info cache TTL (1 hour)
  }
}
```

## Phase 2: Linear Actions Implementation (Week 2)

### 2.1 Linear Browse Action

**File: `lua/nexus/actions/linear/browse.lua` (New)**
```lua
local BaseAction = require('nexus.actions.base')
local logger = require('nexus.logger')

---@class LinearBrowseAction : BaseAction
local LinearBrowseAction = {}

function LinearBrowseAction.new()
  local instance = BaseAction:new({
    category = "linear",
    name = "linear.browse",
    description = "Open Linear issue in browser",
    can_undo = false
  })
  setmetatable(instance, { __index = LinearBrowseAction })
  return instance
end

---Execute browse action
---@param context table Action context with issue data
---@return boolean success
---@return string? error_message
function LinearBrowseAction:execute(context)
  logger.debug("LINEAR_ACTION", "Executing browse action", { context = context })
  
  if not context or not context.issue then
    return false, "No issue data provided"
  end
  
  local issue = context.issue
  if not issue.url then
    return false, "Issue URL not available"
  end
  
  -- Platform-specific URL opening
  local open_cmd
  if vim.fn.has('mac') == 1 then
    open_cmd = 'open'
  elseif vim.fn.has('unix') == 1 then
    open_cmd = 'xdg-open'
  elseif vim.fn.has('win32') == 1 then
    open_cmd = 'start'
  else
    return false, "Unsupported platform for opening URLs"
  end
  
  -- Execute command
  local result = vim.fn.system(string.format('%s "%s"', open_cmd, issue.url))
  local exit_code = vim.v.shell_error
  
  if exit_code == 0 then
    logger.info("LINEAR_ACTION", "Opened issue in browser", { 
      identifier = issue.identifier,
      url = issue.url 
    })
    vim.notify(string.format("Opened %s in browser", issue.identifier), vim.log.levels.INFO)
    return true
  else
    local error_msg = string.format("Failed to open browser: %s", result)
    logger.error("LINEAR_ACTION", error_msg, { exit_code = exit_code })
    return false, error_msg
  end
end

return LinearBrowseAction
```

## Phase 3: UI Integration (Week 3)

### 3.1 Linear Dashboard Component

**File: `lua/nexus/render/components/linear.lua` (New)**
```lua
---@class LinearComponent
local M = {}

local linear_state = require('nexus.state.linear')
local logger = require('nexus.logger')

-- Icons (simplified without external dependency)
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
    todo = "⭕",
    in_progress = "🔄",
    done = "✅",
    canceled = "❌"
  }
}

---Build Linear issues section
---@param config table Nexus configuration
---@return table section
function M.build_linear_section(config)
  logger.debug("LINEAR_COMPONENT", "Building Linear section", { enabled = config.linear.enabled })
  
  if not config.linear.enabled then
    return {}
  end
  
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
  
  table.insert(lines, "") -- Spacing after section
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
  
  -- Priority icon (if high/urgent)
  if config.linear.show_priority and issue.priority >= 2 then
    local priority_icon = M.get_priority_icon(issue.priority)
    table.insert(parts, priority_icon)
  end
  
  -- Issue identifier and title
  table.insert(parts, string.format("[%s] %s", issue.identifier, issue.title))
  
  -- Assignee (if enabled and available)
  if config.linear.show_assignee and issue.assignee then
    table.insert(parts, string.format("(@%s)", issue.assignee.name))
  end
  
  -- Estimate (if enabled and available)  
  if config.linear.show_estimates and issue.estimate then
    table.insert(parts, string.format("(%dp)", issue.estimate))
  end
  
  return table.concat(parts, " ")
end

---Get priority icon
---@param priority number
---@return string icon
function M.get_priority_icon(priority)
  if priority == 0 then return ICONS.priority.none end
  if priority == 1 then return ICONS.priority.low end
  if priority == 2 then return ICONS.priority.medium end
  if priority == 3 then return ICONS.priority.high end
  if priority == 4 then return ICONS.priority.urgent end
  return ICONS.priority.none
end

---Get state icon
---@param state table Linear state
---@return string icon  
function M.get_state_icon(state)
  if not state then return ICONS.state.todo end
  
  if state.type == "backlog" then return ICONS.state.backlog end
  if state.type == "unstarted" then return ICONS.state.todo end
  if state.type == "started" then return ICONS.state.in_progress end  
  if state.type == "completed" then return ICONS.state.done end
  if state.type == "canceled" then return ICONS.state.canceled end
  return ICONS.state.todo
end

return M
```

### 3.2 Integration with Sections Component

**File: `lua/nexus/render/components/sections.lua` (Enhancement)**
```lua
-- Add to existing build_sections function
local function build_sections(config, is_git_repo, files)
  local sections = {}
  
  -- ... existing sections code ...
  
  -- Add Linear section if enabled
  if config.linear and config.linear.enabled then
    local linear_component = require('nexus.render.components.linear')
    sections.linear_issues = linear_component.build_linear_section(config)
  end
  
  return sections
end
```

## Phase 3: Git-Linear Integration (Week 3)

### 3.1 Git-Linear State Integration

**File: `lua/nexus/git/linear_integration.lua` (New)**
```lua
---@class GitLinearIntegration  
local M = {}

local git_state = require('nexus.state.git')
local linear_state = require('nexus.state.linear')
local logger = require('nexus.logger')

-- Pattern matching for Linear issue IDs in branch names
local ISSUE_ID_PATTERNS = {
  "^feat/([A-Z]+%-[0-9]+)",     -- feat/LIN-123-description
  "^fix/([A-Z]+%-[0-9]+)",      -- fix/LIN-123-bugfix  
  "^([A-Z]+%-[0-9]+)",          -- LIN-123-feature
  "/([A-Z]+%-[0-9]+)",          -- any/path/LIN-123-desc
}

---Extract Linear issue ID from current branch
---@return string? issue_id
function M.get_current_issue_id()
  local current_branch = git_state.get_current_branch()
  if not current_branch then
    return nil
  end
  
  for _, pattern in ipairs(ISSUE_ID_PATTERNS) do
    local issue_id = current_branch:match(pattern)
    if issue_id then
      logger.debug("GIT_LINEAR", "Found issue ID in branch", { 
        branch = current_branch,
        issue_id = issue_id
      })
      return issue_id
    end
  end
  
  return nil
end

---Get Linear issue for current branch using centralized state
---@return table? issue, string? error  
function M.get_current_branch_issue()
  local issue_id = M.get_current_issue_id()
  if not issue_id then
    return nil, "No Linear issue ID found in current branch"
  end
  
  -- Get all issues from Linear state
  local issues = linear_state.get_issues()
  if not issues then
    return nil, "No Linear issues available in state"
  end
  
  -- Find issue by identifier
  for _, issue in ipairs(issues) do
    if issue.identifier == issue_id then
      return issue, nil
    end
  end
  
  return nil, string.format("Issue %s not found in current Linear issues", issue_id)
end

---Generate commit message with Linear issue reference
---@param message string Base commit message
---@return string enhanced_message
function M.enhance_commit_message(message)
  local issue_id = M.get_current_issue_id()
  if not issue_id then
    return message
  end
  
  -- Check if issue ID is already in message
  if message:match(issue_id) then
    return message
  end
  
  -- Prepend issue ID to message
  return string.format("%s: %s", issue_id, message)
end

return M
```

**Key Architectural Changes:**
- ✅ Uses centralized `git_state` and `linear_state`
- ✅ No separate HTTP client dependency
- ✅ Integrated with existing logging system
- ✅ Simplified without complex caching logic

## Updated Implementation Summary

### **Architectural Alignment Complete** ✅

The Linear implementation plan has been **fully updated** to align with the current refactored Nexus.nvim architecture:

1. **Provider System** ✅
   - Enhanced existing `linear.lua` provider
   - Integrated HTTP client using `vim.fn.system`  
   - Removed separate client/auth files

2. **State Management** ✅
   - Created `state/linear.lua` module
   - Uses centralized state manager
   - Integrated with cache_state system

3. **Action Pattern** ✅
   - Created `actions/linear/` directory structure
   - Actions inherit from BaseAction
   - Follow existing action registration pattern

4. **Component Architecture** ✅
   - Created `render/components/linear.lua`
   - Integrates with existing sections component
   - Uses existing icon and highlighting systems

5. **Configuration** ✅
   - Enhanced existing `linear` config section
   - Added comprehensive settings
   - Uses existing validation system

6. **Git Integration** ✅
   - Uses existing `git_state` module
   - Integrates with centralized state
   - Simplified pattern matching approach

### **Key Benefits of Updated Plan:**

- ✅ **Minimal Architecture Changes** - Leverages existing systems
- ✅ **Consistent Patterns** - Follows established conventions  
- ✅ **Reduced Complexity** - Fewer files and dependencies
- ✅ **Better Integration** - Works with current state management
- ✅ **Maintainable** - Aligns with existing codebase structure

The plan is now **ready for implementation** and will integrate seamlessly with the current refactored architecture!
