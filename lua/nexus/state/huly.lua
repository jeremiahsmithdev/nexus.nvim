local M = {}

local logger = require('nexus.logger')
local config = require('nexus.config')

-- State variables
local _issues = {}
local _provider = nil
local _last_refresh = 0
local _is_loading = false
local _error = nil
local _current_workspace = nil
local _current_project = nil

-- Cache TTL configuration
local CACHE_TTL = {
  issues = 300,      -- 5 minutes
  workspaces = 3600,  -- 1 hour
  projects = 3600,    -- 1 hour
  provider = 1800    -- 30 minutes
}

---Get the repository-local config directory
local function get_config_dir()
  local repo_root = require('nexus.git.root').get()
  if repo_root then
    return repo_root .. "/.nexus"
  end
  -- Fallback to global config if not in a git repo
  return vim.fn.expand("~/.config/nexus")
end

---Initialize Huly state
function M.init()
  local config_dir = get_config_dir()

  -- Ensure config directory exists
  if vim.fn.isdirectory(config_dir) == 0 then
    vim.fn.mkdir(config_dir, "p")
  end

  -- Load persistent configuration
  M._load_persistent_config()
end

-- Persistent credentials storage
local _saved_token = nil
local _saved_workspace_name = nil

---Load persistent configuration from disk
function M._load_persistent_config()
  local config_file = get_config_dir() .. "/huly_config.json"
  if vim.fn.filereadable(config_file) == 1 then
    local content = vim.fn.readfile(config_file)
    if content and #content > 0 then
      local ok, decoded = pcall(vim.json.decode, table.concat(content, ""))
      if ok then
        _current_workspace = decoded.workspace
        _current_project = decoded.project
        _saved_token = decoded.token
        _saved_workspace_name = decoded.workspace_name
        logger.debug('HULY', 'Loaded persistent configuration', {
          workspace_name = _saved_workspace_name,
          has_token = _saved_token ~= nil
        })

        -- Apply saved credentials to runtime config
        if _saved_token or _saved_workspace_name then
          local config_module = require('nexus.config')
          local current_config = config_module.get()
          if not current_config.huly then
            current_config.huly = {}
          end
          if _saved_token then
            current_config.huly.token = _saved_token
          end
          if _saved_workspace_name then
            current_config.huly.workspace = _saved_workspace_name
          end
          -- Auto-enable if we have saved credentials
          if _saved_token and _saved_workspace_name then
            current_config.huly.enabled = true
          end
        end
      else
        logger.warn('HULY', 'Failed to decode persistent config', { error = decoded })
      end
    end
  end
end

---Save persistent configuration to disk
function M._save_persistent_config()
  local config_dir = get_config_dir()
  -- Ensure directory exists
  if vim.fn.isdirectory(config_dir) == 0 then
    vim.fn.mkdir(config_dir, "p")
  end
  local config_file = config_dir .. "/huly_config.json"

  -- Get current credentials from runtime config
  local config_module = require('nexus.config')
  local current_config = config_module.get()
  local token = current_config.huly and current_config.huly.token
  local workspace_name = current_config.huly and current_config.huly.workspace

  -- Validate token doesn't have garbage (sanity check)
  if token and (token:match("^%s") or token:match("Workspace:")) then
    logger.warn('HULY', 'Token appears corrupted, not saving')
    return
  end

  -- Only save credentials, not the old workspace/project selection state
  local config_data = {
    token = token,
    workspace_name = workspace_name,
  }

  local ok, encoded = pcall(vim.json.encode, config_data)
  if ok then
    vim.fn.writefile({ encoded }, config_file)
    logger.debug('HULY', 'Saved persistent configuration', {
      workspace_name = workspace_name,
      has_token = token ~= nil
    })
  else
    logger.warn('HULY', 'Failed to encode persistent config', { error = encoded })
  end
end

---Get saved token
function M.get_saved_token()
  return _saved_token
end

---Get saved workspace name
function M.get_saved_workspace_name()
  return _saved_workspace_name
end

---Reset provider instance (forces recreation with new credentials)
function M._reset_provider()
  _provider = nil
  _last_refresh = 0
  _is_loading = false
  _error = nil
  logger.debug('HULY', 'Provider reset')
end

---Get or create cached provider instance
---@return HulyProvider
function M.get_cached_provider()
  local now = os.time()

  -- Check if provider exists and is still valid
  if _provider and (now - _last_refresh < CACHE_TTL.provider) then
    return _provider
  end

  -- Create new provider instance
  local HulyProvider = require('nexus.providers.huly')
  local nexus_config = config.get()

  _provider = HulyProvider:new("huly", nexus_config.huly or {})
  _last_refresh = now

  logger.debug('HULY', 'Created new provider instance', {
    workspace = nexus_config.huly and nexus_config.huly.workspace,
    has_token = nexus_config.huly and (nexus_config.huly.token ~= nil) or false,
    has_email = nexus_config.huly and (nexus_config.huly.email ~= nil) or false
  })

  return _provider
end

---Check if currently loading data
---@return boolean
function M.is_loading()
  return _is_loading
end

---Get current error message
---@return string|nil
function M.get_error()
  return _error
end

---Clear current error
function M.clear_error()
  _error = nil
end

---Get current issues
---@return table[]
function M.get_issues()
  return _issues or {}
end

---Get status display order (maps status name -> order index)
---@return table
function M.get_status_order()
  if _provider then
    return _provider:get_status_order()
  end
  return {}
end

---Set issues data
---@param issues table[]
function M.set_issues(issues)
  _issues = issues or {}
  _last_refresh = os.time()
  M.clear_error()
end

---Get current workspace selection
---@return string|nil
function M.get_current_workspace()
  return _current_workspace
end

---Set current workspace selection
---@param workspace string|nil
function M.set_current_workspace(workspace)
  _current_workspace = workspace
  M._save_persistent_config()
  logger.info('HULY', 'Workspace selection updated', { workspace = workspace })
end

---Get current project selection
---@return string|nil
function M.get_current_project()
  return _current_project
end

---Set current project selection
---@param project string|nil
function M.set_current_project(project)
  _current_project = project
  M._save_persistent_config()
  logger.info('HULY', 'Project selection updated', { project = project })
end

---Refresh data if needed based on TTL
---@param config table Nexus configuration
function M.refresh_if_needed(config)
  local now = os.time()
  local issues_ttl = (config.huly and config.huly.cache and config.huly.cache.issues_ttl) or CACHE_TTL.issues

  if not _issues or (now - _last_refresh > issues_ttl) then
    logger.debug('HULY', 'Issues cache expired, refreshing', {
      last_refresh = _last_refresh,
      now = now,
      ttl = issues_ttl
    })
    M.refresh_data(config)
  end
end

---Force refresh all data
---@param config table Nexus configuration
---@param callback function|nil Optional callback
function M.refresh_data(config, callback)
  if _is_loading then
    logger.debug('HULY', 'Already loading, skipping refresh')
    return
  end

  _is_loading = true
  _error = nil

  logger.info('HULY', 'Starting data refresh')

  local provider = M.get_cached_provider()

  -- Authenticate async (this starts the bridge if needed)
  provider:authenticate(function(auth_success, auth_error)
    if not auth_success then
      _error = auth_error or "Authentication failed"
      _is_loading = false
      logger.error('HULY', 'Authentication failed', { error = _error })

      if callback then
        vim.schedule(function() callback(false, _error) end)
      end
      return
    end

    -- Set current workspace/project from config if not already set
    if not _current_workspace and config.huly and config.huly.workspace then
      M.set_current_workspace(config.huly.workspace)
    end

    -- Get issues
    local issues, issues_error = provider:get_issues()
    if issues_error then
      _error = issues_error
      _is_loading = false
      logger.error('HULY', 'Failed to fetch issues', { error = _error })

      if callback then
        vim.schedule(function() callback(false, _error) end)
      end
      return
    end

    -- Update state
    M.set_issues(issues)
    _is_loading = false

    logger.info('HULY', 'Data refresh completed', {
      issues_count = #issues,
      workspace = _current_workspace,
      project = _current_project
    })

    if callback then
      vim.schedule(function() callback(true, nil) end)
    end
  end)
end

---Get available workspaces
---@param callback function Callback with (workspaces, error)
function M.get_workspaces(callback)
  local provider = M.get_cached_provider()

  vim.schedule(function()
    local workspaces, error = provider:get_workspaces()
    if error then
      logger.error('HULY', 'Failed to fetch workspaces', { error = error })
      callback(nil, error)
    else
      logger.debug('HULY', 'Fetched workspaces', { count = #workspaces })
      callback(workspaces, nil)
    end
  end)
end

---Get available projects for workspace
---@param workspace string|nil Workspace name (nil for all)
---@param callback function Callback with (projects, error)
function M.get_projects(workspace, callback)
  local provider = M.get_cached_provider()

  vim.schedule(function()
    local projects, error = provider:get_projects(workspace)
    if error then
      logger.error('HULY', 'Failed to fetch projects', { error = error })
      callback(nil, error)
    else
      logger.debug('HULY', 'Fetched projects', {
        workspace = workspace,
        count = #projects
      })
      callback(projects, nil)
    end
  end)
end

---Create a new issue
---@param data table Issue data
---@param callback function Callback with (issue, error)
function M.create_issue(data, callback)
  local provider = M.get_cached_provider()

  logger.info('HULY', 'Creating issue', data)

  vim.schedule(function()
    local issue, error = provider:create_issue(data)
    if error then
      logger.error('HULY', 'Failed to create issue', { error = error })
      callback(nil, error)
    else
      logger.info('HULY', 'Issue created successfully', {
        id = issue.id,
        identifier = issue.identifier
      })
      callback(issue, nil)

      -- Refresh issues after creation
      M.refresh_data(config.get())
    end
  end)
end

---Update an issue
---@param id string Issue ID
---@param data table Update data
---@param callback function Callback with (issue, error)
function M.update_issue(id, data, callback)
  local provider = M.get_cached_provider()

  logger.info('HULY', 'Updating issue', { id = id, data = data })

  vim.schedule(function()
    local issue, error = provider:update_issue(id, data)
    if error then
      logger.error('HULY', 'Failed to update issue', { error = error })
      callback(nil, error)
    else
      logger.info('HULY', 'Issue updated successfully', {
        id = issue.id,
        identifier = issue.identifier
      })
      callback(issue, nil)

      -- Refresh issues after update
      M.refresh_data(config.get())
    end
  end)
end

---Setup API key interactively
---@param callback function Optional callback
function M.setup_api_key(callback)
  local provider = M.get_cached_provider()

  vim.ui.input({
    prompt = 'Enter Huly API token: ',
    default = '',
    completion = 'secret'
  }, function(token)
    if not token or token == '' then
      logger.info('HULY', 'API key setup cancelled')
      if callback then
        callback(false, "Cancelled")
      end
      return
    end

    -- Update provider configuration
    provider.token = token

    -- Test the token
    local success, error = provider:authenticate()
    if success then
      logger.info('HULY', 'API token setup successful')
      _error = nil

      if callback then
        callback(true, nil)
      end
    else
      logger.error('HULY', 'API token setup failed', { error = error })
      _error = error or "Invalid token"

      if callback then
        callback(false, _error)
      end
    end
  end)
end

---Select workspace interactively
---@param callback function Callback with (workspace, error)
function M.select_workspace(callback)
  M.get_workspaces(function(workspaces, error)
    if error then
      callback(nil, error)
      return
    end

    if not workspaces or #workspaces == 0 then
      callback(nil, "No workspaces found")
      return
    end

    -- Create selection list
    local workspace_names = {}
    for _, workspace in ipairs(workspaces) do
      table.insert(workspace_names, workspace.name)
    end

    vim.ui.select(workspace_names, {
      prompt = 'Select Huly workspace:',
      kind = 'huly_workspace'
    }, function(selected_name)
      if not selected_name then
        callback(nil, "Cancelled")
        return
      end

      -- Find the selected workspace object
      local selected_workspace = nil
      for _, workspace in ipairs(workspaces) do
        if workspace.name == selected_name then
          selected_workspace = workspace
          break
        end
      end

      if selected_workspace then
        M.set_current_workspace(selected_workspace.name)
        callback(selected_workspace, nil)
      else
        callback(nil, "Workspace not found")
      end
    end)
  end)
end

---Select project interactively
---@param workspace string|nil Workspace name (nil for all projects)
---@param callback function Callback with (project, error)
function M.select_project(workspace, callback)
  M.get_projects(workspace, function(projects, error)
    if error then
      callback(nil, error)
      return
    end

    if not projects or #projects == 0 then
      callback(nil, "No projects found")
      return
    end

    -- Create selection list
    local project_names = {}
    for _, project in ipairs(projects) do
      local display_name = project.name
      if project.workspace and project.workspace.name then
        display_name = display_name .. " (" .. project.workspace.name .. ")"
      end
      table.insert(project_names, display_name)
    end

    vim.ui.select(project_names, {
      prompt = workspace and ('Select Huly project in ' .. workspace .. ':') or 'Select Huly project:',
      kind = 'huly_project'
    }, function(selected_name)
      if not selected_name then
        callback(nil, "Cancelled")
        return
      end

      -- Find the selected project object
      local selected_project = nil
      for _, project in ipairs(projects) do
        local display_name = project.name
        if project.workspace and project.workspace.name then
          display_name = display_name .. " (" .. project.workspace.name .. ")"
        end
        if display_name == selected_name then
          selected_project = project
          break
        end
      end

      if selected_project then
        M.set_current_project(selected_project.id)
        callback(selected_project, nil)
      else
        callback(nil, "Project not found")
      end
    end)
  end)
end

-- NOTE: Do NOT call M.init() at module load time as it blocks startup
-- with synchronous git commands. Init is called lazily on first use.
local _initialized = false

---Ensure initialization (called lazily on first use)
local function ensure_init()
  if not _initialized then
    _initialized = true
    M.init()
  end
end

-- Wrap functions that need initialization
local original_get_cached_provider = M.get_cached_provider
function M.get_cached_provider()
  ensure_init()
  return original_get_cached_provider()
end

local original_refresh_if_needed = M.refresh_if_needed
function M.refresh_if_needed(config)
  ensure_init()
  return original_refresh_if_needed(config)
end

return M