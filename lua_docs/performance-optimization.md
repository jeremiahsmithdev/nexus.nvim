# Performance Optimization

This guide covers performance optimization patterns for Neovim Lua plugins, focusing on startup time, runtime efficiency, and memory management based on established practices from high-performance plugins.

## Startup Optimization

### Lazy Module Loading

```lua
-- Deferred require pattern
local M = {}

-- Cache modules to avoid repeated requires
local _cache = {}

---Get module with lazy loading
---@param module_name string
---@return table module
local function get_module(module_name)
  if not _cache[module_name] then
    _cache[module_name] = require(module_name)
  end
  return _cache[module_name]
end

-- Defer expensive operations
function M.setup(opts)
  M._opts = opts or {}
  
  -- Defer initialization until needed
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",  -- or use appropriate event
    once = true,
    callback = function()
      M._do_setup()
    end,
  })
end

function M._do_setup()
  local config = get_module("plugin.config")
  local core = get_module("plugin.core")
  
  M.config = config.merge(config.defaults, M._opts)
  core.init(M.config)
end
```

### Event-Based Initialization

```lua
-- snacks.nvim pattern for feature-based loading
local M = {}

local events = {
  -- Load features on specific events
  BufReadPre = { "bigfile", "quickfile" },
  UIEnter = { "dashboard", "scroll" },
  CmdlineEnter = { "notifier" },
  LspAttach = { "words", "scope" },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})
  
  -- Setup event-based loading
  for event, features in pairs(events) do
    vim.api.nvim_create_autocmd(event, {
      once = true,
      callback = function()
        for _, feature in ipairs(features) do
          if M.config[feature] and M.config[feature] ~= false then
            M.load_feature(feature)
          end
        end
      end,
    })
  end
end

function M.load_feature(name)
  local ok, feature = pcall(require, "snacks." .. name)
  if ok and type(feature.setup) == "function" then
    feature.setup(M.config[name])
  end
end
```

### Conditional Loading

```lua
-- Load features only when dependencies are available
local function setup_integrations()
  -- Telescope integration
  if pcall(require, "telescope") then
    vim.defer_fn(function()
      require("telescope").load_extension("plugin-name")
    end, 100)
  end
  
  -- LSP integration
  vim.api.nvim_create_autocmd("LspAttach", {
    once = true,
    callback = function()
      require("plugin.integrations.lsp").setup()
    end,
  })
  
  -- TreeSitter integration
  vim.api.nvim_create_autocmd("FileType", {
    callback = function()
      if vim.treesitter.get_parser then
        require("plugin.integrations.treesitter").setup()
      end
    end,
  })
end
```

## Runtime Performance

### Throttling and Debouncing

```lua
---Universal throttle utility
---@param fn function Function to throttle
---@param ms number Throttle delay in milliseconds
---@param opts? {leading?: boolean, trailing?: boolean}
---@return function throttled_fn
function M.throttle(fn, ms, opts)
  opts = opts or {}
  local leading = opts.leading ~= false
  local trailing = opts.trailing ~= false
  
  local timer = nil
  local last_call = 0
  local last_args = nil
  
  return function(...)
    last_args = { ... }
    local now = vim.loop.now()
    
    -- Leading edge execution
    if leading and (now - last_call) >= ms then
      last_call = now
      fn(...)
      return
    end
    
    -- Setup trailing edge execution
    if trailing then
      if timer then
        timer:stop()
      end
      
      timer = vim.defer_fn(function()
        timer = nil
        last_call = vim.loop.now()
        fn(unpack(last_args))
      end, ms - (now - last_call))
    end
  end
end

---Debounce utility with immediate option
---@param fn function Function to debounce
---@param ms number Debounce delay
---@param immediate? boolean Execute immediately on first call
---@return function debounced_fn
function M.debounce(fn, ms, immediate)
  local timer = nil
  
  return function(...)
    local args = { ... }
    local call_now = immediate and not timer
    
    if timer then
      timer:stop()
    end
    
    timer = vim.defer_fn(function()
      timer = nil
      if not immediate then
        fn(unpack(args))
      end
    end, ms)
    
    if call_now then
      fn(...)
    end
  end
end
```

### Efficient Event Handling

```lua
-- Batch autocmd registration
local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("PluginName", { clear = true })
  
  local autocmds = {
    {
      event = "BufEnter",
      callback = M.on_buf_enter,
      throttle = 100,  -- Throttle frequent events
    },
    {
      event = "CursorMoved",
      callback = M.on_cursor_moved,
      debounce = 250,  -- Debounce high-frequency events
    },
    {
      event = "TextChanged",
      callback = M.on_text_changed,
      throttle = 50,
    },
  }
  
  for _, autocmd in ipairs(autocmds) do
    local callback = autocmd.callback
    
    -- Apply throttling/debouncing
    if autocmd.throttle then
      callback = M.throttle(callback, autocmd.throttle)
    elseif autocmd.debounce then
      callback = M.debounce(callback, autocmd.debounce)
    end
    
    vim.api.nvim_create_autocmd(autocmd.event, {
      group = group,
      callback = callback,
      pattern = autocmd.pattern,
    })
  end
end
```

### Smart Caching

```lua
-- Multi-level caching system
local M = {}

-- Memory cache with size limit
local memory_cache = {}
local cache_order = {}
local max_cache_size = 100

-- File-based persistent cache
local cache_file = vim.fn.stdpath("cache") .. "/plugin-cache.json"

---Get from cache with fallback to computation
---@param key string Cache key
---@param compute_fn function Function to compute value if not cached
---@param opts? {ttl?: number, persist?: boolean}
---@return any value
function M.get_cached(key, compute_fn, opts)
  opts = opts or {}
  local ttl = opts.ttl or 3600 -- 1 hour default TTL
  
  -- Check memory cache
  local cached = memory_cache[key]
  if cached and (vim.loop.now() - cached.timestamp) < (ttl * 1000) then
    -- Move to end (LRU)
    for i, k in ipairs(cache_order) do
      if k == key then
        table.remove(cache_order, i)
        break
      end
    end
    table.insert(cache_order, key)
    return cached.value
  end
  
  -- Check persistent cache
  if opts.persist then
    local persistent_value = M.get_persistent_cache(key, ttl)
    if persistent_value then
      M.set_memory_cache(key, persistent_value)
      return persistent_value
    end
  end
  
  -- Compute value
  local value = compute_fn()
  
  -- Store in cache
  M.set_memory_cache(key, value)
  if opts.persist then
    M.set_persistent_cache(key, value)
  end
  
  return value
end

---Set memory cache with LRU eviction
---@param key string
---@param value any
function M.set_memory_cache(key, value)
  -- Remove if already exists
  for i, k in ipairs(cache_order) do
    if k == key then
      table.remove(cache_order, i)
      break
    end
  end
  
  -- Add to end
  table.insert(cache_order, key)
  memory_cache[key] = {
    value = value,
    timestamp = vim.loop.now(),
  }
  
  -- Evict oldest if over limit
  while #cache_order > max_cache_size do
    local oldest_key = table.remove(cache_order, 1)
    memory_cache[oldest_key] = nil
  end
end
```

### Efficient String Operations

```lua
-- String utilities for performance
local M = {}

-- Pre-compile commonly used patterns
local patterns = {
  whitespace = vim.regex("\\s\\+"),
  word = vim.regex("\\w\\+"),
  number = vim.regex("\\d\\+"),
}

---Efficient string splitting
---@param str string
---@param delimiter string
---@return string[]
function M.split_fast(str, delimiter)
  if delimiter == "" then
    return { str }
  end
  
  local result = {}
  local start = 1
  
  while true do
    local pos = str:find(delimiter, start, true)
    if not pos then
      table.insert(result, str:sub(start))
      break
    end
    
    table.insert(result, str:sub(start, pos - 1))
    start = pos + #delimiter
  end
  
  return result
end

---Efficient string joining
---@param parts string[]
---@param separator? string
---@return string
function M.join_fast(parts, separator)
  separator = separator or ""
  
  if #parts == 0 then
    return ""
  elseif #parts == 1 then
    return parts[1]
  end
  
  -- Use table.concat for efficiency
  return table.concat(parts, separator)
end

---Pattern matching with caching
---@param str string
---@param pattern_name string
---@return string[]
function M.match_cached(str, pattern_name)
  local pattern = patterns[pattern_name]
  if not pattern then
    error("Unknown pattern: " .. pattern_name)
  end
  
  local matches = {}
  local start = 0
  
  while true do
    local match_start, match_end = pattern:match_str(str, start)
    if not match_start then
      break
    end
    
    table.insert(matches, str:sub(match_start + 1, match_end))
    start = match_end
  end
  
  return matches
end
```

## Memory Management

### Weak References for Large Objects

```lua
-- Weak reference system for memory-sensitive objects
local M = {}

---@type table<string, table>
local weak_cache = setmetatable({}, { __mode = "v" })

---Store object with weak reference
---@param key string
---@param obj table
function M.store_weak(key, obj)
  weak_cache[key] = obj
end

---Get weakly referenced object
---@param key string
---@return table?
function M.get_weak(key)
  return weak_cache[key]
end

---Create weak reference callback
---@param obj table
---@return fun(): table?
function M.weak_ref(obj)
  local weak_table = setmetatable({ obj }, { __mode = "v" })
  return function()
    return weak_table[1]
  end
end
```

### Resource Cleanup

```lua
-- Automatic resource cleanup
local M = {}

---@type table<string, {cleanup: function, refs: number}>
local resources = {}

---Register resource for automatic cleanup
---@param id string Resource identifier
---@param cleanup_fn function Cleanup function
---@return string id Resource ID for reference counting
function M.register_resource(id, cleanup_fn)
  if not resources[id] then
    resources[id] = {
      cleanup = cleanup_fn,
      refs = 0,
    }
  end
  
  resources[id].refs = resources[id].refs + 1
  return id
end

---Release resource reference
---@param id string Resource ID
function M.release_resource(id)
  local resource = resources[id]
  if not resource then
    return
  end
  
  resource.refs = resource.refs - 1
  
  if resource.refs <= 0 then
    resource.cleanup()
    resources[id] = nil
  end
end

---Cleanup all resources
function M.cleanup_all()
  for id, resource in pairs(resources) do
    resource.cleanup()
  end
  resources = {}
end

-- Cleanup on plugin disable/exit
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = M.cleanup_all,
})
```

### Memory-Conscious Data Structures

```lua
-- Circular buffer for memory-bounded collections
---@class CircularBuffer
---@field data table
---@field size number
---@field head number
---@field tail number
---@field count number
local CircularBuffer = {}
CircularBuffer.__index = CircularBuffer

---Create new circular buffer
---@param size number Maximum buffer size
---@return CircularBuffer
function CircularBuffer.new(size)
  return setmetatable({
    data = {},
    size = size,
    head = 1,
    tail = 1,
    count = 0,
  }, CircularBuffer)
end

---Add item to buffer
---@param item any
function CircularBuffer:push(item)
  self.data[self.tail] = item
  self.tail = (self.tail % self.size) + 1
  
  if self.count < self.size then
    self.count = self.count + 1
  else
    self.head = (self.head % self.size) + 1
  end
end

---Get all items in order
---@return table
function CircularBuffer:to_array()
  local result = {}
  local current = self.head
  
  for i = 1, self.count do
    table.insert(result, self.data[current])
    current = (current % self.size) + 1
  end
  
  return result
end
```

## Asynchronous Operations

### Job Queue for Background Tasks

```lua
-- Efficient job queue for background processing
local M = {}

---@type table[]
local job_queue = {}
local processing = false
local max_concurrent = 3
local active_jobs = 0

---Add job to queue
---@param job_fn function Job function
---@param callback? function Completion callback
function M.queue_job(job_fn, callback)
  table.insert(job_queue, {
    fn = job_fn,
    callback = callback,
    id = tostring(math.random(1000000)),
  })
  
  M.process_queue()
end

---Process job queue
function M.process_queue()
  if processing or active_jobs >= max_concurrent or #job_queue == 0 then
    return
  end
  
  processing = true
  
  while #job_queue > 0 and active_jobs < max_concurrent do
    local job = table.remove(job_queue, 1)
    active_jobs = active_jobs + 1
    
    -- Run job in background
    vim.loop.new_work(job.fn, function(result)
      active_jobs = active_jobs - 1
      
      -- Schedule callback on main thread
      if job.callback then
        vim.schedule(function()
          job.callback(result)
        end)
      end
      
      -- Continue processing queue
      vim.schedule(M.process_queue)
    end)
  end
  
  processing = false
end
```

### Efficient File Operations

```lua
-- Async file operations with caching
local M = {}

---@type table<string, {content: string, mtime: number}>
local file_cache = {}

---Read file with caching
---@param filepath string
---@param callback function
function M.read_file_async(filepath, callback)
  -- Check cache first
  local stat = vim.loop.fs_stat(filepath)
  if not stat then
    callback(nil, "File not found: " .. filepath)
    return
  end
  
  local cached = file_cache[filepath]
  if cached and cached.mtime >= stat.mtime.sec then
    callback(cached.content)
    return
  end
  
  -- Read file asynchronously
  vim.loop.fs_open(filepath, "r", 438, function(err, fd)
    if err then
      callback(nil, err)
      return
    end
    
    vim.loop.fs_fstat(fd, function(err, stat)
      if err then
        vim.loop.fs_close(fd)
        callback(nil, err)
        return
      end
      
      vim.loop.fs_read(fd, stat.size, 0, function(err, data)
        vim.loop.fs_close(fd)
        
        if err then
          callback(nil, err)
          return
        end
        
        -- Cache result
        file_cache[filepath] = {
          content = data,
          mtime = stat.mtime.sec,
        }
        
        callback(data)
      end)
    end)
  end)
end
```

## Profiling and Monitoring

### Performance Monitoring

```lua
-- Built-in performance monitoring
local M = {}

local stats = {
  function_calls = {},
  total_time = 0,
  memory_usage = {},
}

---Instrument function for performance monitoring
---@param fn function
---@param name string Function name for stats
---@return function instrumented_fn
function M.instrument(fn, name)
  return function(...)
    local start_time = vim.loop.hrtime()
    local start_memory = collectgarbage("count")
    
    -- Execute function
    local results = { pcall(fn, ...) }
    local success = table.remove(results, 1)
    
    -- Record stats
    local end_time = vim.loop.hrtime()
    local end_memory = collectgarbage("count")
    local duration = (end_time - start_time) / 1e6 -- Convert to milliseconds
    
    if not stats.function_calls[name] then
      stats.function_calls[name] = { count = 0, total_time = 0 }
    end
    
    stats.function_calls[name].count = stats.function_calls[name].count + 1
    stats.function_calls[name].total_time = stats.function_calls[name].total_time + duration
    stats.total_time = stats.total_time + duration
    
    -- Track memory usage
    table.insert(stats.memory_usage, {
      timestamp = os.time(),
      memory = end_memory,
    })
    
    -- Keep only recent memory samples
    if #stats.memory_usage > 100 then
      table.remove(stats.memory_usage, 1)
    end
    
    if success then
      return unpack(results)
    else
      error(results[1])
    end
  end
end

---Get performance statistics
---@return table stats
function M.get_stats()
  local result = {
    total_time = stats.total_time,
    memory_current = collectgarbage("count"),
    functions = {},
  }
  
  for name, data in pairs(stats.function_calls) do
    result.functions[name] = {
      calls = data.count,
      total_time = data.total_time,
      avg_time = data.total_time / data.count,
    }
  end
  
  return result
end
```

## Best Practices Summary

### 1. Startup Performance
- **Lazy loading**: Defer module loading until actually needed
- **Event-driven initialization**: Load features based on Neovim events
- **Conditional loading**: Only load integrations when dependencies are available

### 2. Runtime Efficiency
- **Throttling/Debouncing**: Rate-limit high-frequency operations
- **Smart caching**: Cache expensive computations with proper invalidation
- **Efficient algorithms**: Use appropriate data structures and algorithms

### 3. Memory Management
- **Weak references**: Prevent memory leaks with large objects
- **Resource cleanup**: Properly cleanup timers, autocmds, and other resources
- **Bounded collections**: Use circular buffers for memory-bounded data

### 4. Async Operations
- **Background processing**: Use job queues for CPU-intensive tasks
- **Non-blocking I/O**: Perform file operations asynchronously
- **Proper scheduling**: Use vim.schedule() for UI operations

### 5. Monitoring
- **Performance instrumentation**: Track function execution times
- **Memory monitoring**: Monitor memory usage patterns
- **Profiling tools**: Provide built-in profiling capabilities

These performance optimization patterns ensure efficient, responsive, and memory-conscious plugins that scale well with usage.