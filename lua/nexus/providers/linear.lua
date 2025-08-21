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
  instance.workspace_id = config.workspace_id
  
  -- Linear-specific cache
  instance._teams_cache = {}
  instance._projects_cache = {}
  
  return instance
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
  ]], limit, team_filter)
  
  local success, result = self:_make_request({ query = query })
  
  if success and result and result.data and result.data.issues then
    return result.data.issues.nodes
  else
    local error_msg = result and result.errors and result.errors[1] and result.errors[1].message or "Failed to fetch issues"
    return nil, error_msg
  end
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
  
  local mutation = string.format([[
    mutation {
      issueCreate(input: {
        title: "%s"
        description: "%s"
        teamId: "%s"
        priority: %d
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
  ]], data.title:gsub('"', '\\"'), description:gsub('"', '\\"'), team_id, priority)
  
  local success, result = self:_make_request({ query = mutation })
  
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
  
  -- Build update fields
  local update_fields = {}
  
  if data.title then
    table.insert(update_fields, 'title: "' .. data.title:gsub('"', '\\"') .. '"')
  end
  
  if data.description then
    table.insert(update_fields, 'description: "' .. data.description:gsub('"', '\\"') .. '"')
  end
  
  if data.priority then
    table.insert(update_fields, 'priority: ' .. data.priority)
  end
  
  if data.state_id then
    table.insert(update_fields, 'stateId: "' .. data.state_id .. '"')
  end
  
  if #update_fields == 0 then
    return nil, "No update fields provided"
  end
  
  local mutation = string.format([[
    mutation {
      issueUpdate(id: "%s", input: { %s }) {
        success
        issue {
          id
          identifier
          title
          url
        }
      }
    }
  ]], id, table.concat(update_fields, ", "))
  
  local success, result = self:_make_request({ query = mutation })
  
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
  
  -- Use curl via vim.fn.system for HTTP requests
  local curl_command = string.format([[
    curl -X POST "https://api.linear.app/graphql" \
    -H "Content-Type: application/json" \
    -H "Authorization: %s" \
    -d '%s' \
    --silent \
    --max-time 10 \
    --show-error
  ]], self.api_key, payload:gsub("'", "'\\''"))
  
  local response = vim.fn.system(curl_command)
  local exit_code = vim.v.shell_error
  
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

return LinearProvider
