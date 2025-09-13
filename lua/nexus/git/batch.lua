local M = {}

local logger = require('nexus.logger')
local cache = require('nexus.cache')

-- Batch git operations for better performance
function M.get_git_data_batch(config)
  -- Add comprehensive error handling
  local function safe_get_git_data()
    -- Ensure config is not nil and is a table
    if config == nil or type(config) ~= 'table' then
      config = {}
    end

    -- Safely get cache key
    local cache_key
    local ok, result = pcall(cache.get_git_cache_key, 'batch_data')
    if ok then
      cache_key = result
    else
      logger.warn('GIT_BATCH', 'Failed to get cache key, using fallback')
      cache_key = 'git_batch_data_fallback'
    end

    -- Try cache first (30 second TTL)
    local cached_data = cache.get(cache_key, 30)
    if cached_data then
      logger.debug('GIT_BATCH', 'Using cached git data')
      return cached_data.status_files, cached_data.commits, cached_data.is_git_repo
    end

    logger.debug('GIT_BATCH', 'Fetching fresh git data')

    -- Single git command to batch multiple operations
    local recent_commits_count = 3
    if config and type(config) == 'table' and config.recent_commits_count then
      recent_commits_count = config.recent_commits_count
    end
    
    local cmd = table.concat({
      'git rev-parse --is-inside-work-tree 2>/dev/null',
      'echo "---STATUS---"',
      'git status --porcelain=v1 2>/dev/null',
      'echo "---COMMITS---"', 
      'git log --oneline --decorate -' .. recent_commits_count .. ' 2>/dev/null',
      'echo "---DIFFSTAT---"',
      'git diff --numstat 2>/dev/null'
    }, ' && ')

    local handle = io.popen(cmd)
    if not handle then
      logger.error('GIT_BATCH', 'Failed to execute batch git command')
      return {}, {}, false
    end

    local result = handle:read('*a')
    handle:close()

    if result == '' then
      logger.debug('GIT_BATCH', 'Empty git command result')
      return {}, {}, false
    end

    -- Parse the combined output
    local sections = {}
    local current_section = nil
    local current_content = {}

    for line in result:gmatch('[^\r\n]+') do
      if line == '---STATUS---' then
        if current_section then
          sections[current_section] = table.concat(current_content, '\n')
        end
        current_section = 'status'
        current_content = {}
      elseif line == '---COMMITS---' then
        if current_section then
          sections[current_section] = table.concat(current_content, '\n')
        end
        current_section = 'commits'
        current_content = {}
      elseif line == '---DIFFSTAT---' then
        if current_section then
          sections[current_section] = table.concat(current_content, '\n')
        end
        current_section = 'diffstat'
        current_content = {}
      else
        if current_section then
          table.insert(current_content, line)
        elseif line:match('true') then
          -- This is the git repo check result
          sections.is_git_repo = true
        end
      end
    end

    -- Don't forget the last section
    if current_section then
      sections[current_section] = table.concat(current_content, '\n')
    end

    local is_git_repo = sections.is_git_repo or false

    if not is_git_repo then
      logger.debug('GIT_BATCH', 'Not in git repository')
      return {}, {}, false
    end

    -- Parse status files
    local status_files = M.parse_batch_status(sections.status or '', sections.diffstat or '')

    -- Parse commits
    local commits = M.parse_batch_commits(sections.commits or '')

    -- Cache the results
    local data_to_cache = {
      status_files = status_files,
      commits = commits,
      is_git_repo = is_git_repo
    }
    cache.set(cache_key, data_to_cache)

    logger.debug('GIT_BATCH', string.format('Parsed %d files, %d commits', #status_files, #commits))

    return status_files, commits, is_git_repo
  end

  -- Execute with error handling
  local success, status_files, commits, is_git_repo = pcall(safe_get_git_data)
  if success then
    return status_files, commits, is_git_repo
  else
    logger.error('GIT_BATCH', 'Error in get_git_data_batch: ' .. tostring(status_files))
    return {}, {}, false
  end
end

-- Parse status output from batch command
function M.parse_batch_status(status_output, diffstat_output)
  if status_output == '' then
    return {}
  end

  local files = {}
  local diffstats = M.parse_diffstats(diffstat_output)

  -- Parse status output (line-terminated from batch command)
  for line in status_output:gmatch('[^\r\n]+') do
    if line ~= '' then
      local status = line:sub(1, 2)
      local file = line:sub(4)

      -- Get diff stats from batched data
      local added, deleted = diffstats[file] and diffstats[file].added or 0,
                            diffstats[file] and diffstats[file].deleted or 0

      table.insert(files, {
        status = status,
        file = file,
        added = added,
        deleted = deleted
      })
    end
  end

  return files
end

-- Parse commits output from batch command  
function M.parse_batch_commits(commits_output)
  if commits_output == '' then
    return {}
  end

  local commits = {}
  for line in commits_output:gmatch('[^\r\n]+') do
    if line ~= '' then
      -- Try to match hash with decoration first, then without
      local hash, decoration, message = line:match('([%w]+)%s+(%b())%s*(.*)')
      if not hash then
        -- No decoration, just hash and message
        hash, message = line:match('([%w]+)%s+(.*)')
      end
      if hash then
        table.insert(commits, {
          hash = hash,
          message = message and message:match("^%s*(.-)%s*$") or '',
          decoration = decoration
        })
      end
    end
  end

  return commits
end

-- Parse diff stats for all files at once
function M.parse_diffstats(diffstat_output)
  local stats = {}

  if diffstat_output == '' then
    return stats
  end

  for line in diffstat_output:gmatch('[^\r\n]+') do
    local added, deleted, file = line:match('(%d+)%s+(%d+)%s+(.+)')
    if added and deleted and file then
      stats[file] = {
        added = tonumber(added) or 0,
        deleted = tonumber(deleted) or 0
      }
    end
  end

  return stats
end

-- Fast status check with caching
function M.is_git_repo_cached()
  local cache_key = 'git_repo_check'

  -- Very short cache (5 seconds) for repo check
  local cached = cache.get(cache_key, 5)
  if cached ~= nil then
    return cached
  end

  local git_check = vim.fn.system('git rev-parse --is-inside-work-tree 2>/dev/null')
  local is_repo = vim.v.shell_error == 0 and git_check:match('true')

  cache.set(cache_key, is_repo)
  return is_repo
end

-- Invalidate git data cache (call when git operations are performed)
function M.invalidate_cache()
  local ok, cache_key = pcall(cache.get_git_cache_key, 'batch_data')
  if ok then
    cache.invalidate(cache_key)
  end
  cache.invalidate('git_repo_check')
  logger.debug('GIT_BATCH', 'Invalidated git data cache')
end

return M