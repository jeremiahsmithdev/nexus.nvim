local M = {}

local state = require('nexus.state')

-- Default TTL values in seconds
local DEFAULT_TTL = {
  git_status = 30,    -- 30 seconds
  git_commits = 300,  -- 5 minutes
  ui_config = 60,     -- 1 minute
  buffer_info = 120   -- 2 minutes
}

-- Cache management functions

-- Set cache TTL for a specific cache type
function M.set_ttl(cache_type, ttl_seconds)
  local ttl_config = state.get('cache', 'ttl') or {}
  ttl_config[cache_type] = ttl_seconds
  state.set('cache', 'ttl', ttl_config)
  
  state.notify('cache', 'ttl_updated', {type = cache_type, ttl = ttl_seconds}, nil)
end

-- Get TTL for a cache type
function M.get_ttl(cache_type)
  local ttl_config = state.get('cache', 'ttl') or {}
  return ttl_config[cache_type] or DEFAULT_TTL[cache_type] or 60
end

-- Check if cache entry is valid (not expired)
function M.is_valid(cache_type)
  local timestamp_key = cache_type .. '_timestamp'
  local timestamp = state.get('cache', timestamp_key) or 0
  local current_time = os.time()
  local ttl = M.get_ttl(cache_type)
  
  return (current_time - timestamp) < ttl
end

-- Update cache timestamp for a type
function M.update_timestamp(cache_type)
  local timestamp_key = cache_type .. '_timestamp'
  local current_time = os.time()
  state.set('cache', timestamp_key, current_time)
  
  state.notify('cache', 'timestamp_updated', {type = cache_type, timestamp = current_time}, nil)
end

-- Get cache timestamp for a type
function M.get_timestamp(cache_type)
  local timestamp_key = cache_type .. '_timestamp'
  return state.get('cache', timestamp_key) or 0
end

-- Invalidate specific cache type
function M.invalidate(cache_type)
  local timestamp_key = cache_type .. '_timestamp'
  state.set('cache', timestamp_key, 0)
  
  state.notify('cache', 'invalidated', {type = cache_type}, nil)
end

-- Invalidate all caches
function M.invalidate_all()
  local cache_state = state.get('cache') or {}
  
  for key, _ in pairs(cache_state) do
    if key:match('_timestamp$') then
      state.set('cache', key, 0)
    end
  end
  
  state.notify('cache', 'all_invalidated', {}, nil)
end

-- Get cache statistics
function M.get_stats()
  local cache_state = state.get('cache') or {}
  local stats = {
    cache_types = {},
    total_entries = 0
  }
  
  for key, value in pairs(cache_state) do
    if key:match('_timestamp$') then
      local cache_type = key:gsub('_timestamp$', '')
      local current_time = os.time()
      local age = current_time - (value or 0)
      local ttl = M.get_ttl(cache_type)
      local is_valid = age < ttl
      
      stats.cache_types[cache_type] = {
        timestamp = value,
        age_seconds = age,
        ttl_seconds = ttl,
        is_valid = is_valid,
        expires_in = math.max(0, ttl - age)
      }
      
      stats.total_entries = stats.total_entries + 1
    end
  end
  
  return stats
end

-- Cache-aware get function
function M.get_cached(cache_type, refresh_func, ...)
  if M.is_valid(cache_type) then
    local data_key = cache_type .. '_data'
    local cached_data = state.get('cache', data_key)
    if cached_data then
      return cached_data
    end
  end
  
  -- Cache is invalid or missing, refresh data
  if refresh_func and type(refresh_func) == 'function' then
    local new_data = refresh_func(...)
    M.set_cached(cache_type, new_data)
    return new_data
  end
  
  return nil
end

-- Cache-aware set function
function M.set_cached(cache_type, data)
  local data_key = cache_type .. '_data'
  state.set('cache', data_key, data)
  M.update_timestamp(cache_type)
  
  state.notify('cache', 'data_updated', {type = cache_type, data = data}, nil)
end

-- Subscribe to cache changes
function M.subscribe_to_cache_changes(callback)
  return state.subscribe('cache', callback)
end

-- Clear expired cache entries
function M.cleanup_expired()
  local cache_state = state.get('cache') or {}
  local current_time = os.time()
  local cleaned = {}
  
  for key, value in pairs(cache_state) do
    if key:match('_timestamp$') then
      local cache_type = key:gsub('_timestamp$', '')
      local age = current_time - (value or 0)
      local ttl = M.get_ttl(cache_type)
      
      if age >= ttl then
        -- Mark expired entries for cleanup
        local data_key = cache_type .. '_data'
        state.set('cache', key, 0)
        state.set('cache', data_key, nil)
        table.insert(cleaned, cache_type)
      end
    end
  end
  
  if #cleaned > 0 then
    state.notify('cache', 'expired_cleaned', {cleaned = cleaned}, nil)
  end
  
  return cleaned
end

-- Initialize cache system
function M.init()
  -- Set default TTL values
  state.set('cache', 'ttl', DEFAULT_TTL)
  
  -- Initialize timestamps to 0 (expired)
  for cache_type, _ in pairs(DEFAULT_TTL) do
    local timestamp_key = cache_type .. '_timestamp'
    if not state.get('cache', timestamp_key) then
      state.set('cache', timestamp_key, 0)
    end
  end
  
  -- Start periodic cleanup timer (every 5 minutes) - DISABLED to prevent infinite loops
  -- if vim.fn.has('nvim-0.5') == 1 then
  --   vim.defer_fn(function()
  --     M.cleanup_expired()
  --     -- Schedule next cleanup - THIS CAUSED INFINITE LOOPS
  --     vim.defer_fn(M.cleanup_expired, 300000) -- 5 minutes
  --   end, 300000)
  -- end
end

return M