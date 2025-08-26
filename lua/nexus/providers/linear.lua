local Provider = require('nexus.providers.base')

---@class LinearProvider : Provider
local LinearProvider = setmetatable({}, { __index = Provider })

-- Linear provider constructor
---@param name string Provider identifier
---@param config table Provider configuration
---@return LinearProvider
function LinearProvider:new(name, config)
  local instance = Provider:new(name or "linear", config or {})
  setmetatable(instance, { __index = self })
  
  -- Linear-specific configuration
  instance.api_url = config.api_url or "https://api.linear.app/graphql"
  instance.api_key = config.api_key or os.getenv("LINEAR_API_KEY")
  instance.team_id = config.team_id
  instance.project_id = config.project_id
  instance.workspace_id = config.workspace_id
  
  -- Linear-specific cache
  instance._teams_cache = {}
  instance._projects_cache = {}
  
  return instance
end

-- Get the current git repository name for project filtering
function LinearProvider:_get_repository_name()
  local handle = io.popen('git rev-parse --show-toplevel 2>/dev/null')
  if not handle then
    return nil
  end
  
  local result = handle:read('*a')
  handle:close()
  
  if result and result ~= '' then
    -- Extract repository name from path (e.g., /path/to/nexus.nvim -> nexus.nvim)
    local repo_name = result:gsub('\n$', ''):match('([^/]+)$')
    return repo_name
  end
  
  return nil
end

-- Authentication implementation
function LinearProvider:authenticate()
  if not self.api_key then
    self:set_error("No API key provided. Set LINEAR_API_KEY environment variable or provide in config.")
    return false, "No API key provided"
  end
  
  -- Test authentication with a simple query
  local success, result = self:_make_request({
    query = [[
      query {
        viewer {
          id
          name
          email
        }
      }
    ]]
  })
  
  if success and result and result.data and result.data.viewer then
    self._user_info = result.data.viewer
    return true
  else
    local error_msg = result and result.errors and result.errors[1] and result.errors[1].message or "Authentication failed"
    self:set_error("Linear authentication failed: " .. error_msg)
    return false, error_msg
  end
end

function LinearProvider:is_authenticated()
  return self._user_info ~= nil
end

-- Issue management implementation
function LinearProvider:get_issues(opts)
  if not self:is_authenticated() then
    return nil, "Not authenticated"
  end
  
  opts = opts or {}
  local limit = opts.limit or 50
  local team_filter = self.team_id and ('team: { id: { eq: "' .. self.team_id .. '" } }') or ""
  
  -- Add project filter - prioritize explicit project_id over repository name
  local project_filter = ""
  if self.project_id then
    -- Use explicit project ID if set
    project_filter = string.format('project: { id: { eq: "%s" } }', self.project_id)
    if team_filter ~= "" then
      project_filter = ", " .. project_filter
    end
    
    -- Add debug logging
    local logger = require('nexus.logger')
    logger.debug('LINEAR', 'Filtering issues by explicit project ID', { 
      project_id = self.project_id
    })
  elseif opts.filter_by_repository ~= false then  -- Default to true, allow opt-out
    local repo_name = self:_get_repository_name()
    if repo_name then
      -- Extract project name from repository name (remove .nvim suffix if present)
      local project_name = repo_name:gsub('%.nvim$', '')
      project_filter = string.format('project: { name: { containsIgnoreCase: "%s" } }', project_name)
      if team_filter ~= "" then
        project_filter = ", " .. project_filter
      end
      
      -- Add debug logging
      local logger = require('nexus.logger')
      logger.debug('LINEAR', 'Filtering issues by repository project', { 
        repository = repo_name, 
        project_filter = project_name 
      })
    end
  end
  
  local filter_string = team_filter .. project_filter
  
  local query = string.format([[
    query {
      issues(first: %d, filter: { %s }, orderBy: updatedAt) {
        nodes {
          id
          identifier
          title
          description
          state {
            id
            name
            type
          }
          priority
          estimate
          assignee {
            id
            name
            email
          }
          team {
            id
            name
            key
          }
          project {
            id
            name
          }
          cycle {
            id
            name
            number
          }
          labels {
            nodes {
              id
              name
              color
            }
          }
          createdAt
          updatedAt
          url
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  ]], limit, filter_string)
  
  local success, result = self:_make_request({ query = query })
  
  if success and result and result.data and result.data.issues then
    local issues = result.data.issues.nodes
    
    -- Apply status-based filtering and ordering if configured
    local config = require('nexus.config').get()
    if config.linear and config.linear.issue_order then
      issues = self:_filter_and_order_issues(issues, config.linear.issue_order)
    end
    
    return issues
  else
    local error_msg = result and result.errors and result.errors[1] and result.errors[1].message or "Failed to fetch issues"
    return nil, error_msg
  end
end


-- Get available states for the team
function LinearProvider:get_team_states(team_id)
  if not self:is_authenticated() then
    return nil, "Not authenticated"
  end
  
  local query = string.format([[
    query {
      team(id: "%s") {
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
  ]], team_id or self.team_id or "")
  
  -- If no team_id specified, get all workspace states
  if not team_id and not self.team_id then
    query = [[
      query {
        workflowStates(first: 50) {
          nodes {
            id
            name
            type
            color
            position
          }
        }
      }
    ]]
  end
  
  local success, result = self:_make_request({ query = query })
  
  if success and result and result.data then
    if result.data.team and result.data.team.states then
      return result.data.team.states.nodes
    elseif result.data.workflowStates then
      return result.data.workflowStates.nodes
    end
  else
    local error_msg = result and result.errors and result.errors[1] and result.errors[1].message or "Failed to fetch states"
    return nil, error_msg
  end
  
  return {}
end

function LinearProvider:get_issue(id)
  if not self:is_authenticated() then
    return nil, "Not authenticated"
  end
  
  local query = string.format([[
    query {
      issue(id: "%s") {
        id
        identifier
        title
        description
        state {
          id
          name
          type
        }
        priority
        assignee {
          id
          name
          email
        }
        team {
          id
          name
          key
        }
        project {
          id
          name
        }
        createdAt
        updatedAt
        url
      }
    }
  ]], id)
  
  local success, result = self:_make_request({ query = query })
  
  if success and result and result.data and result.data.issue then
    return result.data.issue
  else
    local error_msg = result and result.errors and result.errors[1] and result.errors[1].message or "Failed to fetch issue"
    return nil, error_msg
  end
end

function LinearProvider:create_issue(data)
  if not self:is_authenticated() then
    return nil, "Not authenticated"
  end
  
  -- Validate required fields
  if not data.title then
    return nil, "Issue title is required"
  end
  
  if not data.team_id and not self.team_id then
    return nil, "Team ID is required"
  end
  
  local team_id = data.team_id or self.team_id
  local description = data.description or ""
  local priority = data.priority or 0
  local project_id = data.project_id
  
  -- Build mutation with optional project assignment
  local mutation = [[
    mutation CreateIssue($title: String!, $description: String!, $teamId: String!, $priority: Int!, $projectId: String) {
      issueCreate(input: {
        title: $title
        description: $description
        teamId: $teamId
        priority: $priority
        projectId: $projectId
      }) {
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
  
  local variables = {
    title = data.title,
    description = description,
    teamId = team_id,
    priority = priority,
    projectId = project_id
  }
  
  local success, result = self:_make_request({ query = mutation, variables = variables })
  
  if success and result and result.data and result.data.issueCreate and result.data.issueCreate.success then
    return result.data.issueCreate.issue
  else
    local error_msg = result and result.errors and result.errors[1] and result.errors[1].message or "Failed to create issue"
    return nil, error_msg
  end
end

function LinearProvider:update_issue(id, data)
  if not self:is_authenticated() then
    return nil, "Not authenticated"
  end
  
  -- Build input object with only provided fields
  local input_fields = {}
  if data.title then
    input_fields.title = data.title
  end
  if data.description then
    input_fields.description = data.description
  end
  if data.priority then
    input_fields.priority = data.priority
  end
  if data.state_id then
    input_fields.stateId = data.state_id
  end
  
  if vim.tbl_isempty(input_fields) then
    return nil, "No update fields provided"
  end
  
  local mutation = [[
    mutation UpdateIssue($id: String!, $input: IssueUpdateInput!) {
      issueUpdate(id: $id, input: $input) {
        success
        issue {
          id
          identifier
          title
          url
          state {
            id
            name
            color
            type
          }
        }
      }
    }
  ]]
  
  local variables = {
    id = id,
    input = input_fields
  }
  
  local success, result = self:_make_request({ query = mutation, variables = variables })
  
  if success and result and result.data and result.data.issueUpdate and result.data.issueUpdate.success then
    return result.data.issueUpdate.issue
  else
    local error_msg = result and result.errors and result.errors[1] and result.errors[1].message or "Failed to update issue"
    return nil, error_msg
  end
end

-- User information implementation
function LinearProvider:get_user_info()
  if self._user_info then
    return self._user_info
  end
  
  if not self:is_authenticated() then
    return nil, "Not authenticated"
  end
  
  return self._user_info
end

-- Health check implementation
function LinearProvider:health_check()
  if not self.api_key then
    return false, "No API key configured"
  end
  
  -- Try to authenticate
  local success, error_msg = self:authenticate()
  if success then
    return true, "Linear provider healthy"
  else
    return false, "Health check failed: " .. (error_msg or "Unknown error")
  end
end

-- Filter and order issues by status
---@param issues table List of Linear issues
---@param issue_order table Ordered list of status names to include
---@return table filtered_issues
function LinearProvider:_filter_and_order_issues(issues, issue_order)
  local logger = require('nexus.logger')
  
  if not issues or #issues == 0 then
    return issues
  end
  
  logger.debug('LINEAR', 'Filtering and ordering issues', { 
    total_issues = #issues,
    issue_order = issue_order 
  })
  
  -- Group issues by status name
  local issues_by_status = {}
  local unmatched_issues = {}
  
  for _, issue in ipairs(issues) do
    local status_name = issue.state and issue.state.name or "Unknown"
    
    -- Check if this status is in our desired order
    local status_included = false
    for _, desired_status in ipairs(issue_order) do
      if status_name == desired_status then
        status_included = true
        break
      end
    end
    
    if status_included then
      if not issues_by_status[status_name] then
        issues_by_status[status_name] = {}
      end
      table.insert(issues_by_status[status_name], issue)
    else
      table.insert(unmatched_issues, { issue = issue, status = status_name })
    end
  end
  
  -- Log excluded issues for debugging
  if #unmatched_issues > 0 then
    local excluded_statuses = {}
    for _, item in ipairs(unmatched_issues) do
      if not excluded_statuses[item.status] then
        excluded_statuses[item.status] = 0
      end
      excluded_statuses[item.status] = excluded_statuses[item.status] + 1
    end
    logger.debug('LINEAR', 'Issues excluded by status filter', excluded_statuses)
  end
  
  -- Build result in the specified order
  local ordered_issues = {}
  for _, status_name in ipairs(issue_order) do
    local status_issues = issues_by_status[status_name] or {}
    
    -- Sort by updatedAt within each status (most recent first)
    table.sort(status_issues, function(a, b)
      if not a.updatedAt or not b.updatedAt then
        return false
      end
      return a.updatedAt > b.updatedAt
    end)
    
    -- Add to result
    for _, issue in ipairs(status_issues) do
      table.insert(ordered_issues, issue)
    end
    
    logger.debug('LINEAR', 'Added status group to results', { 
      status = status_name,
      count = #status_issues 
    })
  end
  
  logger.info('LINEAR', 'Issue filtering complete', { 
    original_count = #issues,
    filtered_count = #ordered_issues,
    excluded_count = #unmatched_issues 
  })
  
  return ordered_issues
end

-- Private helper methods
function LinearProvider:_make_request(data)
  if not data or not data.query then
    return false, { errors = { { message = "No query provided" } } }
  end
  
  if not self.api_key then
    return false, { errors = { { message = "No API key configured" } } }
  end
  
  -- Only include variables if they exist and are not empty
  local payload_data = { query = data.query }
  if data.variables and next(data.variables) then
    payload_data.variables = data.variables
  end
  
  local payload = vim.json.encode(payload_data)
  
  -- Write payload to temporary file for security
  local temp_file = vim.fn.tempname()
  local file = io.open(temp_file, 'w')
  if not file then
    return false, { errors = { { message = "Failed to create temporary file" } } }
  end
  file:write(payload)
  file:close()
  
  -- Use curl with temporary file to avoid shell injection
  local curl_command = string.format([[
    curl -X POST "https://api.linear.app/graphql" \
    -H "Content-Type: application/json" \
    -H "Authorization: %s" \
    -d @%s \
    --silent \
    --max-time 10 \
    --show-error
  ]], self.api_key, vim.fn.shellescape(temp_file))
  
  local response = vim.fn.system(curl_command)
  local exit_code = vim.v.shell_error
  
  -- Clean up temporary file
  os.remove(temp_file)
  
  if exit_code ~= 0 then
    return false, { errors = { { message = "HTTP request failed: " .. response } } }
  end
  
  local ok, decoded = pcall(vim.json.decode, response)
  if not ok then
    return false, { errors = { { message = "Failed to parse JSON response: " .. tostring(decoded) } } }
  end
  
  if decoded.errors then
    return false, decoded
  end
  
  return true, decoded
end

-- Get available teams (cached)
function LinearProvider:get_teams()
  local cached = self:get_cache("teams")
  if cached then
    return cached
  end
  
  if not self:is_authenticated() then
    return nil, "Not authenticated"
  end
  
  local query = [[
    query {
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
  
  local success, result = self:_make_request({ query = query })
  
  if success and result and result.data and result.data.teams then
    local teams = result.data.teams.nodes
    self:set_cache("teams", teams, 3600) -- Cache for 1 hour
    return teams
  else
    local error_msg = result and result.errors and result.errors[1] and result.errors[1].message or "Failed to fetch teams"
    return nil, error_msg
  end
end

-- Get available projects for a team (cached)
function LinearProvider:get_projects(team_id)
  local cache_key = "projects_" .. (team_id or "all")
  local cached = self:get_cache(cache_key)
  if cached then
    return cached
  end
  
  if not self:is_authenticated() then
    return nil, "Not authenticated"
  end
  
  local query = [[
    query {
      projects {
        nodes {
          id
          name
          description
          state
          targetDate
          teams {
            nodes {
              id
              name
              key
            }
          }
        }
      }
    }
  ]]
  
  local success, result = self:_make_request({ query = query })
  
  if success and result and result.data and result.data.projects then
    local all_projects = result.data.projects.nodes
    local filtered_projects = {}
    
    for _, project in ipairs(all_projects) do
      -- Filter out archived/completed projects
      if project.state ~= "completed" and project.state ~= "canceled" then
        -- If team_id is specified, only include projects that belong to that team
        if team_id then
          local belongs_to_team = false
          if project.teams and project.teams.nodes then
            for _, team in ipairs(project.teams.nodes) do
              if team.id == team_id then
                belongs_to_team = true
                break
              end
            end
          end
          if belongs_to_team then
            table.insert(filtered_projects, project)
          end
        else
          -- No team filter, include all active projects
          table.insert(filtered_projects, project)
        end
      end
    end
    
    self:set_cache(cache_key, filtered_projects, 3600) -- Cache for 1 hour
    return filtered_projects
  else
    local error_msg = result and result.errors and result.errors[1] and result.errors[1].message or "Failed to fetch projects"
    return nil, error_msg
  end
end

return LinearProvider
