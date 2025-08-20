# Function Patterns

This guide covers the standard patterns for defining functions in Neovim Lua plugins, including signature conventions, error handling, and common implementation patterns.

## Setup Function Pattern

### Standard Setup Function

```lua
---@class PluginConfig
---@field enabled? boolean
---@field option? string
---@field nested? NestedConfig

---@class NestedConfig  
---@field sub_option? boolean

local M = {}

---Initialize the plugin with user configuration
---@param opts? PluginConfig User configuration options
function M.setup(opts)
  -- 1. Version/compatibility checks
  if vim.fn.has("nvim-0.9.0") == 0 then
    M.error("Plugin requires Neovim >= 0.9.0")
    return
  end
  
  -- 2. Prevent double initialization
  if M._setup_done then
    M.warn("Plugin already initialized")
    return
  end
  
  -- 3. Merge with defaults
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.defaults, opts)
  
  -- 4. Validate configuration
  M.validate_config(M.config)
  
  -- 5. Initialize core systems
  M.init_core()
  M.setup_autocmds()
  M.setup_commands()
  
  -- 6. Mark as initialized
  M._setup_done = true
end
```

### Deferred Setup Pattern

```lua
---Setup the plugin with lazy initialization
---@param opts? PluginConfig
function M.setup(opts)
  M._user_opts = opts or {}
  
  -- Defer actual initialization until first use
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      M._do_setup()
    end,
  })
end

---@private
function M._do_setup()
  M.config = vim.tbl_deep_extend("force", M.defaults, M._user_opts)
  M.init_core()
  M._setup_done = true
end
```

## Configuration Function Patterns

### Option Validation

```lua
---Validate plugin configuration
---@param config PluginConfig
---@return boolean valid
---@return string? error_msg
function M.validate_config(config)
  local function validate_type(value, expected_type, path)
    if type(value) ~= expected_type then
      return false, string.format("Invalid type for %s: expected %s, got %s", 
        path, expected_type, type(value))
    end
    return true
  end
  
  -- Validate required fields
  if not validate_type(config.enabled, "boolean", "enabled") then
    return false
  end
  
  -- Validate optional fields
  if config.option and not validate_type(config.option, "string", "option") then
    return false
  end
  
  return true
end
```

### Configuration Merging

```lua
---Merge user options with defaults intelligently
---@param user_opts table User provided options
---@param defaults table Default configuration
---@return table merged Merged configuration
function M.merge_config(user_opts, defaults)
  local function merge_tables(target, source)
    for key, value in pairs(source) do
      if type(target[key]) == "table" and type(value) == "table" then
        target[key] = merge_tables(target[key], value)
      else
        target[key] = value
      end
    end
    return target
  end
  
  return merge_tables(vim.deepcopy(defaults), user_opts or {})
end
```

## API Function Patterns

### Standard API Function

```lua
---Perform a plugin operation
---@param input string Required input parameter
---@param opts? ApiOptions Optional configuration
---@return ApiResult? result Operation result or nil on failure
function M.api_function(input, opts)
  -- 1. Check initialization
  if not M._setup_done then
    M.error("Plugin not initialized. Call setup() first.")
    return nil
  end
  
  -- 2. Validate input parameters
  if type(input) ~= "string" or input == "" then
    M.error("Invalid input: expected non-empty string")
    return nil
  end
  
  -- 3. Normalize options
  opts = opts or {}
  opts = vim.tbl_extend("keep", opts, M.config.api_defaults)
  
  -- 4. Perform operation with error handling
  local ok, result = pcall(M._internal_operation, input, opts)
  if not ok then
    M.error("Operation failed: " .. result)
    return nil
  end
  
  return result
end
```

### Async Function Pattern

```lua
---Asynchronous operation with callback
---@param input string Input parameter
---@param callback fun(result: ApiResult?, error: string?) Completion callback
---@param opts? AsyncOptions Optional configuration
function M.async_operation(input, callback, opts)
  opts = opts or {}
  local timeout = opts.timeout or 5000
  
  -- Create async context
  local timer = vim.loop.new_timer()
  local completed = false
  
  -- Timeout handler
  timer:start(timeout, 0, function()
    if not completed then
      completed = true
      timer:close()
      vim.schedule(function()
        callback(nil, "Operation timed out after " .. timeout .. "ms")
      end)
    end
  end)
  
  -- Perform async work
  vim.loop.new_work(function()
    -- Background work
    local result = M._process_in_background(input, opts)
    return result
  end, function(result)
    if not completed then
      completed = true
      timer:close()
      vim.schedule(function()
        callback(result, nil)
      end)
    end
  end)
end
```

### Promise-Based Async Pattern

```lua
---Promise-based async operation
---@param input string Input parameter
---@param opts? AsyncOptions
---@return Promise
function M.async_promise(input, opts)
  local Promise = require("plugin-name.promise")
  
  return Promise.new(function(resolve, reject)
    M.async_operation(input, function(result, error)
      if error then
        reject(error)
      else
        resolve(result)
      end
    end, opts)
  end)
end
```

## Error Handling Patterns

### Centralized Error Handling

```lua
---Report error with consistent formatting
---@param msg string|string[] Error message
---@param opts? NotifyOptions Notification options
function M.error(msg, opts)
  opts = opts or {}
  if type(msg) == "table" then
    msg = table.concat(msg, "\n")
  end
  
  local formatted_msg = string.format("[%s] %s", M.plugin_name, msg)
  vim.notify(formatted_msg, vim.log.levels.ERROR, opts)
  
  -- Log to debug file if enabled
  if M.config.debug then
    M.log("ERROR", msg)
  end
end

---Report warning
---@param msg string Warning message
function M.warn(msg)
  local formatted_msg = string.format("[%s] %s", M.plugin_name, msg)
  vim.notify(formatted_msg, vim.log.levels.WARN)
end

---Report info message
---@param msg string Info message
function M.info(msg)
  local formatted_msg = string.format("[%s] %s", M.plugin_name, msg)
  vim.notify(formatted_msg, vim.log.levels.INFO)
end
```

### Try-Catch Pattern

```lua
---Execute function with error handling
---@param fn function Function to execute
---@param opts? TryOptions Options for error handling
---@return any? result Function result or nil on error
---@return string? error Error message if any
function M.try(fn, opts)
  opts = opts or {}
  local context = opts.context or "operation"
  
  local ok, result = pcall(fn)
  if not ok then
    local error_msg = string.format("Failed to %s: %s", context, result)
    if opts.notify ~= false then
      M.error(error_msg)
    end
    return nil, error_msg
  end
  
  return result, nil
end

-- Usage example
local result, error = M.try(function()
  return M.risky_operation()
end, { context = "perform risky operation" })

if not result then
  return nil
end
```

### Graceful Degradation

```lua
---Operation with fallback behavior
---@param primary_fn function Primary operation
---@param fallback_fn function Fallback operation
---@param opts? FallbackOptions
---@return any result
function M.with_fallback(primary_fn, fallback_fn, opts)
  opts = opts or {}
  
  local ok, result = pcall(primary_fn)
  if ok then
    return result
  end
  
  if opts.log_fallback then
    M.warn("Primary operation failed, using fallback: " .. result)
  end
  
  return fallback_fn()
end
```

## Utility Function Patterns

### Throttling and Debouncing

```lua
---Create a throttled version of a function
---@param fn function Function to throttle
---@param delay number Delay in milliseconds
---@return function throttled_fn
function M.throttle(fn, delay)
  local timer = nil
  local last_args = nil
  
  return function(...)
    last_args = { ... }
    
    if timer then
      return
    end
    
    timer = vim.defer_fn(function()
      timer = nil
      fn(unpack(last_args))
    end, delay)
  end
end

---Create a debounced version of a function
---@param fn function Function to debounce
---@param delay number Delay in milliseconds
---@return function debounced_fn
function M.debounce(fn, delay)
  local timer = nil
  
  return function(...)
    local args = { ... }
    
    if timer then
      timer:stop()
    end
    
    timer = vim.defer_fn(function()
      fn(unpack(args))
    end, delay)
  end
end
```

### Memoization Pattern

```lua
---Create a memoized version of a function
---@param fn function Function to memoize
---@param key_fn? function Optional key generation function
---@return function memoized_fn
function M.memoize(fn, key_fn)
  local cache = {}
  key_fn = key_fn or function(...) return table.concat({...}, "|") end
  
  return function(...)
    local key = key_fn(...)
    if cache[key] == nil then
      cache[key] = fn(...)
    end
    return cache[key]
  end
end
```

### Weak Reference Pattern

```lua
---Create a weak reference to an object
---@generic T
---@param obj T Object to create weak reference for
---@return fun(): T? getter Function to get the object or nil if collected
function M.weak_ref(obj)
  local weak_table = setmetatable({ obj }, { __mode = "v" })
  return function()
    return weak_table[1]
  end
end
```

## Event Handler Patterns

### Autocmd Handler

```lua
---Create autocmd with proper error handling
---@param event string|string[] Event name(s)
---@param opts AutocmdOptions Autocmd options
function M.create_autocmd(event, opts)
  opts = opts or {}
  local original_callback = opts.callback
  
  opts.callback = function(args)
    local ok, result = pcall(original_callback, args)
    if not ok then
      M.error("Autocmd callback failed: " .. result)
    end
    return result
  end
  
  return vim.api.nvim_create_autocmd(event, opts)
end
```

### Event Dispatcher Pattern

```lua
local M = {}

---@type table<string, function[]>
M._listeners = {}

---Register event listener
---@param event string Event name
---@param callback function Event handler
function M.on(event, callback)
  if not M._listeners[event] then
    M._listeners[event] = {}
  end
  table.insert(M._listeners[event], callback)
end

---Emit event to all listeners
---@param event string Event name
---@param ... any Event arguments
function M.emit(event, ...)
  local listeners = M._listeners[event]
  if not listeners then
    return
  end
  
  for _, callback in ipairs(listeners) do
    local ok, result = pcall(callback, ...)
    if not ok then
      M.error("Event listener failed: " .. result)
    end
  end
end

return M
```

## Functional Programming Patterns

### Function Composition

```lua
---Compose multiple functions into one
---@param ... function Functions to compose (right to left)
---@return function composed_fn
function M.compose(...)
  local fns = { ... }
  return function(value)
    for i = #fns, 1, -1 do
      value = fns[i](value)
    end
    return value
  end
end

-- Usage
local process_data = M.compose(
  M.format_output,
  M.transform_data,
  M.validate_input
)
```

### Partial Application

```lua
---Create a partially applied function
---@param fn function Function to partially apply
---@param ... any Arguments to pre-fill
---@return function partial_fn
function M.partial(fn, ...)
  local partial_args = { ... }
  return function(...)
    local full_args = {}
    for i, arg in ipairs(partial_args) do
      full_args[i] = arg
    end
    for i, arg in ipairs({ ... }) do
      full_args[#partial_args + i] = arg
    end
    return fn(unpack(full_args))
  end
end
```

## Best Practices Summary

1. **Consistent Signatures**: Use standard parameter ordering (required, optional, callback)
2. **Error Handling**: Always handle errors gracefully with informative messages
3. **Validation**: Validate inputs early and provide clear error messages
4. **Documentation**: Use comprehensive LuaLS annotations
5. **Initialization Checks**: Verify plugin setup before performing operations
6. **Resource Cleanup**: Properly cleanup timers, autocmds, and other resources
7. **Async Safety**: Use vim.schedule() for UI operations in async contexts
8. **Performance**: Use memoization and throttling for expensive operations

These patterns ensure robust, maintainable, and user-friendly plugin functions that follow established community conventions.