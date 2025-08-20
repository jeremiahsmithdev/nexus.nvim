local M = {}

local state = require('nexus.state')
local git_utils = require('nexus.git.utils')
local git_status = require('nexus.git.status')
local git_commits = require('nexus.git.commits')

-- Git state management
function M.update_git_repository_info()
  local is_git_repo = git_utils.is_git_repo()
  local git_root = git_utils.get_git_root()
  
  state.update('git', {
    is_git_repo = is_git_repo,
    git_root = git_root
  })
  
  return is_git_repo
end

-- Update git status in state
function M.update_git_status(force_refresh)
  local cache = state.get('cache')
  local current_time = os.time()
  
  -- Check if we need to refresh based on TTL
  local should_refresh = force_refresh or 
    (current_time - (cache.git_status_timestamp or 0)) > (cache.ttl.git_status or 30)
  
  if not should_refresh then
    return state.get('git', 'files') or {}
  end
  
  local is_git_repo = state.get('git', 'is_git_repo')
  if not is_git_repo then
    M.update_git_repository_info()
    is_git_repo = state.get('git', 'is_git_repo')
  end
  
  if is_git_repo then
    local files = git_status.parse_git_status()
    state.set('git', 'files', files)
    state.set('cache', 'git_status_timestamp', current_time)
    
    -- Emit event for reactive updates
    state.notify('git', 'status_updated', files, state.get('git', 'files'))
  else
    state.set('git', 'files', {})
  end
  
  return state.get('git', 'files') or {}
end

-- Update git commits in state
function M.update_git_commits(config, force_refresh)
  local cache = state.get('cache')
  local current_time = os.time()
  
  -- Check if we need to refresh based on TTL
  local should_refresh = force_refresh or 
    (current_time - (cache.git_commits_timestamp or 0)) > (cache.ttl.git_commits or 300)
  
  if not should_refresh then
    return state.get('git', 'commits') or {}
  end
  
  local is_git_repo = state.get('git', 'is_git_repo')
  if not is_git_repo then
    M.update_git_repository_info()
    is_git_repo = state.get('git', 'is_git_repo')
  end
  
  if is_git_repo then
    local commits = git_commits.get_git_log(config or {})
    state.set('git', 'commits', commits)
    state.set('cache', 'git_commits_timestamp', current_time)
    
    -- Emit event for reactive updates
    state.notify('git', 'commits_updated', commits, state.get('git', 'commits'))
  else
    state.set('git', 'commits', {})
  end
  
  return state.get('git', 'commits') or {}
end

-- Get cached git status
function M.get_git_status()
  return state.get('git', 'files') or {}
end

-- Get cached git commits
function M.get_git_commits()
  return state.get('git', 'commits') or {}
end

-- Check if repository info is available
function M.is_git_repo()
  local is_repo = state.get('git', 'is_git_repo')
  if is_repo == nil then
    M.update_git_repository_info()
    is_repo = state.get('git', 'is_git_repo')
  end
  return is_repo or false
end

-- Get git root directory
function M.get_git_root()
  local git_root = state.get('git', 'git_root')
  if git_root == nil then
    M.update_git_repository_info()
    return state.get('git', 'git_root')
  end
  return git_root
end

-- Invalidate git caches
function M.invalidate_cache()
  state.update('cache', {
    git_status_timestamp = 0,
    git_commits_timestamp = 0
  })
  
  state.notify('cache', 'git_invalidated', {}, nil)
end

-- Force refresh all git data (ignores cache)
function M.force_refresh(config)
  M.update_git_repository_info()
  M.update_git_status(true)  -- force_refresh = true
  M.update_git_commits(config, true)  -- force_refresh = true
  
  -- Notify that git data was refreshed
  state.notify('git', 'force_refreshed', {
    timestamp = os.time(),
    files = state.get('git', 'files'),
    commits = state.get('git', 'commits')
  }, nil)
end

-- Subscribe to git state changes
function M.subscribe_to_git_changes(callback)
  return state.subscribe('git', callback)
end

-- Initialize git state
function M.init()
  M.update_git_repository_info()
end

-- Initialize on module load
M.init()

return M