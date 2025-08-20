local M = {}

-- Registered providers
local providers = {}
local active_provider = nil

-- Provider types and their module paths
local PROVIDER_TYPES = {
  linear = "nexus.providers.linear",
  github = "nexus.providers.github",
  jira = "nexus.providers.jira"
}

-- Register a provider
---@param name string Provider name
---@param provider_module table Provider module
---@param config table? Provider configuration
---@return boolean success
---@return string? error_message
function M.register_provider(name, provider_module, config)
  if not name or type(name) ~= "string" then
    return false, "Provider name must be a string"
  end
  
  if not provider_module then
    return false, "Provider module is required"
  end
  
  -- Validate that the provider implements the required interface
  if type(provider_module.new) ~= "function" then
    return false, "Provider must have a 'new' constructor function"
  end
  
  -- Create provider instance
  local provider_instance = provider_module:new(name, config or {})
  
  -- Validate implementation
  local valid, missing_methods = provider_instance:validate_implementation()
  if not valid then
    return false, "Provider missing required methods: " .. table.concat(missing_methods, ", ")
  end
  
  providers[name] = {
    name = name,
    module = provider_module,
    instance = provider_instance,
    config = config or {},
    registered_at = os.time()
  }
  
  return true
end

-- Load and register a provider by type
---@param provider_type string Provider type (linear, github, jira)
---@param config table? Provider configuration
---@return boolean success
---@return string? error_message
function M.load_provider(provider_type, config)
  if not PROVIDER_TYPES[provider_type] then
    return false, "Unknown provider type: " .. provider_type
  end
  
  local module_path = PROVIDER_TYPES[provider_type]
  local ok, provider_module = pcall(require, module_path)
  
  if not ok then
    return false, "Failed to load provider module: " .. provider_module
  end
  
  return M.register_provider(provider_type, provider_module, config)
end

-- Get a registered provider
---@param name string Provider name
---@return table? provider_instance
function M.get_provider(name)
  local provider_data = providers[name]
  return provider_data and provider_data.instance
end

-- Set active provider
---@param name string Provider name
---@return boolean success
---@return string? error_message
function M.set_active_provider(name)
  local provider = M.get_provider(name)
  if not provider then
    return false, "Provider not found: " .. name
  end
  
  active_provider = name
  return true
end

-- Get active provider
---@return table? provider_instance
---@return string? provider_name
function M.get_active_provider()
  if active_provider and providers[active_provider] then
    return providers[active_provider].instance, active_provider
  end
  return nil, nil
end

-- List all registered providers
---@return table[] providers_info
function M.list_providers()
  local list = {}
  for name, data in pairs(providers) do
    table.insert(list, {
      name = name,
      enabled = data.instance.enabled,
      authenticated = data.instance:is_authenticated(),
      active = name == active_provider,
      registered_at = data.registered_at,
      info = data.instance:get_info()
    })
  end
  return list
end

-- Enable a provider
---@param name string Provider name
---@return boolean success
---@return string? error_message
function M.enable_provider(name)
  local provider = M.get_provider(name)
  if not provider then
    return false, "Provider not found: " .. name
  end
  
  return provider:enable()
end

-- Disable a provider
---@param name string Provider name
---@return boolean success
---@return string? error_message
function M.disable_provider(name)
  local provider = M.get_provider(name)
  if not provider then
    return false, "Provider not found: " .. name
  end
  
  provider:disable()
  
  -- If this was the active provider, clear it
  if active_provider == name then
    active_provider = nil
  end
  
  return true
end

-- Unregister a provider
---@param name string Provider name
---@return boolean success
function M.unregister_provider(name)
  if providers[name] then
    -- Disable first
    M.disable_provider(name)
    providers[name] = nil
    return true
  end
  return false
end

-- Health check all providers
---@return table health_status
function M.health_check_all()
  local results = {}
  for name, data in pairs(providers) do
    local healthy, message = data.instance:health_check()
    results[name] = {
      healthy = healthy,
      message = message,
      enabled = data.instance.enabled,
      authenticated = data.instance:is_authenticated()
    }
  end
  return results
end

-- Update provider configuration
---@param name string Provider name
---@param config table New configuration
---@return boolean success
---@return string? error_message
function M.update_provider_config(name, config)
  local provider_data = providers[name]
  if not provider_data then
    return false, "Provider not found: " .. name
  end
  
  provider_data.instance:update_config(config)
  provider_data.config = vim.tbl_deep_extend("force", provider_data.config, config)
  
  return true
end

-- Convenience methods for active provider
function M.get_issues(opts)
  local provider = M.get_active_provider()
  if not provider then
    return nil, "No active provider"
  end
  return provider:get_issues(opts)
end

function M.create_issue(data)
  local provider = M.get_active_provider()
  if not provider then
    return nil, "No active provider"
  end
  return provider:create_issue(data)
end

function M.update_issue(id, data)
  local provider = M.get_active_provider()
  if not provider then
    return nil, "No active provider"
  end
  return provider:update_issue(id, data)
end

function M.get_issue(id)
  local provider = M.get_active_provider()
  if not provider then
    return nil, "No active provider"
  end
  return provider:get_issue(id)
end

-- Initialize provider manager
function M.init()
  -- Clear any existing state
  providers = {}
  active_provider = nil
  
  -- Register default providers if available
  for provider_type, _ in pairs(PROVIDER_TYPES) do
    -- Try to load each provider, but don't fail if not available
    pcall(M.load_provider, provider_type, {})
  end
end

return M