---@class Provider
---@field name string Provider identifier
---@field config table Provider configuration
---@field enabled boolean Provider status
local Provider = {}
Provider.__index = Provider

-- Provider constructor
---@param name string Provider identifier
---@param config table Provider configuration
---@return Provider
function Provider:new(name, config)
  local instance = setmetatable({}, self)
  instance.name = name or "unknown"
  instance.config = config or {}
  instance.enabled = false
  instance._cache = {}
  instance._last_error = nil
  return instance
end

-- Authentication methods
---@return boolean success
---@return string? error_message
function Provider:authenticate()
  error("Provider:authenticate() must be implemented by subclass")
end

---@return boolean
function Provider:is_authenticated()
  error("Provider:is_authenticated() must be implemented by subclass")
end

-- Issue management methods
---@param opts table? Query options
---@return table[] issues
---@return string? error_message
function Provider:get_issues(opts)
  error("Provider:get_issues() must be implemented by subclass")
end

---@param id string Issue identifier
---@param data table Issue update data
---@return table? updated_issue
---@return string? error_message
function Provider:update_issue(id, data)
  error("Provider:update_issue() must be implemented by subclass")
end

---@param data table Issue creation data
---@return table? created_issue
---@return string? error_message  
function Provider:create_issue(data)
  error("Provider:create_issue() must be implemented by subclass")
end

---@param id string Issue identifier
---@return table? issue
---@return string? error_message
function Provider:get_issue(id)
  error("Provider:get_issue() must be implemented by subclass")
end

-- User information methods
---@return table? user_info
---@return string? error_message
function Provider:get_user_info()
  error("Provider:get_user_info() must be implemented by subclass")
end

-- Health check methods
---@return boolean healthy
---@return string? status_message
function Provider:health_check()
  error("Provider:health_check() must be implemented by subclass")
end

-- Provider lifecycle methods
---@return boolean success
---@return string? error_message
function Provider:enable()
  local success, err = self:health_check()
  if success then
    self.enabled = true
    return true
  else
    self.enabled = false
    return false, err
  end
end

---@return boolean success
function Provider:disable()
  self.enabled = false
  self._cache = {}
  return true
end

-- Configuration methods
---@param config table New configuration
function Provider:update_config(config)
  self.config = vim.tbl_deep_extend("force", self.config, config or {})
  -- Re-authenticate if config changes
  if self.enabled then
    self:authenticate()
  end
end

---@return table
function Provider:get_config()
  return vim.deepcopy(self.config)
end

-- Cache management
---@param key string Cache key
---@param value any Value to cache
---@param ttl number? Time to live in seconds
function Provider:set_cache(key, value, ttl)
  self._cache[key] = {
    value = value,
    timestamp = os.time(),
    ttl = ttl or 300 -- 5 minutes default
  }
end

---@param key string Cache key
---@return any? value
function Provider:get_cache(key)
  local cached = self._cache[key]
  if not cached then
    return nil
  end
  
  local age = os.time() - cached.timestamp
  if age > cached.ttl then
    self._cache[key] = nil
    return nil
  end
  
  return cached.value
end

-- Error handling
---@param error string Error message
function Provider:set_error(error)
  self._last_error = {
    message = error,
    timestamp = os.time()
  }
end

---@return string? error_message
function Provider:get_last_error()
  return self._last_error and self._last_error.message
end

-- Provider information
---@return table
function Provider:get_info()
  return {
    name = self.name,
    enabled = self.enabled,
    authenticated = self:is_authenticated(),
    last_error = self:get_last_error(),
    config_keys = vim.tbl_keys(self.config)
  }
end

-- Abstract method validation
function Provider:validate_implementation()
  local required_methods = {
    "authenticate",
    "is_authenticated", 
    "get_issues",
    "update_issue",
    "create_issue",
    "get_issue",
    "get_user_info",
    "health_check"
  }
  
  local missing = {}
  for _, method in ipairs(required_methods) do
    if type(self[method]) ~= "function" then
      table.insert(missing, method)
    end
  end
  
  return #missing == 0, missing
end

return Provider