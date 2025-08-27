# Nexus.nvim Performance Optimization Checklist

## 🎯 Core Performance Principles

### 1. Lazy Loading Strategy
Lazy loading is critical - plugins should only load when actually needed, using events, commands, filetypes, and key mappings as triggers

```lua
-- ✅ GOOD: Lazy load on specific events
return {
  "nexus.nvim",
  event = { "VimEnter", "BufReadPost" },  -- Only load after startup
  cmd = { "Nexus", "NexusRefresh" },      -- Load when commands are used
  keys = { "<leader>n" },                  -- Load on keymap trigger
}

-- ❌ BAD: Loading everything on startup
require('nexus').setup() -- This loads everything immediately
```

### 2. Module Structure & Lazy Loading
Lua modules are cached after first require(), but initial loading can be expensive

```lua
-- ✅ GOOD: Split into small, lazy-loadable modules
-- nexus/init.lua
local M = {}
M.linear = nil  -- Don't load until needed

function M.get_linear()
  if not M.linear then
    M.linear = require('nexus.integrations.linear')
  end
  return M.linear
end

-- ❌ BAD: Loading all modules upfront
local linear = require('nexus.integrations.linear')
local github = require('nexus.integrations.github')
local jira = require('nexus.integrations.jira')
```

## 🚀 Startup Optimization

### 3. Defer Non-Critical Operations
Use vim.defer_fn and vim.schedule to avoid blocking startup

```lua
-- ✅ GOOD: Defer expensive operations
function M.setup(opts)
  -- Critical setup only
  M.config = opts
  
  -- Defer non-critical operations
  vim.defer_fn(function()
    M.load_cache()
    M.check_linear_api()
  end, 100)  -- Load after 100ms
end

-- ❌ BAD: Blocking startup with expensive operations
function M.setup(opts)
  M.config = opts
  M.load_cache()        -- Blocks startup
  M.check_linear_api()  -- Blocks startup
  M.fetch_git_status()  -- Blocks startup
end
```

### 4. Measure & Profile Performance
Use nvim --startuptime and profiling tools to identify bottlenecks

```lua
-- Add profiling helper
local function profile(name, fn)
  local start = vim.loop.hrtime()
  local result = fn()
  local duration = (vim.loop.hrtime() - start) / 1000000  -- Convert to ms
  if duration > 10 then  -- Log if > 10ms
    vim.notify(string.format("Nexus: %s took %.2fms", name, duration))
  end
  return result
end

-- Use it to identify slow operations
local git_status = profile("git_status", function()
  return M.get_git_status()
end)
```

## 💾 State Management & Caching

### 5. Implement Smart Caching
Cache expensive operations and invalidate intelligently

```lua
-- ✅ GOOD: Multi-level cache with TTL
local cache = {
  git = {
    status = nil,
    commits = nil,
    last_updated = 0,
    ttl = 30000  -- 30 seconds in ms
  },
  linear = {
    issues = nil,
    last_updated = 0,
    ttl = 300000  -- 5 minutes in ms
  }
}

function M.get_git_status()
  local now = vim.loop.now()
  if cache.git.status and (now - cache.git.last_updated) < cache.git.ttl then
    return cache.git.status  -- Return cached data
  end
  
  -- Fetch new data
  cache.git.status = M.fetch_git_status_async()
  cache.git.last_updated = now
  return cache.git.status
end

-- ❌ BAD: No caching, fetching every time
function M.get_git_status()
  return vim.fn.system('git status --porcelain')  -- Expensive every time
end
```

### 6. Use Weak Tables for Memory Management
Lua garbage collection and proper memory management are crucial

```lua
-- ✅ GOOD: Use weak references for large temporary data
local file_cache = setmetatable({}, {
  __mode = 'v'  -- Weak values, allows GC to clean up
})

-- ✅ GOOD: Clear large data when not needed
function M.clear_cache()
  cache.linear.issues = nil
  collectgarbage('collect')  -- Force GC if needed
end
```

## ⚡ Git Operations Optimization

### 7. Use libgit2 or Async Git Operations
libgit2-based plugins like fugit2.nvim show significant performance improvements over shell git commands

```lua
-- ✅ GOOD: Async git operations with vim.loop
function M.get_git_status_async(callback)
  vim.loop.new_work(
    function()
      -- This runs in a separate thread
      local handle = io.popen('git status --porcelain=v2 2>/dev/null')
      local result = handle:read('*a')
      handle:close()
      return result
    end,
    function(result)
      -- This runs in main thread
      cache.git.status = M.parse_git_status(result)
      callback(cache.git.status)
    end
  ):queue()
end

-- ❌ BAD: Blocking git operations
function M.get_git_status()
  return vim.fn.system('git status --porcelain')  -- Blocks UI
end
```

### 8. Batch Git Operations
```lua
-- ✅ GOOD: Single git command for multiple operations
function M.get_git_info()
  local cmd = [[
    git status --porcelain=v2 --branch &&
    echo "---SEPARATOR---" &&
    git log --oneline -5
  ]]
  local output = vim.fn.system(cmd)
  local parts = vim.split(output, "---SEPARATOR---")
  return {
    status = parts[1],
    commits = parts[2]
  }
end

-- ❌ BAD: Multiple git calls
function M.get_git_info()
  local status = vim.fn.system('git status')
  local commits = vim.fn.system('git log')
  local branch = vim.fn.system('git branch')
  -- Each call spawns a new process
end
```

## 🌐 Linear API Optimization

### 9. Implement Request Debouncing & Throttling
```lua
-- ✅ GOOD: Debounce rapid refresh requests
local pending_refresh = nil

function M.refresh_linear_debounced()
  if pending_refresh then
    vim.fn.timer_stop(pending_refresh)
  end
  
  pending_refresh = vim.fn.timer_start(500, function()
    M.refresh_linear()
    pending_refresh = nil
  end)
end
```

### 10. Progressive Loading & Rendering
```lua
-- ✅ GOOD: Show what's ready immediately
function M.render()
  -- Render immediately with cached data
  M.render_header()
  M.render_git_status(cache.git.status or { loading = true })
  
  -- Fetch and update async
  M.get_git_status_async(function(status)
    M.render_git_status(status)
  end)
  
  M.get_linear_issues_async(function(issues)
    M.render_linear_section(issues)
  end)
end

-- ❌ BAD: Wait for everything before rendering
function M.render()
  local git_status = M.get_git_status()  -- Blocks
  local linear_issues = M.get_linear_issues()  -- Blocks
  M.render_all(git_status, linear_issues)
end
```

### 11. GraphQL Query Optimization for Linear
```lua
-- ✅ GOOD: Request only needed fields
local query = [[
  query {
    issues(first: 5, filter: { assignee: { id: { eq: "%s" } } }) {
      nodes {
        id
        title
        state { name }
        priority
      }
    }
  }
]]

-- ❌ BAD: Requesting all fields
local query = [[
  query {
    issues {
      nodes {
        *  -- Getting everything is slow
      }
    }
  }
]]
```

## 🔧 Advanced Optimizations

### 12. Use vim.loop for True Async Operations
Neovim's vim.uv (vim.loop) allows true async operations and threading

```lua
-- ✅ GOOD: Non-blocking file operations
function M.read_cache_async(callback)
  local path = vim.fn.stdpath('cache') .. '/nexus.json'
  
  vim.loop.fs_open(path, 'r', 438, function(err, fd)
    if err then callback(nil) return end
    
    vim.loop.fs_fstat(fd, function(err, stat)
      if err then callback(nil) return end
      
      vim.loop.fs_read(fd, stat.size, 0, function(err, data)
        vim.loop.fs_close(fd)
        if err then callback(nil) return end
        
        local ok, decoded = pcall(vim.json.decode, data)
        callback(ok and decoded or nil)
      end)
    end)
  end)
end
```

### 13. Optimize Render Operations
```lua
-- ✅ GOOD: Batch buffer updates
function M.render_to_buffer(buf, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)  -- Single update
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
end

-- ❌ BAD: Multiple buffer updates
function M.render_to_buffer(buf, lines)
  for i, line in ipairs(lines) do
    vim.api.nvim_buf_set_lines(buf, i-1, i, false, {line})  -- Many updates
  end
end
```

### 14. Smart Differential Updates
```lua
-- ✅ GOOD: Only update changed sections
function M.update_git_status(new_status)
  local old_status = cache.git.status
  
  if vim.deep_equal(old_status, new_status) then
    return  -- No changes, skip render
  end
  
  -- Find which lines changed
  local changed_lines = M.diff_status(old_status, new_status)
  
  -- Update only changed lines
  for _, line_info in ipairs(changed_lines) do
    M.update_buffer_line(line_info.num, line_info.content)
  end
  
  cache.git.status = new_status
end
```

### 15. Implement Background Refresh
```lua
-- ✅ GOOD: Background refresh without blocking
local refresh_timer = nil

function M.start_background_refresh()
  refresh_timer = vim.loop.new_timer()
  refresh_timer:start(0, 30000, vim.schedule_wrap(function()
    -- Refresh git status (fast operation)
    M.refresh_git_cached()
    
    -- Refresh Linear less frequently
    if os.time() - cache.linear.last_updated > 300 then
      M.refresh_linear_cached()
    end
  end))
end

function M.stop_background_refresh()
  if refresh_timer then
    refresh_timer:stop()
    refresh_timer:close()
  end
end
```

## 📊 Performance Monitoring

### 16. Add Performance Metrics
```lua
-- Track performance metrics
local metrics = {
  startup_time = nil,
  render_times = {},
  api_call_times = {},
  cache_hits = 0,
  cache_misses = 0
}

function M.log_metric(category, name, duration)
  if not metrics[category] then
    metrics[category] = {}
  end
  table.insert(metrics[category], {
    name = name,
    duration = duration,
    timestamp = os.time()
  })
end

-- Command to view metrics
vim.api.nvim_create_user_command('NexusMetrics', function()
  vim.print(metrics)
end, {})
```

## 🔍 Testing Performance

### 17. Performance Test Suite
```lua
-- Create performance benchmarks
local function benchmark_startup()
  local times = {}
  for i = 1, 10 do
    local start = vim.loop.hrtime()
    require('nexus').setup({})
    require('nexus').render()
    times[i] = (vim.loop.hrtime() - start) / 1000000
    package.loaded['nexus'] = nil  -- Reset
  end
  
  local avg = vim.fn.reduce(times, function(acc, val) 
    return acc + val 
  end) / #times
  
  print(string.format("Average startup: %.2fms", avg))
end
```

## ✅ Implementation Priority

1. **Critical (Week 1)**
   - [ ] Implement lazy loading for Linear/git modules
   - [ ] Add basic caching with TTL
   - [ ] Make git operations async
   - [ ] Defer non-critical startup operations

2. **Important (Week 2)**
   - [ ] Implement progressive rendering
   - [ ] Add request debouncing
   - [ ] Optimize GraphQL queries
   - [ ] Batch git operations

3. **Nice to Have (Week 3+)**
   - [ ] Add differential updates
   - [ ] Implement background refresh
   - [ ] Add performance metrics
   - [ ] Create benchmark suite

## 🎯 Performance Targets

Based on typical Neovim plugin performance benchmarks:

- **Startup time**: < 10ms for initial load
- **Full render**: < 50ms with cache, < 200ms without
- **Git operations**: < 30ms for status, < 50ms for commits
- **Linear API**: < 100ms with cache, < 500ms fresh fetch
- **Memory usage**: < 5MB for cache, < 10MB total
- **Refresh rate**: 30s for git, 5 min for Linear

## 🐛 Common Performance Pitfalls to Avoid

1. **Don't use vim.fn.system() in hot paths** - it blocks
2. **Don't parse git output on every render** - cache parsed data
3. **Don't fetch all Linear issues** - paginate and limit
4. **Don't render invisible content** - virtual text and folds
5. **Don't update buffer line-by-line** - batch updates
6. **Don't ignore garbage collection** - clean up large tables
7. **Don't make synchronous HTTP requests** - always async
8. **Don't re-parse unchanged data** - check timestamps

Remember: Even small optimizations like reusing validation tables can provide 100x performance improvements in hot code paths.
