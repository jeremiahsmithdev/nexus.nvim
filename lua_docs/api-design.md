# API Design

This guide covers the patterns for designing consistent, intuitive, and robust APIs for Neovim Lua plugins, based on established conventions from high-quality plugins in the ecosystem.

## API Architecture Patterns

### Plugin API Structure

```lua
---@class PluginApi
local M = {}

-- Core API functions
function M.setup(opts) end           -- Plugin initialization
function M.enable() end              -- Enable plugin functionality
function M.disable() end             -- Disable plugin functionality  
function M.toggle() end              -- Toggle plugin state
function M.info() end                -- Show plugin information
function M.health() end              -- Run health checks

-- Feature-specific APIs
M.features = {}                      -- Feature namespaces
M.ui = {}                           -- UI-related functions
M.util = {}                         -- Utility functions

return M
```

### Metatable-Based Lazy Loading

```lua
-- lazy.nvim pattern
local M = {}

-- Export main API immediately available functions
M.setup = function(opts) end
M.health = function() end

-- Lazy-load additional API functions
return setmetatable(M, {
  __index = function(t, k)
    local api = require("plugin-name.api")
    local value = api[k]
    if value ~= nil then
      rawset(t, k, value)
      return value
    end
  end,
})
```

### Global Object Pattern

```lua
-- snacks.nvim pattern for global access
local M = {}

-- Register globally for easy access
_G.PluginName = M

-- Dynamic module loading
setmetatable(M, {
  __index = function(t, k)
    -- Auto-require and cache modules
    local ok, module = pcall(require, "plugin-name." .. k)
    if ok then
      rawset(t, k, module)
      return module
    end
    
    -- Fallback to API module
    local api = require("plugin-name.api")
    local value = api[k]
    if value ~= nil then
      rawset(t, k, value)
      return value
    end
  end,
})

return M
```

## Function Signature Patterns

### Standard API Function Signatures

```lua
---Core plugin functions with consistent signatures
---@param opts? PluginSetupOptions
function M.setup(opts) end

---@param feature_name? string Optional feature to enable
function M.enable(feature_name) end

---@param feature_name? string Optional feature to disable  
function M.disable(feature_name) end

---@param feature_name? string Optional feature to toggle
---@return boolean new_state The new state after toggling
function M.toggle(feature_name) end

---@param opts? InfoOptions Display options
function M.info(opts) end

---@return table health_status Health check results
function M.health() end
```

### Operation Functions

```lua
---Perform primary plugin operation
---@param input string|table Required input parameter
---@param opts? OperationOptions Optional configuration
---@return OperationResult? result Result object or nil on failure
function M.operation(input, opts)
  -- Validate setup
  if not M._setup_done then
    M.error("Plugin not initialized. Call setup() first.")
    return nil
  end
  
  -- Normalize inputs
  input = M.normalize_input(input)
  opts = M.normalize_opts(opts)
  
  -- Perform operation
  local result, err = M._perform_operation(input, opts)
  if not result then
    M.error("Operation failed: " .. (err or "unknown error"))
    return nil
  end
  
  return result
end

---Async version of operation
---@param input string|table
---@param callback fun(result: OperationResult?, error: string?)
---@param opts? OperationOptions
function M.operation_async(input, callback, opts)
  vim.defer_fn(function()
    local result = M.operation(input, opts)
    callback(result, result and nil or "Operation failed")
  end, 0)
end
```

### Fluent API Pattern

```lua
---Fluent API builder pattern
---@class FluentBuilder
---@field _config table
local Builder = {}
Builder.__index = Builder

---Create new builder instance
---@return FluentBuilder
function M.new()
  return setmetatable({ _config = {} }, Builder)
end

---Set input value
---@param value string
---@return FluentBuilder self
function Builder:input(value)
  self._config.input = value
  return self
end

---Set option
---@param key string
---@param value any
---@return FluentBuilder self
function Builder:option(key, value)
  self._config.options = self._config.options or {}
  self._config.options[key] = value
  return self
end

---Execute the built operation
---@return OperationResult?
function Builder:execute()
  return M.operation(self._config.input, self._config.options)
end

-- Usage: M.new():input("test"):option("verbose", true):execute()
```

## Error Handling in APIs

### Consistent Error Responses

```lua
---@class ApiError
---@field code string Error code
---@field message string Human-readable error message
---@field context? table Additional error context

---Create standardized API error
---@param code string Error code
---@param message string Error message
---@param context? table Additional context
---@return ApiError
function M.create_error(code, message, context)
  return {
    code = code,
    message = message,
    context = context or {},
    timestamp = os.time(),
  }
end

---API function with structured error handling
---@param input string
---@return OperationResult? result
---@return ApiError? error
function M.api_function(input)
  -- Input validation
  if not input or input == "" then
    return nil, M.create_error("INVALID_INPUT", "Input cannot be empty")
  end
  
  -- Operation
  local ok, result = pcall(M._internal_operation, input)
  if not ok then
    return nil, M.create_error("OPERATION_FAILED", result, { input = input })
  end
  
  return result, nil
end
```

### Error Recovery Patterns

```lua
---API function with automatic retry
---@param input string
---@param opts? RetryOptions
---@return OperationResult?
function M.operation_with_retry(input, opts)
  opts = opts or {}
  local max_retries = opts.max_retries or 3
  local delay = opts.delay or 100
  
  for attempt = 1, max_retries do
    local result, error = M.api_function(input)
    if result then
      return result
    end
    
    -- Check if error is retryable
    if not M.is_retryable_error(error) then
      M.error("Non-retryable error: " .. error.message)
      return nil
    end
    
    if attempt < max_retries then
      M.warn(string.format("Attempt %d failed, retrying in %dms", attempt, delay))
      vim.defer_fn(function() end, delay)
      delay = delay * 2 -- Exponential backoff
    end
  end
  
  M.error("Operation failed after " .. max_retries .. " attempts")
  return nil
end
```

## Configuration API Patterns

### Dynamic Configuration API

```lua
---Get current configuration value
---@param path string Configuration path (dot-separated)
---@return any value Current configuration value
function M.get_config(path)
  local keys = vim.split(path, ".", { plain = true })
  local current = M.config
  
  for _, key in ipairs(keys) do
    if type(current) ~= "table" or current[key] == nil then
      return nil
    end
    current = current[key]
  end
  
  return current
end

---Set configuration value
---@param path string Configuration path
---@param value any New value
---@return boolean success Whether the update succeeded
function M.set_config(path, value)
  local keys = vim.split(path, ".", { plain = true })
  local current = M.config
  
  -- Navigate to parent
  for i = 1, #keys - 1 do
    local key = keys[i]
    if type(current[key]) ~= "table" then
      current[key] = {}
    end
    current = current[key]
  end
  
  -- Set value
  local final_key = keys[#keys]
  local old_value = current[final_key]
  current[final_key] = value
  
  -- Validate new configuration
  local valid, error_msg = M.validate_config(M.config)
  if not valid then
    -- Rollback on validation failure
    current[final_key] = old_value
    M.error("Configuration update failed: " .. error_msg)
    return false
  end
  
  -- Apply change handlers
  M.apply_config_change(path, value, old_value)
  
  return true
end

---Reset configuration to defaults
---@param path? string Optional path to reset (resets all if not provided)
function M.reset_config(path)
  if not path then
    M.config = vim.deepcopy(M.defaults)
    M.apply_full_config_reset()
  else
    local default_value = M.get_default_config(path)
    M.set_config(path, default_value)
  end
end
```

### Feature Toggle API

```lua
---Enable specific feature
---@param feature_name string Feature to enable
---@param opts? FeatureOptions Feature-specific options
---@return boolean success Whether feature was enabled
function M.enable_feature(feature_name, opts)
  if not M.features[feature_name] then
    M.error("Unknown feature: " .. feature_name)
    return false
  end
  
  if M.is_feature_enabled(feature_name) then
    M.warn("Feature already enabled: " .. feature_name)
    return true
  end
  
  local feature = M.features[feature_name]
  local ok, err = pcall(feature.enable, opts)
  if not ok then
    M.error("Failed to enable feature '" .. feature_name .. "': " .. err)
    return false
  end
  
  M.config.features[feature_name].enabled = true
  M.info("Enabled feature: " .. feature_name)
  return true
end

---Disable specific feature
---@param feature_name string Feature to disable
---@return boolean success Whether feature was disabled
function M.disable_feature(feature_name)
  if not M.features[feature_name] then
    M.error("Unknown feature: " .. feature_name)
    return false
  end
  
  if not M.is_feature_enabled(feature_name) then
    M.warn("Feature already disabled: " .. feature_name)
    return true
  end
  
  local feature = M.features[feature_name]
  local ok, err = pcall(feature.disable)
  if not ok then
    M.error("Failed to disable feature '" .. feature_name .. "': " .. err)
    return false
  end
  
  M.config.features[feature_name].enabled = false
  M.info("Disabled feature: " .. feature_name)
  return true
end

---Toggle feature state
---@param feature_name string Feature to toggle
---@return boolean new_state New feature state
function M.toggle_feature(feature_name)
  local enabled = M.is_feature_enabled(feature_name)
  if enabled then
    M.disable_feature(feature_name)
    return false
  else
    M.enable_feature(feature_name)
    return true
  end
end
```

## Status and Information APIs

### Status API

```lua
---@class PluginStatus
---@field enabled boolean Whether plugin is enabled
---@field features table<string, boolean> Feature states
---@field version string Plugin version
---@field config_valid boolean Whether configuration is valid
---@field last_error? string Last error message
---@field performance PerformanceStats Performance statistics

---Get current plugin status
---@return PluginStatus
function M.status()
  return {
    enabled = M._setup_done and M.config.enabled,
    features = M.get_feature_states(),
    version = M.version,
    config_valid = M.validate_config(M.config),
    last_error = M._last_error,
    performance = M.get_performance_stats(),
  }
end

---Get feature states
---@return table<string, boolean>
function M.get_feature_states()
  local states = {}
  for name, feature in pairs(M.features) do
    states[name] = M.is_feature_enabled(name)
  end
  return states
end

---Get performance statistics
---@return PerformanceStats
function M.get_performance_stats()
  return {
    startup_time = M._startup_time,
    operation_count = M._operation_count,
    average_operation_time = M._total_operation_time / math.max(M._operation_count, 1),
    memory_usage = collectgarbage("count"),
    cache_hit_rate = M._cache_hits / math.max(M._cache_requests, 1),
  }
end
```

### Information Display API

```lua
---Display plugin information
---@param opts? InfoDisplayOptions Display options
function M.info(opts)
  opts = opts or {}
  local format = opts.format or "popup"
  
  local info = {
    "Plugin Name: " .. M.plugin_name,
    "Version: " .. M.version,
    "Status: " .. (M.status().enabled and "Enabled" or "Disabled"),
    "",
    "Features:",
  }
  
  for name, enabled in pairs(M.get_feature_states()) do
    table.insert(info, string.format("  %s: %s", name, enabled and "✓" or "✗"))
  end
  
  if format == "popup" then
    M.ui.show_popup(info, { title = "Plugin Information" })
  elseif format == "echo" then
    vim.cmd("echohl Title | echo 'Plugin Information:' | echohl None")
    for _, line in ipairs(info) do
      print(line)
    end
  elseif format == "buffer" then
    M.ui.show_in_buffer(info, { filetype = "plugin-info" })
  end
end
```

## Async API Patterns

### Promise-Based Async API

```lua
---@class Promise
local Promise = {}
Promise.__index = Promise

---Create new promise
---@param executor fun(resolve: function, reject: function)
---@return Promise
function Promise.new(executor)
  local promise = setmetatable({
    state = "pending",
    value = nil,
    handlers = { resolved = {}, rejected = {} }
  }, Promise)
  
  local function resolve(value)
    if promise.state == "pending" then
      promise.state = "resolved"
      promise.value = value
      for _, handler in ipairs(promise.handlers.resolved) do
        handler(value)
      end
    end
  end
  
  local function reject(reason)
    if promise.state == "pending" then
      promise.state = "rejected"
      promise.value = reason
      for _, handler in ipairs(promise.handlers.rejected) do
        handler(reason)
      end
    end
  end
  
  executor(resolve, reject)
  return promise
end

---Add success handler
---@param callback function
---@return Promise
function Promise:then_call(callback)
  if self.state == "resolved" then
    callback(self.value)
  elseif self.state == "pending" then
    table.insert(self.handlers.resolved, callback)
  end
  return self
end

---Add error handler
---@param callback function
---@return Promise
function Promise:catch(callback)
  if self.state == "rejected" then
    callback(self.value)
  elseif self.state == "pending" then
    table.insert(self.handlers.rejected, callback)
  end
  return self
end

-- Async API using promises
---@param input string
---@return Promise
function M.async_operation(input)
  return Promise.new(function(resolve, reject)
    vim.defer_fn(function()
      local result, error = M.api_function(input)
      if result then
        resolve(result)
      else
        reject(error)
      end
    end, 0)
  end)
end
```

### Callback-Based Async API

```lua
---Async operation with callback
---@param input string
---@param callback fun(result: OperationResult?, error: string?)
---@param opts? AsyncOptions
function M.async_operation_callback(input, callback, opts)
  opts = opts or {}
  local timeout = opts.timeout or 5000
  
  -- Setup timeout
  local timer = vim.loop.new_timer()
  local completed = false
  
  timer:start(timeout, 0, function()
    if not completed then
      completed = true
      timer:close()
      vim.schedule(function()
        callback(nil, "Operation timed out")
      end)
    end
  end)
  
  -- Perform async work
  vim.defer_fn(function()
    local result, error = M.api_function(input)
    if not completed then
      completed = true
      timer:close()
      callback(result, error)
    end
  end, 0)
end
```

## User Command Integration

### Command Registration

```lua
---Register plugin commands
function M.setup_commands()
  local commands = {
    {
      name = "PluginEnable",
      callback = function(args)
        M.enable(args.args ~= "" and args.args or nil)
      end,
      opts = {
        desc = "Enable plugin or specific feature",
        nargs = "?",
        complete = function()
          return vim.tbl_keys(M.features)
        end,
      },
    },
    {
      name = "PluginDisable",
      callback = function(args)
        M.disable(args.args ~= "" and args.args or nil)
      end,
      opts = {
        desc = "Disable plugin or specific feature",
        nargs = "?",
        complete = function()
          return vim.tbl_keys(M.features)
        end,
      },
    },
    {
      name = "PluginToggle",
      callback = function(args)
        M.toggle(args.args ~= "" and args.args or nil)
      end,
      opts = {
        desc = "Toggle plugin or specific feature",
        nargs = "?",
        complete = function()
          return vim.tbl_keys(M.features)
        end,
      },
    },
    {
      name = "PluginInfo",
      callback = function(args)
        local format = args.args ~= "" and args.args or "popup"
        M.info({ format = format })
      end,
      opts = {
        desc = "Show plugin information",
        nargs = "?",
        complete = function()
          return { "popup", "echo", "buffer" }
        end,
      },
    },
  }
  
  for _, cmd in ipairs(commands) do
    vim.api.nvim_create_user_command(cmd.name, cmd.callback, cmd.opts)
  end
end
```

## Best Practices

### 1. API Design Principles
- **Consistency**: Use consistent naming and parameter patterns across all functions
- **Discoverability**: Group related functions logically and provide good documentation
- **Error Handling**: Always provide clear, actionable error messages
- **Backward Compatibility**: Design APIs that can evolve without breaking existing code

### 2. Function Signatures
- **Required first**: Place required parameters before optional ones
- **Options objects**: Use options tables for multiple optional parameters
- **Return values**: Be consistent about return value patterns (nil on error vs error objects)

### 3. Performance
- **Lazy loading**: Don't load API modules until they're actually used
- **Caching**: Cache expensive computations and API results when appropriate
- **Async operations**: Provide async versions for potentially slow operations

### 4. User Experience
- **Helpful defaults**: APIs should work well with minimal configuration
- **Progressive disclosure**: Simple APIs for basic use, advanced APIs for power users
- **Integration**: Provide good integration with Neovim's built-in systems (commands, autocmds, etc.)

This API design approach ensures consistent, intuitive, and robust plugin interfaces that follow established community conventions.