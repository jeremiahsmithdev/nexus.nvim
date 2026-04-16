--- DORMANT MODULE: Huly integration is currently disabled.
--- Provider implementation is broken (assumes GraphQL; Huly uses WebSocket via Node client).
--- Awaiting Node bridge implementation. See HULY_INTEGRATION_STATUS.md.
---
-- Huly Provider for Nexus
--
-- Connects to Huly project management via the huly-bridge HTTP server.
-- The bridge translates REST calls to Huly's WebSocket protocol.
-- The bridge is auto-started when needed.
---

local Provider = require('nexus.providers.base')
local logger = require('nexus.logger')

---@class HulyProvider : Provider
local HulyProvider = setmetatable({}, { __index = Provider })

-- Bridge process state (shared across instances)
local _bridge_job_id = nil
local _bridge_starting = false
local _bridge_ready = false

--- Get the bridge script path
local function get_bridge_path()
  -- Find the plugin directory
  local source = debug.getinfo(1, "S").source:sub(2)
  local plugin_dir = vim.fn.fnamemodify(source, ":h:h:h:h")
  return plugin_dir .. "/scripts/huly-bridge"
end

--- Check if bridge is responding
local function is_bridge_alive(bridge_url)
  local curl_cmd = string.format('curl -s --max-time 2 "%s/health" 2>/dev/null', bridge_url)
  local result = vim.fn.system(curl_cmd)
  return vim.v.shell_error == 0 and result:match('"status"')
end

--- Start the bridge server
---@param bridge_url string Bridge URL
---@param token string Huly token
---@param workspace string Workspace name
---@param callback function Called when bridge is ready (success, error)
local function start_bridge(bridge_url, token, workspace, callback)
  if _bridge_ready and is_bridge_alive(bridge_url) then
    callback(true)
    return
  end

  if _bridge_starting then
    -- Wait for existing startup
    vim.defer_fn(function()
      if _bridge_ready then
        callback(true)
      else
        callback(false, "Bridge startup timeout")
      end
    end, 5000)
    return
  end

  _bridge_starting = true
  local bridge_path = get_bridge_path()

  -- Check if node_modules exists
  if vim.fn.isdirectory(bridge_path .. "/node_modules") == 0 then
    logger.info('HULY', 'Installing bridge dependencies...')
    vim.notify("Installing Huly bridge dependencies (first time only)...", vim.log.levels.INFO)

    local install_result = vim.fn.system(string.format('cd "%s" && npm install 2>&1', bridge_path))
    if vim.v.shell_error ~= 0 then
      _bridge_starting = false
      callback(false, "Failed to install bridge dependencies: " .. install_result)
      return
    end
  end

  -- Build environment as dictionary
  local env = {
    PORT = bridge_url:match(":(%d+)") or "8088",
    PATH = os.getenv("PATH") or "",
  }
  if token then
    env.HULY_TOKEN = token
  end
  if workspace then
    env.HULY_WORKSPACE = workspace
  end

  logger.info('HULY', 'Starting bridge server', { path = bridge_path })

  -- Start the bridge as a background job
  _bridge_job_id = vim.fn.jobstart({
    "node", bridge_path .. "/server.js"
  }, {
    cwd = bridge_path,
    env = env,
    detach = false,
    on_exit = function(_, exit_code)
      logger.info('HULY', 'Bridge process exited', { exit_code = exit_code })
      _bridge_job_id = nil
      _bridge_ready = false
      _bridge_starting = false
    end,
    on_stderr = function(_, data)
      if data and data[1] and data[1] ~= "" then
        logger.debug('HULY', 'Bridge stderr', { data = data })
      end
    end,
  })

  if _bridge_job_id <= 0 then
    _bridge_starting = false
    callback(false, "Failed to start bridge process")
    return
  end

  -- Wait for bridge to be ready
  local attempts = 0
  local max_attempts = 20
  local check_interval = 250

  local function check_ready()
    attempts = attempts + 1
    if is_bridge_alive(bridge_url) then
      _bridge_ready = true
      _bridge_starting = false
      logger.info('HULY', 'Bridge is ready')
      callback(true)
    elseif attempts >= max_attempts then
      _bridge_starting = false
      callback(false, "Bridge startup timeout")
    else
      vim.defer_fn(check_ready, check_interval)
    end
  end

  vim.defer_fn(check_ready, 500)
end

--- Stop the bridge server
local function stop_bridge()
  if _bridge_job_id and _bridge_job_id > 0 then
    vim.fn.jobstop(_bridge_job_id)
    _bridge_job_id = nil
    _bridge_ready = false
    logger.info('HULY', 'Bridge stopped')
  end
end

-- Stop bridge when Neovim exits
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = stop_bridge,
  desc = "Stop Huly bridge on exit"
})

--- Huly provider constructor
---@param name string Provider identifier
---@param config table Provider configuration
---@return HulyProvider
function HulyProvider:new(name, config)
  local instance = Provider:new(name or "huly", config or {})
  setmetatable(instance, { __index = self })

  -- Bridge URL (not Huly directly - Lua can't speak WebSocket)
  instance.bridge_url = config.bridge_url or "http://localhost:8088"
  instance.token = config.token or os.getenv("HULY_TOKEN")
  instance.workspace = config.workspace or os.getenv("HULY_WORKSPACE")

  -- State
  instance._authenticated = false
  instance._statuses = {}
  instance._bridge_started = false

  return instance
end

--- Ensure bridge is running
---@param callback function Called when bridge is ready (success, error)
function HulyProvider:ensure_bridge(callback)
  start_bridge(self.bridge_url, self.token, self.workspace, callback)
end

--- Make HTTP request to bridge server
---@param endpoint string API endpoint (e.g., "/issues")
---@param method string HTTP method (default: "GET")
---@return boolean success
---@return table|nil result
function HulyProvider:_request(endpoint, method)
  method = method or "GET"

  if not self.token then
    logger.error('HULY', '_request: No token configured')
    return false, { error = "No HULY_TOKEN configured" }
  end

  local url = self.bridge_url .. endpoint
  -- URL-encode the workspace (don't use shellescape - that's for shell args, not URLs)
  local encoded_workspace = vim.fn.substitute(self.workspace, ' ', '%20', 'g')
  if not endpoint:find("?") then
    url = url .. "?workspace=" .. encoded_workspace
  elseif not endpoint:find("workspace=") then
    url = url .. "&workspace=" .. encoded_workspace
  end

  local curl_cmd = string.format(
    'curl -s -X %s "%s" -H "Authorization: Bearer %s" -H "Content-Type: application/json" --max-time 10',
    method,
    url,
    self.token
  )

  logger.debug('HULY', '_request: Making request', { endpoint = endpoint, url = url })

  local response = vim.fn.system(curl_cmd)
  local exit_code = vim.v.shell_error

  logger.debug('HULY', '_request: Got response', {
    exit_code = exit_code,
    response_length = response and #response or 0,
    response_preview = response and response:sub(1, 200) or "nil"
  })

  if exit_code ~= 0 then
    logger.error('HULY', '_request: curl failed', { exit_code = exit_code, response = response })
    return false, { error = "Bridge request failed (is huly-bridge running?): " .. response }
  end

  local ok, decoded = pcall(vim.json.decode, response)
  if not ok then
    logger.error('HULY', '_request: JSON decode failed', { error = decoded, response = response:sub(1, 200) })
    return false, { error = "Invalid JSON from bridge: " .. response:sub(1, 100) }
  end

  if decoded.error then
    logger.warn('HULY', '_request: Bridge returned error', { error = decoded.error })
    return false, decoded
  end

  logger.debug('HULY', '_request: Success', { endpoint = endpoint })
  return true, decoded
end

--- Authenticate with Huly via bridge (async version)
---@param callback function|nil Optional callback(success, error)
function HulyProvider:authenticate(callback)
  if not self.token then
    local err = "No HULY_TOKEN configured. Press 'H' to set up Huly."
    self:set_error(err)
    if callback then callback(false, err) end
    return false, err
  end

  if not self.workspace then
    local err = "No workspace configured. Press 'H' to set up Huly."
    self:set_error(err)
    if callback then callback(false, err) end
    return false, err
  end

  -- If callback provided, do async; otherwise sync
  if callback then
    self:ensure_bridge(function(bridge_ok, bridge_err)
      if not bridge_ok then
        self:set_error("Failed to start bridge: " .. (bridge_err or "Unknown"))
        callback(false, bridge_err)
        return
      end

      -- Test connection by fetching health
      local success, result = self:_request("/health")
      if success then
        self._authenticated = true
        self:_load_statuses()
        callback(true)
      else
        local err = result and result.error or "Bridge connection failed"
        self:set_error("Huly auth failed: " .. err)
        callback(false, err)
      end
    end)
    return true -- async in progress
  else
    -- Sync version - just try the request (bridge should already be running)
    local success, result = self:_request("/health")
    if success then
      self._authenticated = true
      self:_load_statuses()
      return true
    else
      local err = result and result.error or "Bridge connection failed"
      self:set_error("Huly auth failed: " .. err)
      return false, err
    end
  end
end

--- Load status mappings from bridge
function HulyProvider:_load_statuses()
  local success, result = self:_request("/statuses")
  if success and result.statuses then
    self._statuses = {}
    self._status_order = {}  -- Maps status name -> order index
    for i, status in ipairs(result.statuses) do
      self._statuses[status.id] = status.name
      -- Store order by name (position in array = display order from Huly)
      self._status_order[status.name] = i
    end
    logger.debug('HULY', 'Loaded status order', { order = self._status_order })
  end
end

--- Get status display order
function HulyProvider:get_status_order()
  return self._status_order or {}
end

function HulyProvider:is_authenticated()
  return self._authenticated
end

--- Get issues from Huly
---@param opts table|nil Options (limit, etc.)
---@return table|nil issues
---@return string|nil error
function HulyProvider:get_issues(opts)
  if not self:is_authenticated() then
    local success = self:authenticate()
    if not success then
      return nil, "Not authenticated"
    end
  end

  opts = opts or {}
  local success, result = self:_request("/issues")

  if not success then
    return nil, result and result.error or "Failed to fetch issues"
  end

  local issues = result.issues or {}

  -- Apply limit if specified
  if opts.limit and #issues > opts.limit then
    local limited = {}
    for i = 1, opts.limit do
      limited[i] = issues[i]
    end
    issues = limited
  end

  -- Transform to standard format expected by rendering
  local transformed = {}
  for _, issue in ipairs(issues) do
    table.insert(transformed, {
      id = issue.id,
      identifier = issue.identifier,
      title = issue.title,
      status = issue.status,
      status_id = issue.status_id,
      status_rank = issue.status_rank,
      status_category = issue.status_category,
      priority = issue.priority,
      priority_label = issue.priority_label,
      assignee = issue.assignee,
      createdOn = issue.created_on,
      updatedOn = issue.modified_on,
      subIssues = issue.sub_issues,
      comments = issue.comments,
    })
  end

  return transformed
end

--- Get single issue with full details
---@param identifier string Issue identifier (e.g., "PRIVC-1")
---@return table|nil issue
---@return string|nil error
function HulyProvider:get_issue(identifier)
  if not self:is_authenticated() then
    local success = self:authenticate()
    if not success then
      return nil, "Not authenticated"
    end
  end

  logger.debug('HULY', 'Fetching single issue', { identifier = identifier })

  local success, result = self:_request("/issues/" .. identifier)

  if not success then
    logger.error('HULY', 'Failed to fetch issue', { error = result and result.error })
    return nil, result and result.error or "Failed to fetch issue"
  end

  logger.debug('HULY', 'Got issue from bridge', {
    identifier = result.identifier,
    has_description = result.description ~= nil and result.description ~= "",
    description_length = result.description and #result.description or 0
  })

  return {
    id = result.id,
    identifier = result.identifier,
    title = result.title,
    description = result.description,
    status = result.status,
    status_id = result.status_id,
    priority = result.priority,
    priority_label = result.priority_label,
    assignee = result.assignee,
    createdOn = result.created_on,
    updatedOn = result.modified_on,
    subIssues = result.sub_issues,
    comments = result.comments,
    links = result.links,
  }
end

--- Create issue (placeholder - bridge doesn't support yet)
---@param data table Issue data
---@return table|nil issue
---@return string|nil error
function HulyProvider:create_issue(data)
  -- TODO: Implement when bridge supports POST /issues
  return nil, "Issue creation not yet implemented in bridge"
end

--- Update issue (placeholder - bridge doesn't support yet)
---@param id string Issue ID
---@param data table Update data
---@return table|nil issue
---@return string|nil error
function HulyProvider:update_issue(id, data)
  -- TODO: Implement when bridge supports PATCH /issues/:id
  return nil, "Issue update not yet implemented in bridge"
end

--- Get user info
function HulyProvider:get_user_info()
  -- Bridge doesn't expose user info yet
  return { name = "Huly User" }
end

--- Health check
function HulyProvider:health_check()
  if not self.token then
    return false, "No HULY_TOKEN configured"
  end

  local success, result = self:_request("/health")
  if success then
    return true, "Huly bridge connected"
  else
    return false, result and result.error or "Bridge not reachable"
  end
end

--- Get available statuses
function HulyProvider:get_statuses()
  if not self:is_authenticated() then
    self:authenticate()
  end
  return self._statuses
end

--- Get workspaces (not yet implemented in bridge)
---@return table|nil workspaces
---@return string|nil error
function HulyProvider:get_workspaces()
  -- TODO: Implement when bridge supports GET /workspaces
  return nil, "Workspace listing not yet implemented. Set workspace in config."
end

--- Get projects (not yet implemented in bridge)
---@param workspace_name string|nil
---@return table|nil projects
---@return string|nil error
function HulyProvider:get_projects(workspace_name)
  -- TODO: Implement when bridge supports GET /projects
  return nil, "Project listing not yet implemented."
end

return HulyProvider
