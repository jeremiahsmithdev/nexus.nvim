-- Module registry for performance optimization
-- Caches frequently used modules to avoid repeated require() calls
local M = {}

-- Module cache
local module_cache = {}

-- Performance tracking
local stats = {
  cache_hits = 0,
  cache_misses = 0,
  cached_modules = 0
}

-- Commonly used modules that benefit from caching
local CACHEABLE_MODULES = {
  'nexus.config',
  'nexus.logger',
  'nexus.render',
  'nexus.keymaps',
  'nexus.buffer',
  'nexus.state.git',
  'nexus.state.ui',
  'nexus.git.utils',
  'nexus.git.status',
  'nexus.ui.logo',
  'nexus.actions',
  'nexus.render.components.sections',
  'nexus.render.layout',
  'nexus.ui.center'
}

-- Get a module from cache or require it
function M.get(module_name)
  -- Check if module is in cache
  if module_cache[module_name] then
    stats.cache_hits = stats.cache_hits + 1
    return module_cache[module_name]
  end

  -- Module not cached, require it
  stats.cache_misses = stats.cache_misses + 1
  local module = require(module_name)

  -- Cache commonly used modules
  if vim.tbl_contains(CACHEABLE_MODULES, module_name) then
    module_cache[module_name] = module
    stats.cached_modules = stats.cached_modules + 1
  end

  return module
end

-- Require function replacement for performance-critical paths
function M.require(module_name)
  return M.get(module_name)
end

-- Pre-cache commonly used modules
function M.precache_common_modules()
  for _, module_name in ipairs(CACHEABLE_MODULES) do
    if not module_cache[module_name] then
      local success, module = pcall(require, module_name)
      if success then
        module_cache[module_name] = module
        stats.cached_modules = stats.cached_modules + 1
      end
    end
  end
end

-- Get cache statistics
function M.get_stats()
  return {
    cache_hits = stats.cache_hits,
    cache_misses = stats.cache_misses,
    cached_modules = stats.cached_modules,
    cache_hit_ratio = stats.cache_hits / (stats.cache_hits + stats.cache_misses + 0.001) -- avoid division by zero
  }
end

-- Clear the module cache (for testing or memory cleanup)
function M.clear_cache()
  module_cache = {}
  stats.cached_modules = 0
end

-- Get list of cached modules
function M.get_cached_modules()
  return vim.tbl_keys(module_cache)
end

-- Initialize the registry.
--
-- We intentionally do NOT eagerly precache here. Lua's `require` already
-- memoizes modules in package.loaded, and M.get() caches on first access, so
-- the modules load exactly once when render first needs them. Eagerly loading
-- the full CACHEABLE_MODULES list right after VimEnter only front-loaded ~12
-- module chunk-evaluations onto the startup path for no benefit (the cache has
-- no eager consumers). Call M.precache_common_modules() explicitly if a warm
-- cache is ever needed.
function M.init()
end

return M