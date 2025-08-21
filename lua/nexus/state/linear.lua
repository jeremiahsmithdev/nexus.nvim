---@class LinearState
local M = {}

local logger = require('nexus.logger')
local state = require('nexus.state')

-- Cached provider instance to avoid repeated authentication
local _cached_provider = nil
local _cached_states = {}
local _states_cache_timestamp = 0
local STATES_CACHE_TTL = 3600 -- 1 hour

---Initialize Linear state
function M.init()
  -- Only initialize if linear state doesn't exist yet
  local existing_state = state.get('linear')
  if not existing_state then
    state.update('linear', {
      issues = {},
      user_info = nil,
      teams = {},
      loading = false,
      error = nil,
      last_sync = nil,
      enabled = false
    })
    logger.info("LINEAR", "Linear state initialized")
  else
    logger.debug("LINEAR", "Linear state already exists, skipping initialization")
  end
end

---Get Linear issues from state
---@return table? issues
function M.get_issues()
  return state.get('linear', 'issues')
end

---Set Linear issues in state
---@param issues table
function M.set_issues(issues)
  state.set('linear', 'issues', issues)
  state.set('linear', 'last_sync', os.time())
end

---Get loading state
---@return boolean
function M.is_loading()
  return state.get('linear', 'loading') or false
end

---Set loading state  
---@param loading boolean
function M.set_loading(loading)
  state.set('linear', 'loading', loading)
end

---Get error state
---@return string? error
function M.get_error()
  return state.get('linear', 'error')
end

---Set error state
---@param error string?
function M.set_error(error)
  state.set('linear', 'error', error)
end

---Get user info from state
---@return table? user_info
function M.get_user_info()
  return state.get('linear', 'user_info')
end

---Set user info in state
---@param user_info table
function M.set_user_info(user_info)
  state.set('linear', 'user_info', user_info)
end

---Get teams from state
---@return table? teams
function M.get_teams()
  return state.get('linear', 'teams')
end

---Set teams in state
---@param teams table
function M.set_teams(teams)
  state.set('linear', 'teams', teams)
end

---Get enabled state
---@return boolean
function M.is_enabled()
  return state.get('linear', 'enabled') or false
end

---Set enabled state
---@param enabled boolean
function M.set_enabled(enabled)
  state.set('linear', 'enabled', enabled)
end

---Get last sync time
---@return number? timestamp
function M.get_last_sync()
  return state.get('linear', 'last_sync')
end

---Clear all Linear state
function M.clear()
  state.clear('linear')
  logger.info("LINEAR", "Linear state cleared")
end

---Check if data needs refresh (based on TTL)
---@param ttl_seconds number Time-to-live in seconds
---@return boolean needs_refresh
function M.needs_refresh(ttl_seconds)
  local last_sync = M.get_last_sync()
  if not last_sync then
    return true
  end
  
  local current_time = os.time()
  return (current_time - last_sync) > ttl_seconds
end

---Refresh Linear data if needed
---@param config table Configuration
function M.refresh_if_needed(config)
  if not config.linear or not config.linear.enabled then
    M.set_enabled(false)
    return
  end
  
  M.set_enabled(true)
  
  -- Check if we need to refresh based on TTL
  local ttl = (config.linear.cache and config.linear.cache.issues_ttl) or 300 -- 5 minutes default
  if not M.needs_refresh(ttl) and M.get_issues() then
    return -- Data is still fresh
  end
  
  -- Refresh data
  logger.debug("LINEAR", "Refreshing Linear data", { ttl = ttl })
  M.refresh_data(config)
end

---Prompt user for Linear API key
---@return string? api_key
function M.prompt_for_api_key()
  local api_key = vim.fn.input({
    prompt = "Enter your Linear API key: ",
    highlight = function()
      vim.api.nvim_echo({
        {"Linear API Key Setup", "Title"},
        {"\n"},
        {"Get your API key from: ", "Normal"},
        {"https://linear.app/settings/account/security", "Underlined"},
        {"\nAPI Key: ", "Normal"}
      }, false, {})
    end
  })
  
  if api_key and api_key ~= "" then
    -- Save to environment for current session
    vim.env.LINEAR_API_KEY = api_key
    
    -- Also try to save to shell config files for persistence
    M.save_api_key_to_shell_config(api_key)
    
    logger.info("LINEAR", "Linear API key provided by user")
    vim.notify("Linear API key saved! Refreshing issues...", vim.log.levels.INFO)
    return api_key
  end
  
  return nil
end

---Save API key to shell configuration files
---@param api_key string
function M.save_api_key_to_shell_config(api_key)
  local home = vim.fn.expand("~")
  local shell_configs = {
    home .. "/.bashrc",
    home .. "/.zshrc", 
    home .. "/.profile"
  }
  
  local export_line = string.format('export LINEAR_API_KEY="%s"', api_key)
  
  for _, config_file in ipairs(shell_configs) do
    if vim.fn.filereadable(config_file) == 1 then
      -- Check if LINEAR_API_KEY is already in the file
      local content = vim.fn.readfile(config_file)
      local found = false
      
      for i, line in ipairs(content) do
        if line:match("^export LINEAR_API_KEY=") then
          -- Update existing line
          content[i] = export_line
          found = true
          break
        end
      end
      
      if not found then
        -- Add new line
        table.insert(content, "")
        table.insert(content, "# Linear API Key (added by nexus.nvim)")
        table.insert(content, export_line)
      end
      
      -- Write back to file
      vim.fn.writefile(content, config_file)
      logger.info("LINEAR", "Updated shell config", { file = config_file })
      break -- Only update the first found config file
    end
  end
end

---Force refresh Linear data
---@param config table Configuration
function M.refresh_data(config)
  if not config.linear or not config.linear.enabled then
    return
  end
  
  M.set_loading(true)
  M.set_error(nil)
  
  -- Check if API key is available
  local api_key = config.linear.api_key or vim.env.LINEAR_API_KEY
  if not api_key or api_key == "" then
    M.set_loading(false)
    M.set_error("No API key found - press <Enter> to set up")
    return
  end
  
  -- Use cached provider
  local linear_provider = M.get_cached_provider(config)
  if not linear_provider then
    M.set_loading(false)
    M.set_error("Invalid API key - press <Enter> to update")
    return
  end
  
  -- Fetch issues
  local issues, error_msg = linear_provider:get_issues({
    limit = config.linear.max_issues or 10,
    filter_by_repository = config.linear.filter_by_repository
  })
  
  if issues then
    M.set_issues(issues)
    M.set_error(nil)
    logger.info("LINEAR", "Successfully refreshed Linear data", { 
      issue_count = #issues 
    })
  else
    M.set_error(error_msg or "Failed to fetch issues")
    logger.error("LINEAR", "Failed to refresh Linear data", { 
      error = error_msg 
    })
  end
  
  M.set_loading(false)
end

---Handle API key setup interaction
---@param config table Configuration
---@param render_callback function Callback to re-render the buffer
function M.handle_api_key_setup(config, render_callback)
  local api_key = M.prompt_for_api_key()
  if api_key then
    -- Update config for this session
    config.linear.api_key = api_key
    
    -- Refresh data with new API key
    M.refresh_data(config)
    
    -- Re-render the buffer
    if render_callback then
      render_callback()
    end
  end
end

---Get cached Linear provider instance
---@param config table Configuration
---@return table provider Linear provider instance
function M.get_cached_provider(config)
  -- Check if we have a valid cached provider
  if _cached_provider and _cached_provider:is_authenticated() then
    return _cached_provider
  end
  
  -- Create new provider instance
  local LinearProvider = require('nexus.providers.linear')
  local provider_config = vim.deepcopy(config.linear)
  provider_config.api_key = provider_config.api_key or vim.env.LINEAR_API_KEY
  
  _cached_provider = LinearProvider:new("linear", provider_config)
  
  if not _cached_provider:authenticate() then
    logger.error('LINEAR', 'Failed to authenticate provider')
    _cached_provider = nil
    return nil
  end
  
  logger.debug('LINEAR', 'Created and cached new provider instance')
  return _cached_provider
end

---Get cached team states or fetch fresh
---@param config table Configuration  
---@param team_id? string Team ID (optional)
---@return table? states Available states
function M.get_cached_states(config, team_id)
  local cache_key = team_id or 'default'
  local now = os.time()
  
  -- Check if we have valid cached states
  if _cached_states[cache_key] and (now - _states_cache_timestamp) < STATES_CACHE_TTL then
    logger.debug('LINEAR', 'Using cached states', { team_id = team_id, cache_age = now - _states_cache_timestamp })
    return _cached_states[cache_key]
  end
  
  -- Fetch fresh states
  local provider = M.get_cached_provider(config)
  if not provider then
    return nil
  end
  
  local states, error_msg = provider:get_team_states(team_id)
  if not states then
    logger.error('LINEAR', 'Failed to fetch team states', { error = error_msg })
    return nil
  end
  
  -- Cache the states
  _cached_states[cache_key] = states
  _states_cache_timestamp = now
  
  logger.debug('LINEAR', 'Fetched and cached team states', { 
    team_id = team_id, 
    states_count = #states 
  })
  
  return states
end

---Update issue status via cached provider
---@param issue_id string Issue ID
---@param status_id string New status ID
---@param config table Configuration
---@param callback function Callback function
function M.update_issue_status(issue_id, status_id, config, callback)
  local provider = M.get_cached_provider(config)
  if not provider then
    callback(false, "Failed to get authenticated provider")
    return
  end
  
  logger.info('LINEAR', 'Updating issue status via cached provider', {
    issue_id = issue_id,
    status_id = status_id
  })
  
  local updated_issue, error_msg = provider:update_issue(issue_id, { state_id = status_id })
  
  if updated_issue then
    logger.info('LINEAR', 'Issue status updated successfully', {
      identifier = updated_issue.identifier,
      new_status = updated_issue.state.name
    })
    
    -- Refresh Linear data to show the change
    M.refresh_data(config)
    
    callback(true, updated_issue)
  else
    logger.error('LINEAR', 'Failed to update issue status', {
      issue_id = issue_id,
      error = error_msg
    })
    callback(false, error_msg)
  end
end

return M