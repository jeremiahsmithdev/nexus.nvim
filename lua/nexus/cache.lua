local M = {}

local logger = require('nexus.logger')
local git_root_mod = require('nexus.git.root')

-- Get cache directory for current project
local function get_cache_dir()
  local git_root = git_root_mod.get()
  if git_root then
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

-- Get cache file path for a specific key
local function get_cache_file(key)
  local cache_dir = ensure_cache_dir()
  return cache_dir .. '/' .. key .. '.json'
end

-- Default TTL values in seconds
local DEFAULT_TTL = {
  git_status = 30,     -- 30 seconds - frequent changes
  git_commits = 300,   -- 5 minutes - less frequent
  linear_issues = 900, -- 15 minutes - external API, slower to change
  linear_auth = 3600,  -- 1 hour - authentication info
  claude_conversations = 600, -- 10 minutes - moderate frequency
}

-- Check if cache entry exists and is valid
function M.is_valid(key, custom_ttl)
  local cache_file = get_cache_file(key)
  
  -- Check if file exists
  if vim.fn.filereadable(cache_file) == 0 then
    return false
  end
  
  -- Get file modification time
  local stat = vim.loop.fs_stat(cache_file)
  if not stat then
    return false
  end
  
  -- Check TTL
  local ttl = custom_ttl or DEFAULT_TTL[key] or 300 -- 5 min default
  local age = os.time() - stat.mtime.sec
  
  return age < ttl
end

-- Get cached data if valid
function M.get(key, custom_ttl)
  if not M.is_valid(key, custom_ttl) then
    return nil
  end
  
  local cache_file = get_cache_file(key)
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
    -- Remove corrupted cache file
    os.remove(cache_file)
    return nil
  end
  
  return data
end

-- Set cached data
function M.set(key, data)
  if not data then
    return false
  end
  
  local cache_file = get_cache_file(key)
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
  
  logger.debug('CACHE', 'Cached data written', { key = key, file = cache_file })
  return true
end

-- Get cached data or compute and cache it
function M.get_or_set(key, compute_fn, custom_ttl)
  local cached = M.get(key, custom_ttl)
  if cached then
    logger.debug('CACHE', 'Cache hit', { key = key })
    return cached
  end
  
  logger.debug('CACHE', 'Cache miss - computing', { key = key })
  local data = compute_fn()
  if data then
    M.set(key, data)
  end
  
  return data
end

-- Invalidate specific cache entry
function M.invalidate(key)
  local cache_file = get_cache_file(key)
  if vim.fn.filereadable(cache_file) == 1 then
    os.remove(cache_file)
    logger.debug('CACHE', 'Cache invalidated', { key = key })
  end
end

-- Invalidate all cache entries
function M.invalidate_all()
  local cache_dir = get_cache_dir()
  if vim.fn.isdirectory(cache_dir) == 1 then
    local files = vim.fn.glob(cache_dir .. '/*.json', false, true)
    for _, file in ipairs(files) do
      os.remove(file)
    end
    logger.info('CACHE', 'All cache entries invalidated', { count = #files })
  end
end

-- Clean up expired cache entries
function M.cleanup_expired()
  local cache_dir = get_cache_dir()
  if vim.fn.isdirectory(cache_dir) == 0 then
    return 0
  end
  
  local files = vim.fn.glob(cache_dir .. '/*.json', false, true)
  local cleaned = 0
  
  for _, file in ipairs(files) do
    local key = vim.fn.fnamemodify(file, ':t:r') -- Get filename without extension
    if not M.is_valid(key) then
      os.remove(file)
      cleaned = cleaned + 1
    end
  end
  
  if cleaned > 0 then
    logger.info('CACHE', 'Cleaned up expired cache entries', { count = cleaned })
  end
  
  return cleaned
end

-- Get cache statistics
function M.get_stats()
  local cache_dir = get_cache_dir()
  local stats = {
    cache_dir = cache_dir,
    entries = {},
    total_files = 0,
    total_size = 0,
  }
  
  if vim.fn.isdirectory(cache_dir) == 0 then
    return stats
  end
  
  local files = vim.fn.glob(cache_dir .. '/*.json', false, true)
  stats.total_files = #files
  
  for _, file in ipairs(files) do
    local key = vim.fn.fnamemodify(file, ':t:r')
    local stat = vim.loop.fs_stat(file)
    
    if stat then
      local age = os.time() - stat.mtime.sec
      local ttl = DEFAULT_TTL[key] or 300
      local is_valid = age < ttl
      
      stats.entries[key] = {
        file = file,
        size = stat.size,
        age_seconds = age,
        ttl_seconds = ttl,
        is_valid = is_valid,
        expires_in = math.max(0, ttl - age)
      }
      
      stats.total_size = stats.total_size + stat.size
    end
  end
  
  return stats
end

-- Create cache key for git repository
function M.get_git_cache_key(suffix)
  local git_root = git_root_mod.get()
  if git_root then
    local repo_name = git_root:match('([^/]+)$')
    return 'git_' .. repo_name .. '_' .. suffix
  end
  return 'git_' .. suffix
end

return M