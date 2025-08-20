# Linear Integration Implementation Plan

## Executive Summary

This document provides a comprehensive implementation roadmap for integrating Linear API with Nexus.nvim, building upon the refactored architecture outlined in `PRE_LINEAR_REFACTORING_PLAN.md`. The integration will transform Nexus.nvim into a powerful developer dashboard that seamlessly connects git workflows with Linear project management.

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

**Provider Architecture:**
```
lua/nexus/providers/linear/
├── init.lua            -- Main Linear provider
├── client.lua          -- HTTP client and API wrapper
├── auth.lua            -- Authentication handling
├── cache.lua           -- Linear-specific caching
├── queries.lua         -- GraphQL query definitions
├── mutations.lua       -- GraphQL mutation definitions
├── parser.lua          -- Response parsing utilities
├── types.lua           -- Linear type definitions
└── health.lua          -- Linear-specific health checks
```

### Data Flow Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   User Action   │───▶│  Action Handler  │───▶│ Linear Provider │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │                        │
                                ▼                        ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │  State Manager   │    │  Linear API     │
                       └──────────────────┘    └─────────────────┘
                                │                        │
                                ▼                        ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │   UI Renderer    │    │  Cache Layer    │
                       └──────────────────┘    └─────────────────┘
```

## Implementation Phases

## Phase 1: Linear Provider Foundation (Week 1)

### 1.1 GraphQL Client Implementation

**File: `lua/nexus/providers/linear/client.lua`**
```lua
---@class LinearClient
---@field config LinearConfig
---@field http_client table
local M = {}

-- HTTP client configuration
local HTTP_TIMEOUT = 10000 -- 10 seconds
local API_ENDPOINT = "https://api.linear.app/graphql"

---Initialize Linear HTTP client
---@param config LinearConfig
---@return LinearClient
function M.new(config)
  local client = {
    config = config,
    http_client = require('plenary.curl'),
  }
  
  return setmetatable(client, { __index = M })
end

---Execute GraphQL query
---@param query string GraphQL query
---@param variables? table Query variables
---@return table? result, string? error
function M:query(query, variables)
  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = self.config.api_key,
  }
  
  local body = vim.json.encode({
    query = query,
    variables = variables or {},
  })
  
  local response = self.http_client.post(API_ENDPOINT, {
    headers = headers,
    body = body,
    timeout = HTTP_TIMEOUT,
  })
  
  if response.status ~= 200 then
    return nil, string.format("HTTP %d: %s", response.status, response.body)
  end
  
  local ok, decoded = pcall(vim.json.decode, response.body)
  if not ok then
    return nil, "Failed to parse JSON response"
  end
  
  if decoded.errors then
    return nil, "GraphQL errors: " .. vim.inspect(decoded.errors)
  end
  
  return decoded.data, nil
end
```

### 1.2 Authentication System

**File: `lua/nexus/providers/linear/auth.lua`**
```lua
local M = {}

-- OAuth 2.0 configuration
local OAUTH_CONFIG = {
  client_id = nil, -- Set by user configuration
  redirect_uri = "http://localhost:8080/auth/callback",
  scopes = "read,write,issues:create",
  authorize_url = "https://linear.app/oauth/authorize",
  token_url = "https://api.linear.app/oauth/token",
}

---Validate API key
---@param api_key string
---@return boolean valid, string? error
function M.validate_api_key(api_key)
  if not api_key or api_key == "" then
    return false, "API key is required"
  end
  
  local client = require('nexus.providers.linear.client').new({ api_key = api_key })
  local result, error = client:query([[
    query ValidateAuth {
      viewer {
        id
        name
        email
      }
    }
  ]])
  
  if error then
    return false, "Invalid API key: " .. error
  end
  
  return true, nil
end

---Get current user information
---@param api_key string
---@return table? user_info, string? error
function M.get_user_info(api_key)
  local client = require('nexus.providers.linear.client').new({ api_key = api_key })
  return client:query([[
    query GetUserInfo {
      viewer {
        id
        name
        email
        avatarUrl
      }
    }
  ]])
end
```

### 1.3 GraphQL Query Definitions

**File: `lua/nexus/providers/linear/queries.lua`**
```lua
local M = {}

-- Core issue fields fragment
M.ISSUE_FRAGMENT = [[
  fragment IssueFields on Issue {
    id
    identifier
    title
    description
    url
    priority
    estimate
    createdAt
    updatedAt
    assignee {
      id
      name
      avatarUrl
    }
    state {
      id
      name
      type
      color
    }
    team {
      id
      name
      key
    }
    labels {
      nodes {
        id
        name
        color
      }
    }
    cycle {
      id
      name
      number
    }
    project {
      id
      name
    }
  }
]]

-- Get assigned issues for current user
M.GET_ASSIGNED_ISSUES = M.ISSUE_FRAGMENT .. [[
  query GetAssignedIssues($first: Int, $filter: IssueFilter) {
    viewer {
      assignedIssues(first: $first, filter: $filter) {
        nodes {
          ...IssueFields
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
]]

-- Get team issues
M.GET_TEAM_ISSUES = M.ISSUE_FRAGMENT .. [[
  query GetTeamIssues($teamId: String!, $first: Int, $filter: IssueFilter) {
    team(id: $teamId) {
      issues(first: $first, filter: $filter) {
        nodes {
          ...IssueFields
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }
]]

-- Get issue by identifier (e.g., "LIN-123")
M.GET_ISSUE_BY_ID = M.ISSUE_FRAGMENT .. [[
  query GetIssueById($issueId: String!) {
    issue(id: $issueId) {
      ...IssueFields
      comments {
        nodes {
          id
          body
          createdAt
          user {
            name
            avatarUrl
          }
        }
      }
      attachments {
        nodes {
          id
          title
          url
        }
      }
    }
  }
]]

-- Get current user's teams
M.GET_TEAMS = [[
  query GetTeams {
    teams {
      nodes {
        id
        name
        key
        description
      }
    }
  }
]]

-- Get workflow states for a team
M.GET_WORKFLOW_STATES = [[
  query GetWorkflowStates($teamId: String!) {
    team(id: $teamId) {
      states {
        nodes {
          id
          name
          type
          color
          position
        }
      }
    }
  }
]]

return M
```

### 1.4 Issue Mutations

**File: `lua/nexus/providers/linear/mutations.lua`**
```lua
local M = {}

-- Create new issue
M.CREATE_ISSUE = [[
  mutation CreateIssue($input: IssueCreateInput!) {
    issueCreate(input: $input) {
      success
      issue {
        id
        identifier
        title
        url
      }
    }
  }
]]

-- Update issue
M.UPDATE_ISSUE = [[
  mutation UpdateIssue($id: String!, $input: IssueUpdateInput!) {
    issueUpdate(id: $id, input: $input) {
      success
      issue {
        id
        identifier
        title
        state {
          name
        }
      }
    }
  }
]]

-- Create comment
M.CREATE_COMMENT = [[
  mutation CreateComment($input: CommentCreateInput!) {
    commentCreate(input: $input) {
      success
      comment {
        id
        body
        createdAt
      }
    }
  }
]]

return M
```

## Phase 2: Core Linear Provider (Week 2)

### 2.1 Main Provider Implementation

**File: `lua/nexus/providers/linear/init.lua`**
```lua
---@class LinearProvider : Provider
---@field client LinearClient
---@field cache LinearCache
local M = {}

-- Inherit from base provider
local Provider = require('nexus.providers.base')
setmetatable(M, { __index = Provider })

---@type string
M.name = "linear"

---Initialize Linear provider
---@param config LinearConfig
---@return LinearProvider
function M:new(config)
  local provider = Provider.new(self, config)
  
  provider.client = require('nexus.providers.linear.client').new(config)
  provider.cache = require('nexus.providers.linear.cache').new(config)
  
  return provider
end

---Authenticate with Linear
---@return boolean success, string? error
function M:authenticate()
  local auth = require('nexus.providers.linear.auth')
  local valid, error = auth.validate_api_key(self.config.api_key)
  
  if not valid then
    return false, error
  end
  
  -- Cache user info for future use
  local user_info, user_error = auth.get_user_info(self.config.api_key)
  if user_info then
    self.cache:set('user_info', user_info.viewer, { ttl = 3600 })
  end
  
  return true, nil
end

---Get issues based on filters
---@param opts? IssueQueryOptions
---@return LinearIssue[]? issues, string? error
function M:get_issues(opts)
  opts = opts or {}
  local cache_key = self:_build_cache_key("issues", opts)
  
  -- Try cache first
  local cached = self.cache:get(cache_key)
  if cached and not opts.force_refresh then
    return cached, nil
  end
  
  local queries = require('nexus.providers.linear.queries')
  local variables = {
    first = opts.limit or 25,
    filter = self:_build_issue_filter(opts),
  }
  
  local query = opts.team_id and queries.GET_TEAM_ISSUES or queries.GET_ASSIGNED_ISSUES
  if opts.team_id then
    variables.teamId = opts.team_id
  end
  
  local result, error = self.client:query(query, variables)
  if error then
    return nil, error
  end
  
  local issues = opts.team_id and result.team.issues.nodes or result.viewer.assignedIssues.nodes
  
  -- Cache the results
  self.cache:set(cache_key, issues, { ttl = 300 }) -- 5 minute TTL
  
  return issues, nil
end

---Update issue state or properties
---@param issue_id string
---@param updates table
---@return boolean success, string? error
function M:update_issue(issue_id, updates)
  local mutations = require('nexus.providers.linear.mutations')
  
  local result, error = self.client:query(mutations.UPDATE_ISSUE, {
    id = issue_id,
    input = updates
  })
  
  if error then
    return false, error
  end
  
  if result.issueUpdate.success then
    -- Invalidate related caches
    self.cache:invalidate_pattern("issues:*")
    return true, nil
  else
    return false, "Update operation was not successful"
  end
end

---Create new issue
---@param issue_data IssueCreateData
---@return LinearIssue? issue, string? error
function M:create_issue(issue_data)
  local mutations = require('nexus.providers.linear.mutations')
  
  local result, error = self.client:query(mutations.CREATE_ISSUE, {
    input = issue_data
  })
  
  if error then
    return nil, error
  end
  
  if result.issueCreate.success then
    -- Invalidate caches
    self.cache:invalidate_pattern("issues:*")
    return result.issueCreate.issue, nil
  else
    return nil, "Issue creation was not successful"
  end
end

---Get current user info
---@return LinearUser? user, string? error
function M:get_user_info()
  local cached = self.cache:get('user_info')
  if cached then
    return cached, nil
  end
  
  local auth = require('nexus.providers.linear.auth')
  local result, error = auth.get_user_info(self.config.api_key)
  
  if error then
    return nil, error
  end
  
  local user = result.viewer
  self.cache:set('user_info', user, { ttl = 3600 })
  
  return user, nil
end

---Health check for Linear provider
---@return table health_status
function M:health_check()
  local status = {
    name = "Linear",
    status = "ok",
    checks = {}
  }
  
  -- Check API key validity
  local auth_valid, auth_error = self:authenticate()
  table.insert(status.checks, {
    name = "Authentication",
    status = auth_valid and "ok" or "error",
    message = auth_error
  })
  
  -- Check API connectivity
  local user, user_error = self:get_user_info()
  table.insert(status.checks, {
    name = "API Connectivity",
    status = user and "ok" or "error",
    message = user_error
  })
  
  -- Check team access
  local teams, teams_error = self:get_teams()
  table.insert(status.checks, {
    name = "Team Access",
    status = teams and #teams > 0 and "ok" or "warning",
    message = teams_error or (teams and #teams == 0 and "No teams accessible")
  })
  
  -- Overall status
  local has_error = false
  for _, check in ipairs(status.checks) do
    if check.status == "error" then
      has_error = true
      break
    end
  end
  
  status.status = has_error and "error" or "ok"
  
  return status
end

-- Private helper methods
function M:_build_cache_key(prefix, opts)
  local key_parts = { prefix }
  if opts.team_id then
    table.insert(key_parts, "team:" .. opts.team_id)
  end
  if opts.assignee then
    table.insert(key_parts, "assignee:" .. opts.assignee)
  end
  if opts.state then
    table.insert(key_parts, "state:" .. opts.state)
  end
  return table.concat(key_parts, ":")
end

function M:_build_issue_filter(opts)
  local filter = {}
  
  if opts.state then
    filter.state = { id = { eq = opts.state } }
  end
  
  if opts.assignee then
    filter.assignee = { id = { eq = opts.assignee } }
  end
  
  if opts.team then
    filter.team = { id = { eq = opts.team } }
  end
  
  -- Exclude archived issues by default
  if not opts.include_archived then
    filter.state = filter.state or {}
    filter.state.type = { neq = "completed" }
  end
  
  return filter
end

return M
```

## Phase 3: UI Integration (Week 3)

### 3.1 Linear Dashboard Component

**File: `lua/nexus/render/components/linear.lua`**
```lua
---@class LinearComponent
local M = {}

local icons = require('nexus.utils.icons')
local colors = require('nexus.utils.colors')

---Render Linear issues section
---@param config NexusConfig
---@param state NexusState
---@return string[] lines
---@return table ranges
function M.render(config, state)
  if not config.integrations.linear.enabled then
    return {}, {}
  end
  
  local lines = {}
  local ranges = {}
  
  -- Section header
  local header = string.format("%s Linear Issues", icons.linear)
  table.insert(lines, header)
  table.insert(ranges, {
    type = "header",
    line = #lines,
    col_start = 0,
    col_end = #header,
  })
  
  -- Loading state
  if state.linear.loading then
    table.insert(lines, "  " .. icons.spinner .. " Loading issues...")
    return lines, ranges
  end
  
  -- Error state
  if state.linear.error then
    local error_line = "  " .. icons.error .. " " .. state.linear.error
    table.insert(lines, error_line)
    table.insert(ranges, {
      type = "error",
      line = #lines,
      col_start = 0,
      col_end = #error_line,
    })
    return lines, ranges
  end
  
  -- Issues list
  local issues = state.linear.issues or {}
  
  if #issues == 0 then
    table.insert(lines, "  " .. icons.info .. " No issues found")
    return lines, ranges
  end
  
  -- Current cycle/sprint info
  if state.linear.current_cycle then
    local cycle = state.linear.current_cycle
    local cycle_line = string.format("  %s %s (%s)", 
      icons.cycle, 
      cycle.name, 
      M.format_cycle_status(cycle)
    )
    table.insert(lines, cycle_line)
    table.insert(lines, "")
  end
  
  -- Render each issue
  for i, issue in ipairs(issues) do
    if i > config.integrations.linear.max_issues then
      break
    end
    
    local issue_lines, issue_ranges = M.render_issue(issue, #lines + 1)
    for _, line in ipairs(issue_lines) do
      table.insert(lines, line)
    end
    for _, range in ipairs(issue_ranges) do
      table.insert(ranges, range)
    end
  end
  
  -- Show more indicator
  if #issues > config.integrations.linear.max_issues then
    local more_line = string.format("  ... and %d more", 
      #issues - config.integrations.linear.max_issues)
    table.insert(lines, more_line)
  end
  
  return lines, ranges
end

---Render individual issue
---@param issue LinearIssue
---@param start_line number
---@return string[] lines
---@return table[] ranges
function M.render_issue(issue, start_line)
  local lines = {}
  local ranges = {}
  
  -- Priority icon
  local priority_icon = M.get_priority_icon(issue.priority)
  local state_icon = M.get_state_icon(issue.state)
  
  -- Build issue line
  local issue_parts = {
    "  " .. state_icon,
    string.format("[%s]", string.upper(issue.state.name)),
    string.format("%s:", issue.identifier),
    issue.title,
  }
  
  -- Add priority if high/urgent
  if issue.priority >= 2 then -- High or Urgent
    table.insert(issue_parts, 2, priority_icon)
  end
  
  -- Add estimate if available
  if issue.estimate then
    table.insert(issue_parts, string.format("(%dp)", issue.estimate))
  end
  
  local issue_line = table.concat(issue_parts, " ")
  table.insert(lines, issue_line)
  
  -- Add range for the entire issue
  table.insert(ranges, {
    type = "issue",
    line = start_line,
    col_start = 0,
    col_end = #issue_line,
    data = issue,
  })
  
  -- Add assignee info if configured
  local config = require('nexus.state').get_config()
  if config.integrations.linear.show_assignee and issue.assignee then
    local assignee_line = string.format("    assigned to %s", issue.assignee.name)
    table.insert(lines, assignee_line)
  end
  
  return lines, ranges
end

---Get priority icon
---@param priority number
---@return string icon
function M.get_priority_icon(priority)
  if priority == 0 then return icons.priority.none end
  if priority == 1 then return icons.priority.low end
  if priority == 2 then return icons.priority.medium end
  if priority == 3 then return icons.priority.high end
  if priority == 4 then return icons.priority.urgent end
  return icons.priority.none
end

---Get state icon
---@param state LinearState
---@return string icon
function M.get_state_icon(state)
  if state.type == "backlog" then return icons.state.backlog end
  if state.type == "unstarted" then return icons.state.todo end
  if state.type == "started" then return icons.state.in_progress end
  if state.type == "completed" then return icons.state.done end
  if state.type == "canceled" then return icons.state.canceled end
  return icons.state.unknown
end

---Format cycle status
---@param cycle LinearCycle
---@return string status
function M.format_cycle_status(cycle)
  if not cycle.endsAt then
    return "ongoing"
  end
  
  local ends_at = vim.fn.strftime("%Y-%m-%d", cycle.endsAt)
  local days_left = math.ceil((cycle.endsAt - os.time()) / 86400)
  
  if days_left < 0 then
    return "ended"
  elseif days_left == 0 then
    return "ends today"
  elseif days_left == 1 then
    return "1 day left"
  else
    return string.format("%d days left", days_left)
  end
end

return M
```

### 3.2 Linear Actions Implementation

**File: `lua/nexus/actions/linear.lua`**
```lua
---@class LinearActions
local M = {}

local linear = require('nexus.providers').get('linear')
local state = require('nexus.state')

---Open issue in browser
---@param issue LinearIssue
function M.open_issue(issue)
  local url = issue.url
  if not url then
    vim.notify("Issue URL not available", vim.log.levels.WARN)
    return
  end
  
  -- Open URL based on platform
  local cmd
  if vim.fn.has('mac') == 1 then
    cmd = 'open'
  elseif vim.fn.has('unix') == 1 then
    cmd = 'xdg-open'
  elseif vim.fn.has('win32') == 1 then
    cmd = 'start'
  else
    vim.notify("Unsupported platform for opening URLs", vim.log.levels.ERROR)
    return
  end
  
  vim.fn.system(string.format('%s "%s"', cmd, url))
  vim.notify(string.format("Opened %s in browser", issue.identifier), vim.log.levels.INFO)
end

---Update issue state
---@param issue LinearIssue
---@param new_state_id string
function M.update_issue_state(issue, new_state_id)
  if not linear then
    vim.notify("Linear provider not available", vim.log.levels.ERROR)
    return
  end
  
  local success, error = linear:update_issue(issue.id, {
    stateId = new_state_id
  })
  
  if success then
    vim.notify(string.format("Updated %s state", issue.identifier), vim.log.levels.INFO)
    -- Refresh Linear data
    M.refresh_issues()
  else
    vim.notify(string.format("Failed to update %s: %s", issue.identifier, error), vim.log.levels.ERROR)
  end
end

---Mark issue as in progress
---@param issue LinearIssue
function M.start_issue(issue)
  -- Find "In Progress" state for the team
  local in_progress_state = M.find_state_by_type(issue.team.id, "started")
  if in_progress_state then
    M.update_issue_state(issue, in_progress_state.id)
  else
    vim.notify("Could not find 'In Progress' state for this team", vim.log.levels.WARN)
  end
end

---Mark issue as done
---@param issue LinearIssue
function M.complete_issue(issue)
  local done_state = M.find_state_by_type(issue.team.id, "completed")
  if done_state then
    M.update_issue_state(issue, done_state.id)
  else
    vim.notify("Could not find 'Done' state for this team", vim.log.levels.WARN)
  end
end

---Create git branch from issue
---@param issue LinearIssue
function M.create_branch_from_issue(issue)
  -- Generate branch name from issue
  local branch_name = M.generate_branch_name(issue)
  
  -- Check if branch already exists
  local branch_exists = vim.fn.system('git rev-parse --verify ' .. branch_name .. ' 2>/dev/null')
  if vim.v.shell_error == 0 then
    vim.notify(string.format("Branch %s already exists", branch_name), vim.log.levels.WARN)
    return
  end
  
  -- Create and checkout branch
  local result = vim.fn.system('git checkout -b ' .. branch_name)
  if vim.v.shell_error == 0 then
    vim.notify(string.format("Created and checked out branch: %s", branch_name), vim.log.levels.INFO)
  else
    vim.notify(string.format("Failed to create branch: %s", result), vim.log.levels.ERROR)
  end
end

---Create new Linear issue
---@param opts? IssueCreationOptions
function M.create_issue(opts)
  opts = opts or {}
  
  -- Get user input
  local title = opts.title or vim.fn.input("Issue title: ")
  if title == "" then
    return
  end
  
  local description = opts.description or vim.fn.input("Description (optional): ")
  
  -- Get team ID (use configured team or prompt)
  local config = state.get_config()
  local team_id = opts.team_id or config.integrations.linear.default_team_id
  
  if not team_id then
    vim.notify("No team configured for issue creation", vim.log.levels.ERROR)
    return
  end
  
  -- Create issue
  local issue_data = {
    title = title,
    teamId = team_id,
  }
  
  if description ~= "" then
    issue_data.description = description
  end
  
  if opts.priority then
    issue_data.priority = opts.priority
  end
  
  if not linear then
    vim.notify("Linear provider not available", vim.log.levels.ERROR)
    return
  end
  
  local issue, error = linear:create_issue(issue_data)
  if issue then
    vim.notify(string.format("Created issue: %s", issue.identifier), vim.log.levels.INFO)
    -- Refresh issues
    M.refresh_issues()
    -- Optionally open in browser
    if opts.open_in_browser then
      M.open_issue(issue)
    end
  else
    vim.notify(string.format("Failed to create issue: %s", error), vim.log.levels.ERROR)
  end
end

---Refresh Linear issues
function M.refresh_issues()
  local linear_state = state.get_linear_state()
  linear_state.loading = true
  
  -- Update UI
  require('nexus.render').refresh()
  
  -- Fetch fresh data
  vim.defer_fn(function()
    if not linear then
      linear_state.loading = false
      linear_state.error = "Linear provider not available"
      require('nexus.render').refresh()
      return
    end
    
    local config = state.get_config()
    local issues, error = linear:get_issues({
      force_refresh = true,
      limit = config.integrations.linear.max_issues * 2, -- Fetch more than we show
    })
    
    linear_state.loading = false
    
    if issues then
      linear_state.issues = issues
      linear_state.error = nil
      linear_state.last_updated = os.time()
    else
      linear_state.error = error
    end
    
    require('nexus.render').refresh()
  end, 0)
end

-- Helper functions
function M.find_state_by_type(team_id, state_type)
  -- This would cache and lookup team states
  -- Implementation depends on state management system
  local team_states = state.get_team_states(team_id)
  if not team_states then
    return nil
  end
  
  for _, state_info in ipairs(team_states) do
    if state_info.type == state_type then
      return state_info
    end
  end
  
  return nil
end

function M.generate_branch_name(issue)
  -- Generate branch name from issue
  local prefix = "feat"
  local identifier = issue.identifier:lower()
  local title_slug = issue.title:lower()
    :gsub("[^%w%s]", "") -- Remove special characters
    :gsub("%s+", "-")    -- Replace spaces with dashes
    :sub(1, 40)          -- Limit length
  
  return string.format("%s/%s-%s", prefix, identifier, title_slug)
end

return M
```

## Phase 4: Git-Linear Integration (Week 4)

### 4.1 Branch-Issue Detection

**File: `lua/nexus/git/linear_integration.lua`**
```lua
---@class GitLinearIntegration
local M = {}

local git = require('nexus.git')
local linear = require('nexus.providers').get('linear')

-- Pattern matching for Linear issue IDs in branch names
local ISSUE_PATTERNS = {
  "^feat/([A-Z]+%-[0-9]+)",     -- feat/LIN-123-description
  "^fix/([A-Z]+%-[0-9]+)",      -- fix/LIN-123-bugfix
  "^([A-Z]+%-[0-9]+)",          -- LIN-123-feature
  "/([A-Z]+%-[0-9]+)",          -- any/path/LIN-123-desc
}

---Extract Linear issue ID from current branch
---@return string? issue_id
function M.get_current_issue_id()
  local branch = git.get_current_branch()
  if not branch then
    return nil
  end
  
  for _, pattern in ipairs(ISSUE_PATTERNS) do
    local issue_id = branch:match(pattern)
    if issue_id then
      return issue_id
    end
  end
  
  return nil
end

---Get Linear issue for current branch
---@return LinearIssue? issue, string? error
function M.get_current_issue()
  local issue_id = M.get_current_issue_id()
  if not issue_id then
    return nil, "No Linear issue ID found in current branch"
  end
  
  if not linear then
    return nil, "Linear provider not available"
  end
  
  return linear:get_issue(issue_id)
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

---Validate commit against Linear issue
---@param message string Commit message
---@return boolean valid, string? warning
function M.validate_commit(message)
  local issue = M.get_current_issue()
  if not issue then
    return true, "No Linear issue associated with current branch"
  end
  
  -- Check if issue is in appropriate state
  if issue.state.type == "completed" then
    return false, string.format("Issue %s is already completed", issue.identifier)
  end
  
  if issue.state.type == "canceled" then
    return false, string.format("Issue %s is canceled", issue.identifier)
  end
  
  -- Suggest moving to "In Progress" if it's in backlog
  if issue.state.type == "backlog" or issue.state.type == "unstarted" then
    return true, string.format("Consider moving %s to 'In Progress'", issue.identifier)
  end
  
  return true, nil
end

---Auto-update issue state based on commit
---@param message string Commit message
function M.handle_commit(message)
  local issue = M.get_current_issue()
  if not issue then
    return
  end
  
  -- Auto-move to "In Progress" if not already started
  if issue.state.type == "backlog" or issue.state.type == "unstarted" then
    local actions = require('nexus.actions.linear')
    actions.start_issue(issue)
  end
  
  -- Look for completion keywords in commit message
  local completion_keywords = {
    "fix", "fixes", "fixed",
    "close", "closes", "closed",
    "resolve", "resolves", "resolved",
    "complete", "completes", "completed"
  }
  
  for _, keyword in ipairs(completion_keywords) do
    if message:lower():match("%f[%a]" .. keyword .. "%f[%A]") then
      local actions = require('nexus.actions.linear')
      actions.complete_issue(issue)
      break
    end
  end
end

---Show Linear context in git status
---@return string[] context_lines
function M.get_git_context()
  local lines = {}
  local issue = M.get_current_issue()
  
  if not issue then
    local issue_id = M.get_current_issue_id()
    if issue_id then
      table.insert(lines, string.format("🔗 Branch linked to %s (not found)", issue_id))
    end
    return lines
  end
  
  -- Show issue context
  local status_icon = require('nexus.render.components.linear').get_state_icon(issue.state)
  table.insert(lines, string.format("🔗 Working on: %s %s", issue.identifier, status_icon))
  table.insert(lines, string.format("   %s", issue.title))
  
  if issue.assignee and issue.assignee.name then
    table.insert(lines, string.format("   Assigned to: %s", issue.assignee.name))
  end
  
  if issue.priority > 1 then
    local priority_names = { [2] = "Medium", [3] = "High", [4] = "Urgent" }
    table.insert(lines, string.format("   Priority: %s", priority_names[issue.priority]))
  end
  
  return lines
end

return M
```

### 4.2 Configuration Schema

**File: `lua/nexus/config/linear.lua`**
```lua
---@class LinearConfig
---@field enabled boolean Whether Linear integration is enabled
---@field api_key string Linear API key
---@field default_team_id? string Default team for new issues
---@field max_issues number Maximum issues to show in dashboard
---@field show_assignee boolean Show assignee information
---@field show_cycle boolean Show cycle/sprint information
---@field auto_refresh number Auto-refresh interval in seconds (0 to disable)
---@field branch_integration LinearBranchConfig Branch integration settings
---@field commit_integration LinearCommitConfig Commit integration settings

---@class LinearBranchConfig
---@field auto_create_from_issue boolean Auto-create branches from issues
---@field branch_naming_pattern string Branch naming pattern
---@field require_issue_link boolean Require Linear issue link in branches

---@class LinearCommitConfig  
---@field auto_add_issue_id boolean Auto-add issue ID to commit messages
---@field validate_against_issue boolean Validate commits against Linear issues
---@field auto_update_status boolean Auto-update issue status on commits
---@field completion_keywords string[] Keywords that trigger issue completion

local M = {}

---@type LinearConfig
M.defaults = {
  enabled = false,
  api_key = vim.env.LINEAR_API_KEY or "",
  default_team_id = nil,
  max_issues = 10,
  show_assignee = true,
  show_cycle = true,
  auto_refresh = 300, -- 5 minutes
  
  branch_integration = {
    auto_create_from_issue = false,
    branch_naming_pattern = "feat/%s-%s", -- identifier-title-slug
    require_issue_link = false,
  },
  
  commit_integration = {
    auto_add_issue_id = true,
    validate_against_issue = true,
    auto_update_status = true,
    completion_keywords = {
      "fix", "fixes", "fixed",
      "close", "closes", "closed", 
      "resolve", "resolves", "resolved",
      "complete", "completes", "completed"
    },
  },
}

---Validate Linear configuration
---@param config LinearConfig
---@return boolean valid, string[] errors
function M.validate(config)
  local errors = {}
  
  if not config.enabled then
    return true, {}
  end
  
  -- API key validation
  if not config.api_key or config.api_key == "" then
    table.insert(errors, "Linear API key is required when enabled")
  end
  
  -- Numeric validations
  if config.max_issues < 1 or config.max_issues > 100 then
    table.insert(errors, "max_issues must be between 1 and 100")
  end
  
  if config.auto_refresh < 0 then
    table.insert(errors, "auto_refresh must be >= 0")
  end
  
  -- Branch naming pattern validation
  if not config.branch_integration.branch_naming_pattern:match("%%s") then
    table.insert(errors, "branch_naming_pattern must contain %s placeholder")
  end
  
  return #errors == 0, errors
end

return M
```

## Phase 5: Testing & Quality Assurance (Week 5)

### 5.1 Linear Provider Tests

**File: `tests/unit/providers/linear_spec.lua`**
```lua
local mock = require('tests.mocks.linear')
local LinearProvider = require('nexus.providers.linear')

describe("Linear Provider", function()
  local provider
  
  before_each(function()
    provider = LinearProvider:new({
      api_key = "test_api_key",
      default_team_id = "team123"
    })
    mock.setup()
  end)
  
  after_each(function()
    mock.teardown()
  end)
  
  describe("authentication", function()
    it("validates API key successfully", function()
      mock.mock_query_response({
        viewer = {
          id = "user123",
          name = "Test User",
          email = "test@example.com"
        }
      })
      
      local success, error = provider:authenticate()
      assert.is_true(success)
      assert.is_nil(error)
    end)
    
    it("handles invalid API key", function()
      mock.mock_query_error("Invalid API key")
      
      local success, error = provider:authenticate()
      assert.is_false(success)
      assert.is_not_nil(error)
      assert.matches("Invalid API key", error)
    end)
  end)
  
  describe("get_issues", function()
    it("returns assigned issues", function()
      mock.mock_query_response({
        viewer = {
          assignedIssues = {
            nodes = {
              {
                id = "issue1",
                identifier = "TEST-1",
                title = "Test Issue",
                state = { name = "In Progress", type = "started" }
              }
            }
          }
        }
      })
      
      local issues, error = provider:get_issues()
      assert.is_nil(error)
      assert.equals(1, #issues)
      assert.equals("TEST-1", issues[1].identifier)
    end)
    
    it("handles API errors gracefully", function()
      mock.mock_query_error("Network error")
      
      local issues, error = provider:get_issues()
      assert.is_nil(issues)
      assert.matches("Network error", error)
    end)
  end)
  
  describe("update_issue", function()
    it("updates issue state", function()
      mock.mock_query_response({
        issueUpdate = {
          success = true,
          issue = { id = "issue1", identifier = "TEST-1" }
        }
      })
      
      local success, error = provider:update_issue("issue1", { stateId = "state123" })
      assert.is_true(success)
      assert.is_nil(error)
    end)
  end)
end)
```

### 5.2 Integration Tests

**File: `tests/integration/linear_integration_spec.lua`**
```lua
local GitLinearIntegration = require('nexus.git.linear_integration')
local mock_git = require('tests.mocks.git')
local mock_linear = require('tests.mocks.linear')

describe("Git-Linear Integration", function()
  before_each(function()
    mock_git.setup()
    mock_linear.setup()
  end)
  
  after_each(function()
    mock_git.teardown()
    mock_linear.teardown()
  end)
  
  describe("branch issue detection", function()
    it("extracts issue ID from feature branch", function()
      mock_git.mock_current_branch("feat/LIN-123-new-feature")
      
      local issue_id = GitLinearIntegration.get_current_issue_id()
      assert.equals("LIN-123", issue_id)
    end)
    
    it("handles branches without issue IDs", function()
      mock_git.mock_current_branch("main")
      
      local issue_id = GitLinearIntegration.get_current_issue_id()
      assert.is_nil(issue_id)
    end)
  end)
  
  describe("commit message enhancement", function()
    it("adds issue ID to commit message", function()
      mock_git.mock_current_branch("feat/LIN-123-feature")
      
      local enhanced = GitLinearIntegration.enhance_commit_message("Add new feature")
      assert.equals("LIN-123: Add new feature", enhanced)
    end)
    
    it("doesn't duplicate issue ID", function()
      mock_git.mock_current_branch("feat/LIN-123-feature")
      
      local enhanced = GitLinearIntegration.enhance_commit_message("LIN-123: Add feature")
      assert.equals("LIN-123: Add feature", enhanced)
    end)
  end)
end)
```

## Phase 6: Documentation & Polish (Week 6)

### 6.1 User Documentation

**File: `docs/LINEAR_SETUP.md`**
```markdown
# Linear Integration Setup Guide

## Prerequisites

1. **Linear Account**: You need access to a Linear workspace
2. **API Access**: Personal API key or OAuth2 setup
3. **Neovim**: Version 0.9.0 or later
4. **Dependencies**: `plenary.nvim` for HTTP requests

## Quick Setup

### 1. Get Linear API Key

Visit [Linear Settings > Security & Access](https://linear.app/settings/account/security) and create a personal API key.

### 2. Configure Nexus.nvim

```lua
require('nexus').setup({
  integrations = {
    linear = {
      enabled = true,
      api_key = "lin_api_***", -- Your Linear API key
      max_issues = 10,
      show_assignee = true,
      show_cycle = true,
      auto_refresh = 300, -- 5 minutes
    }
  }
})
```

### 3. Environment Variable (Recommended)

Set your API key as an environment variable:

```bash
export LINEAR_API_KEY="lin_api_***"
```

Then use in configuration:
```lua
api_key = vim.env.LINEAR_API_KEY,
```

## Advanced Configuration

### Branch Integration

Enable automatic branch creation from Linear issues:

```lua
integrations = {
  linear = {
    -- ... other config
    branch_integration = {
      auto_create_from_issue = true,
      branch_naming_pattern = "feat/%s-%s", -- identifier-title
      require_issue_link = false,
    }
  }
}
```

### Commit Integration

Automatically link commits to Linear issues:

```lua
integrations = {
  linear = {
    -- ... other config  
    commit_integration = {
      auto_add_issue_id = true,
      validate_against_issue = true,
      auto_update_status = true,
      completion_keywords = {"fix", "close", "resolve"}
    }
  }
}
```

## Usage

### Dashboard Interactions

- `<Enter>` on issue: Open in browser
- `i` on issue: Mark as "In Progress"  
- `d` on issue: Mark as "Done"
- `b` on issue: Create git branch
- `c` on issue: Create commit referencing issue
- `r`: Refresh Linear data

### Commands

- `:LinearRefresh` - Refresh issue data
- `:LinearCreate` - Create new issue
- `:LinearBranch` - Create branch from current issue

## Troubleshooting

### Authentication Issues

Check your API key:
```
:checkhealth nexus
```

### Network Issues

Linear integration will gracefully degrade if the API is unavailable, showing cached data when possible.

### Performance

Linear data is cached for 5 minutes by default. Adjust `auto_refresh` to balance freshness vs. performance.
```

## Expected Outcomes

### User Experience
- **Seamless Workflow**: Developers never leave Neovim to manage Linear issues
- **Automatic Linking**: Git branches and commits automatically link to Linear issues
- **Context Awareness**: Always know what you're supposed to be working on
- **Offline Resilience**: Cached data available when Linear API is unavailable

### Performance Targets
- **Initial Load**: < 2 seconds for dashboard with Linear data
- **Cached Load**: < 200ms for subsequent dashboard opens
- **Issue Operations**: < 500ms for cached issue actions
- **Memory Usage**: < 5MB additional memory for Linear integration

### Integration Quality
- **Error Handling**: Graceful degradation with helpful error messages
- **Caching**: Intelligent caching reduces API calls by 80%
- **Async Operations**: All Linear API calls are non-blocking
- **Type Safety**: Full type annotations for all Linear data structures

This comprehensive implementation plan establishes Nexus.nvim as a premier developer dashboard with deep Linear integration, following Lua best practices and Neovim conventions while maintaining excellent performance and user experience.