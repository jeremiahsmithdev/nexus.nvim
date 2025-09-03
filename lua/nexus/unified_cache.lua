local M = {}

local logger = require('nexus.logger')

-- Unified cache system combining memory and file-based caching
local memory_cache = {}
local cache_stats = {
  hits = 0,
  misses = 0,
  memory_entries = 0,
  file_entries = 0
}

-- Default TTL values in seconds
local DEFAULT_TTL = {
  git_status = 30,        -- 30 seconds - frequent changes
  git_commits = 300,      -- 5 minutes - less frequent
  git_repo_check = 5,     -- 5 seconds - very fast check
  linear_issues = 900,    -- 15 minutes - external API, slower to change
  linear_auth = 3600,     -- 1 hour - authentication info
  claude_conversations = 600, -- 10 minutes - moderate frequency
  ui_config = 60,         -- 1 minute - UI configuration
  buffer_info = 120       -- 2 minutes - buffer metadata
}

-- LRU cache implementation for memory management
local lru_order = {}
local max_memory_entries = 50

-- Get cache directory for current project
local function get_cache_dir()
  local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
  if vim.v.shell_error == 0 and git_root ~= '' then
    return git_root .. '/.nexus/cache'
  end
  return vim.fn.stdpath('cache') .. '/nexus'
end

-- Ensure cache directory exists
local function ensure_cache_dir()
  local cache_dir = get_cache_dir()
  if vim.fn.isdirectory(cache_dir) == 0 then
    vim.fn.mkdir(cache_dir, 'p')
  end
  return cache_dir
end

-- Update LRU order
local function update_lru(key)
  -- Remove if exists
  for i, k in ipairs(lru_order) do
    if k == key then
      table.remove(lru_order, i)
      break
    end
  end
  -- Add to front
  table.insert(lru_order, 1, key)
  
  -- Enforce max size
  while #lru_order > max_memory_entries do
    local evict_key = table.remove(lru_order)
    memory_cache[evict_key] = nil
    cache_stats.memory_entries = cache_stats.memory_entries - 1
    logger.debug('CACHE', 'Evicted from memory cache', { key = evict_key })
  end
end

-- Fast memory cache operations
function M.get_memory(key)
  local entry = memory_cache[key]
  if not entry then
    return nil
  end
  
  local current_time = os.time()
  if current_time - entry.timestamp > entry.ttl then
    memory_cache[key] = nil
    cache_stats.memory_entries = cache_stats.memory_entries - 1
    return nil
  end
  
  update_lru(key)
  cache_stats.hits = cache_stats.hits + 1
  return entry.data
end

function M.set_memory(key, data, ttl)
  ttl = ttl or DEFAULT_TTL[key] or 300
  
  memory_cache[key] = {
    data = data,
    timestamp = os.time(),
    ttl = ttl
  }
  
  update_lru(key)
  cache_stats.memory_entries = cache_stats.memory_entries + 1
  cache_stats.misses = cache_stats.misses + 1
  
  logger.debug('CACHE', 'Stored in memory cache', { key = key, ttl = ttl })
end

-- File-based cache for persistence
function M.get_file(key, ttl)
  ttl = ttl or DEFAULT_TTL[key] or 300
  local cache_file = ensure_cache_dir() .. '/' .. key .. '.json'
  
  -- Check if file exists
  if vim.fn.filereadable(cache_file) == 0 then
    return nil
  end
  
  -- Get file modification time
  local stat = vim.loop.fs_stat(cache_file)
  if not stat then
    return nil
  end
  
  -- Check TTL
  local age = os.time() - stat.mtime.sec
  if age >= ttl then
    os.remove(cache_file)
    return nil
  end
  
  -- Read and decode file
  local file = io.open(cache_file, 'r')
  if not file then
    return nil
  end
  
  local content = file:read('*a')
  file:close()
  
  if content == '' then
    return nil
  end
  
  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    logger.warn('CACHE', 'Failed to decode cache file', { file = cache_file, error = data })
    os.remove(cache_file)
    return nil
  end
  
  cache_stats.hits = cache_stats.hits + 1
  return data
end

function M.set_file(key, data)
  if not data then
    return false
  end
  
  local cache_file = ensure_cache_dir() .. '/' .. key .. '.json'
  local file = io.open(cache_file, 'w')
  if not file then
    logger.error('CACHE', 'Failed to open cache file for writing', { file = cache_file })
    return false
  end
  
  local ok, json = pcall(vim.json.encode, data)
  if not ok then
    logger.error('CACHE', 'Failed to encode data for cache', { key = key, error = json })
    file:close()
    return false
  end
  
  file:write(json)
  file:close()
  
  cache_stats.file_entries = cache_stats.file_entries + 1
  cache_stats.misses = cache_stats.misses + 1
  
  logger.debug('CACHE', 'Stored in file cache', { key = key, file = cache_file })
  return true
end

-- Unified cache interface
function M.get(key, ttl)
  -- Try memory cache first (fastest)
  local data = M.get_memory(key)
  if data then
    return data
  end
  
  -- Try file cache second
  data = M.get_file(key, ttl)
  if data then
    -- Promote to memory cache for faster future access
    M.set_memory(key, data, ttl)
    return data
  end
  
  cache_stats.misses = cache_stats.misses + 1
  return nil
end

function M.set(key, data, ttl)
  if not data then
    return false
  end
  
  -- Store in both memory and file cache
  M.set_memory(key, data, ttl)
  return M.set_file(key, data)
end

-- Get cached data or compute and cache it
function M.get_or_set(key, compute_fn, ttl)
  local cached = M.get(key, ttl)
  if cached then
    logger.debug('CACHE', 'Cache hit', { key = key })
    return cached
  end
  
  logger.debug('CACHE', 'Cache miss - computing', { key = key })
  local data = compute_fn()
  if data then
    M.set(key, data, ttl)
  end
  
  return data
end

-- Invalidate cache entries
function M.invalidate(key)
  -- Remove from memory
  memory_cache[key] = nil
  for i, k in ipairs(lru_order) do
    if k == key then
      table.remove(lru_order, i)
      break
    end
  end
  
  -- Remove from file
  local cache_file = get_cache_dir() .. '/' .. key .. '.json'
  if vim.fn.filereadable(cache_file) == 1 then
    os.remove(cache_file)
  end
  
  logger.debug('CACHE', 'Cache invalidated', { key = key })
end

function M.invalidate_all()
  -- Clear memory cache
  memory_cache = {}
  lru_order = {}
  cache_stats.memory_entries = 0
  
  -- Clear file cache
  local cache_dir = get_cache_dir()
  if vim.fn.isdirectory(cache_dir) == 1 then
    local files = vim.fn.glob(cache_dir .. '/*.json', false, true)
    for _, file in ipairs(files) do
      os.remove(file)
    end
    cache_stats.file_entries = 0
    logger.info('CACHE', 'All cache entries invalidated', { count = #files })
  end
end

-- Clean up expired entries
function M.cleanup_expired()
  local current_time = os.time()
  local cleaned_memory = 0
  local cleaned_files = 0
  
  -- Clean memory cache
  for key, entry in pairs(memory_cache) do
    if current_time - entry.timestamp >= entry.ttl then
      memory_cache[key] = nil
      cleaned_memory = cleaned_memory + 1
    end
  end
  
  -- Clean file cache
  local cache_dir = get_cache_dir()
  if vim.fn.isdirectory(cache_dir) == 1 then
    local files = vim.fn.glob(cache_dir .. '/*.json', false, true)
    
    for _, file in ipairs(files) do
      local key = vim.fn.fnamemodify(file, ':t:r')
      local ttl = DEFAULT_TTL[key] or 300
      
      local stat = vim.loop.fs_stat(file)
      if stat then
        local age = current_time - stat.mtime.sec
        if age >= ttl then
          os.remove(file)
          cleaned_files = cleaned_files + 1
        end
      end
    end
  end
  
  if cleaned_memory > 0 or cleaned_files > 0 then
    logger.info('CACHE', 'Cleaned up expired cache entries', { 
      memory = cleaned_memory, 
      files = cleaned_files 
    })
  end
  
  return cleaned_memory + cleaned_files
end

-- Get cache statistics
function M.get_stats()
  local cache_dir = get_cache_dir()
  local stats = {
    cache_dir = cache_dir,
    memory = {
      entries = cache_stats.memory_entries,
      max_entries = max_memory_entries,
      lru_order = #lru_order
    },
    file = {
      entries = cache_stats.file_entries,
      directory_exists = vim.fn.isdirectory(cache_dir) == 1
    },
    performance = {
      hits = cache_stats.hits,
      misses = cache_stats.misses,
      hit_rate = cache_stats.hits > 0 and (cache_stats.hits / (cache_stats.hits + cache_stats.misses)) * 100 or 0
    },
    ttl_config = DEFAULT_TTL
  }
  
  return stats
end

-- Create cache key for git repository
function M.get_git_cache_key(suffix)
  local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
  if vim.v.shell_error == 0 and git_root ~= '' then
    local repo_name = git_root:match('([^/]+)$')
    return 'git_' .. repo_name .. '_' .. suffix
  end
  return 'git_' .. suffix
end

-- Initialize cache system
function M.init()
  -- Reset stats
  cache_stats = {
    hits = 0,
    misses = 0,
    memory_entries = 0,
    file_entries = 0
  }
  
  -- Ensure cache directory exists
  ensure_cache_dir()
  
  -- Schedule periodic cleanup (every 5 minutes)
  if vim.fn.has('nvim-0.5') == 1 then
    local function schedule_cleanup()
      M.cleanup_expired()
      vim.defer_fn(schedule_cleanup, 300000) -- 5 minutes
    end
    vim.defer_fn(schedule_cleanup, 300000)
  end
  
  logger.debug('CACHE', 'Unified cache system initialized')
end

return M