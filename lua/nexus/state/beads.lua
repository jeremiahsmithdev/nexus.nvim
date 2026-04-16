--- Beads state management for Nexus
--- Handles CLI interaction with beads (br or bd) and caches results
---@module nexus.state.beads

local M = {}

local state = require('nexus.state')
local logger = require('nexus.logger')

-- Cache configuration
local CACHE_TTL = 60 -- 1 minute default (beads is local, frequent updates)
local _last_refresh = 0
local _cached_issues = {}
local _loading = false
local _error = nil

-- Dedicated epic cache (separate from filter-based cache to avoid collisions)
local _cached_epics = {}
local _last_epic_refresh = 0

-- Line to issue mapping for navigation
local _line_to_issue_map = {}

-- In-flight guards: key = cmd_args string, value = list of pending callbacks.
-- Coalesces concurrent CLI calls for the same command into one in-flight request.
local _inflight = {}

--- Get configured CLI binary name
---@return string "br" or "bd"
local function get_cli()
  local config = require('nexus.config').get()
  return (config.beads and config.beads.cli) or 'br'
end

--- Check if beads is available in current directory
---@return boolean
function M.is_beads_available()
  -- Check for .beads/ directory
  local git_root = require('nexus.git.root').get()
  if not git_root then
    return false
  end

  local beads_dir = git_root .. '/.beads'
  return vim.fn.isdirectory(beads_dir) == 1
end

--- Check if beads CLI is installed
---@return boolean
function M.is_cli_installed()
  local cli = get_cli()
  return vim.fn.executable(cli) == 1
end

-- run_cli_command (sync) removed: all callers converted to *_async variants.
-- Sync public functions below now return stale cache only; use *_async for
-- fresh data.

--- Execute beads CLI command asynchronously and parse JSON output.
--- Uses vim.system (Neovim 0.10+); callback is always called on the main thread
--- via vim.schedule so Neovim API calls are safe inside it.
---@param args string Command arguments (shell string; shell wrapper added internally)
---@param callback function Called with (result, error) — result is parsed table or nil
local function run_cli_command_async(args, callback)
  local cli = get_cli()
  local cmd = { 'sh', '-c', cli .. ' ' .. args .. ' 2>/dev/null' }
  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        logger.debug('BEADS', cli .. ' command failed: ' .. cli .. ' ' .. args)
        callback(nil, cli .. ' command failed')
        return
      end
      local output = obj.stdout or ''
      if output == '' or output == '\n' then
        callback({}, nil)
        return
      end
      local ok, result = pcall(vim.json.decode, output)
      if not ok then
        logger.debug('BEADS', 'Failed to parse JSON: ' .. output)
        callback(nil, 'Failed to parse ' .. cli .. ' output')
        return
      end
      callback(result, nil)
    end)
  end)
end

--- Normalise a raw CLI result (object or array) into a plain issues array.
---@param result any Raw parsed JSON
---@return table issues
local function normalize_issues(result)
  if type(result) ~= 'table' then return {} end
  if result.issues then return result.issues end
  if #result > 0 or next(result) == nil then return result end
  return { result }  -- single-object response
end

--- Initialize beads state
function M.init()
  state.set('beads', 'issues', {})
  state.set('beads', 'loaded', false)
  state.set('beads', 'error', nil)
  _cached_issues = {}
  _cached_epics = {}
  _last_refresh = 0
  _last_epic_refresh = 0
  _loading = false
  _error = nil
end

--- Get issues based on filter
---@param filter string|nil "ready", "all", "in_progress", "epics" (default: from config)
---@param force_refresh boolean|nil Force refresh ignoring cache
---@return table issues List of issues
function M.get_issues(filter, force_refresh)
  local config = require('nexus.config').get()
  filter = filter or (config.beads and config.beads.filter) or 'ready'

  -- Check cache validity
  local now = os.time()
  local ttl = (config.beads and config.beads.cache and config.beads.cache.issues_ttl) or CACHE_TTL

  if not force_refresh and (now - _last_refresh) < ttl and #_cached_issues > 0 then
    return _cached_issues
  end

  -- Check prerequisites
  -- Cache miss with no async refresh in flight: return what we have.
  -- Callers that need fresh data should use get_issues_async() instead.
  logger.debug('BEADS', 'get_issues (sync): returning stale cache, use get_issues_async for fresh data')
  return _cached_issues
end

--- Get a single issue by ID — cache lookup only.
--- Returns nil if the issue is not in the in-memory cache.
--- Use get_issue_by_id_async() to also trigger a CLI fallback.
---@param id string Issue ID (e.g., "Prefix-a3f8")
---@return table|nil issue Issue details or nil
function M.get_issue_by_id(id)
  if not id then return nil end
  for _, issue in ipairs(_cached_issues) do
    if issue.id == id then return issue end
  end
  return nil
end

--- Create a new issue — deprecated sync stub.
--- Use create_issue_async() instead; this version no longer executes CLI calls.
---@param title string Issue title
---@param opts table|nil Options: { type, priority, parent, description }
---@return table|nil issue nil (use async variant)
---@return string|nil error
function M.create_issue(title, opts)
  logger.warn('BEADS', 'create_issue (sync) called — use create_issue_async()')
  return nil, 'Use create_issue_async()'
end

--- Update an issue — deprecated sync stub.
--- Use update_issue_async() instead; this version no longer executes CLI calls.
---@param id string Issue ID
---@param updates table Updates: { status, title, description, priority, notes }
---@return table|nil issue nil (use async variant)
---@return string|nil error
function M.update_issue(id, updates)
  logger.warn('BEADS', 'update_issue (sync) called — use update_issue_async()')
  return nil, 'Use update_issue_async()'
end

--- Close an issue — deprecated sync stub.
--- Use close_issue_async() instead; this version no longer executes CLI calls.
---@param id string Issue ID
---@param reason string|nil Close reason
---@return boolean success
---@return string|nil error
function M.close_issue(id, reason)
  logger.warn('BEADS', 'close_issue (sync) called — use close_issue_async()')
  return false, 'Use close_issue_async()'
end

--- Force refresh issues (sync stub — schedules async refresh).
function M.refresh()
  M.refresh_async(nil, nil)
end

--- Check if currently loading
---@return boolean
function M.is_loading()
  return _loading
end

--- Get last error
---@return string|nil
function M.get_error()
  return _error
end

--- Clear error
function M.clear_error()
  _error = nil
end

--- Set line to issue mapping (called during render)
---@param mapping table Line number to issue ID mapping
function M.set_line_mapping(mapping)
  _line_to_issue_map = mapping or {}
end

--- Get issue ID for a line number
---@param line_num number Buffer line number
---@return string|nil issue_id
function M.get_issue_id_for_line(line_num)
  return _line_to_issue_map[line_num]
end

--- Get cached issues without refreshing
---@return table
function M.get_cached_issues()
  return _cached_issues
end

--- Check if needs refresh based on TTL
---@param config table Nexus config
---@return boolean
function M.needs_refresh(config)
  local ttl = (config.beads and config.beads.cache and config.beads.cache.issues_ttl) or CACHE_TTL
  return (os.time() - _last_refresh) >= ttl
end

--- Refresh if needed based on TTL
---@param config table Nexus config
function M.refresh_if_needed(config)
  if M.needs_refresh(config) then
    M.get_issues(nil, true)
  end
end

--- Get epics sorted by activity (in_progress first, then others by priority).
--- Uses a dedicated cache + dedicated `br list --type epic` query so it
--- doesn't collide with the filter-based `_cached_issues` cache and doesn't
--- require fetching every issue. Modeled on ~/dotfiles/beads.sh _bepic_sorted_list.
---@param force_refresh boolean|nil Force refresh
---@return table epics Sorted list of epics
--- Get sorted epics — returns cache only.
--- Use get_sorted_epics_async() to also trigger a background refresh.
---@param force_refresh boolean|nil Ignored; kept for signature compatibility
---@return table epics Cached epic list (may be empty if not yet loaded)
function M.get_sorted_epics(force_refresh)
  return _cached_epics
end

--- Get children of an epic — deprecated sync stub.
--- Use get_epic_children_async() instead; this version always returns {}.
---@param epic_id string Epic ID
---@return table children Empty table (use async variant)
function M.get_epic_children(epic_id)
  logger.warn('BEADS', 'get_epic_children (sync) called — use get_epic_children_async()')
  return {}
end

--- Get ready issues (no dependencies blocking)
---@param force_refresh boolean|nil Force refresh
---@return table issues List of ready issues
function M.get_ready_issues(force_refresh)
  return M.get_issues('ready', force_refresh)
end

--- Get cached epics without triggering a refresh.
--- Counterpart to get_cached_issues(); used by the render component so it
--- never blocks the main thread.
---@return table
function M.get_cached_epics()
  return _cached_epics
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Async public API  (stale-while-revalidate + in-flight coalescing)
-- ─────────────────────────────────────────────────────────────────────────────

--- Get issues asynchronously with stale-while-revalidate semantics.
--- Returns cached data immediately if fresh; otherwise fires a background CLI
--- refresh and calls callback when complete.  Concurrent calls for the same
--- filter coalesce into one in-flight CLI request.
---@param filter string|nil "ready", "all", "in_progress", "epics" (default: from config)
---@param callback function Called with (issues, error) — may fire synchronously from cache
function M.get_issues_async(filter, callback)
  local config = require('nexus.config').get()
  filter = filter or (config.beads and config.beads.filter) or 'ready'

  -- Fast prerequisite checks (no subprocess)
  if not M.is_beads_available() then
    callback({}, 'No .beads directory found')
    return
  end
  if not M.is_cli_installed() then
    callback({}, get_cli() .. ' CLI not installed')
    return
  end

  -- Build the canonical args key used for in-flight deduplication
  local cmd_args
  if filter == 'ready' then
    cmd_args = 'ready --json'
  elseif filter == 'in_progress' then
    cmd_args = 'list --status in_progress --json'
  elseif filter == 'epics' then
    cmd_args = 'list --type epic --json'
  else
    cmd_args = 'list --json'
  end

  local now = os.time()
  local ttl = (config.beads and config.beads.cache and config.beads.cache.issues_ttl) or CACHE_TTL

  -- Cache hit: return immediately without any I/O
  if (now - _last_refresh) < ttl and #_cached_issues > 0 then
    callback(_cached_issues, nil)
    return
  end

  -- Coalesce: queue behind an already in-flight call for this command
  if _inflight[cmd_args] then
    table.insert(_inflight[cmd_args], callback)
    return
  end

  -- Start a new in-flight call
  _inflight[cmd_args] = { callback }
  _loading = true
  _error = nil

  run_cli_command_async(cmd_args, function(result, err)
    local pending = _inflight[cmd_args] or {}
    _inflight[cmd_args] = nil
    _loading = false

    if err then
      _error = err
      logger.warn('BEADS', 'Async: failed to get issues: ' .. err)
      for _, cb in ipairs(pending) do cb(_cached_issues, err) end
      return
    end

    local issues = normalize_issues(result)
    _cached_issues = issues
    _last_refresh = os.time()
    local state_mod = require('nexus.state')
    state_mod.set('beads', 'issues', issues)
    state_mod.set('beads', 'loaded', true)
    logger.debug('BEADS', string.format('Async: loaded %d issues (filter: %s)', #issues, filter))
    for _, cb in ipairs(pending) do cb(issues, nil) end
  end)
end

--- Get a single issue by ID asynchronously.
--- Checks the in-memory cache first (O(n), instant); falls back to a CLI call.
---@param id string Issue ID
---@param callback function Called with (issue, error)
function M.get_issue_by_id_async(id, callback)
  if not id then callback(nil, 'ID required') return end

  -- Fast cache hit
  for _, issue in ipairs(_cached_issues) do
    if issue.id == id then
      callback(issue, nil)
      return
    end
  end

  -- Async fallback: br list --id <id> (~18ms, much faster than br show)
  run_cli_command_async('list --id ' .. id .. ' --format json', function(result, err)
    if err or not result then
      logger.debug('BEADS', 'Async: failed to get issue ' .. id)
      callback(nil, err or 'unknown error')
      return
    end
    local issue
    if type(result) == 'table' then
      if result.issues and result.issues[1] then
        issue = result.issues[1]
      elseif result[1] then
        issue = result[1]
      end
    end
    callback(issue or result, nil)
  end)
end

--- Get sorted epics asynchronously with stale-while-revalidate semantics.
---@param force_refresh boolean|nil Force bypass of cache
---@param callback function Called with (epics, error)
function M.get_sorted_epics_async(force_refresh, callback)
  local config = require('nexus.config').get()
  local ttl = (config.beads and config.beads.cache and config.beads.cache.issues_ttl) or CACHE_TTL
  local now = os.time()

  if not M.is_beads_available() or not M.is_cli_installed() then
    callback({}, nil)
    return
  end

  -- Cache hit
  if not force_refresh and (now - _last_epic_refresh) < ttl and #_cached_epics > 0 then
    callback(_cached_epics, nil)
    return
  end

  local cmd_args = 'list --type epic --json'

  -- Coalesce
  if _inflight[cmd_args] then
    table.insert(_inflight[cmd_args], callback)
    return
  end

  _inflight[cmd_args] = { callback }

  run_cli_command_async(cmd_args, function(result, err)
    local pending = _inflight[cmd_args] or {}
    _inflight[cmd_args] = nil

    if err or type(result) ~= 'table' then
      for _, cb in ipairs(pending) do cb(_cached_epics, err) end
      return
    end

    local epics = result.issues or result
    if type(epics) ~= 'table' or (not epics[1] and next(epics) ~= nil) then
      epics = { epics }
    end

    local status_order = { in_progress = 1, open = 2, blocked = 3, deferred = 4, closed = 5 }
    table.sort(epics, function(a, b)
      local as = status_order[a.status] or 99
      local bs = status_order[b.status] or 99
      if as ~= bs then return as < bs end
      return (a.priority or 2) < (b.priority or 2)
    end)

    _cached_epics = epics
    _last_epic_refresh = os.time()
    logger.debug('BEADS', string.format('Async: loaded %d epics', #epics))
    for _, cb in ipairs(pending) do cb(epics, nil) end
  end)
end

--- Get children of an epic asynchronously.
--- Queries SQLite directly for child IDs (via vim.system), then fetches display
--- data with a single br list call — mirrors the sync get_epic_children pattern.
---@param epic_id string Epic ID
---@param callback function Called with (children)
function M.get_epic_children_async(epic_id, callback)
  if not epic_id then callback({}) return end

  local git_root = require('nexus.git.root').get()
  if not git_root then callback({}) return end
  local db = git_root .. '/.beads/beads.db'
  if vim.fn.filereadable(db) == 0 then callback({}) return end

  local sql_id = epic_id:gsub("'", "''")
  local query = string.format(
    "SELECT issue_id FROM dependencies WHERE depends_on_id='%s' AND type='parent-child';",
    sql_id
  )

  vim.system({ 'sqlite3', db, query }, { text = true }, function(obj)
    vim.schedule(function()
      local raw = obj.stdout or ''
      if obj.code ~= 0 or raw == '' then
        callback({})
        return
      end

      local id_args = {}
      for cid in raw:gmatch('[^\r\n]+') do
        if cid ~= '' then table.insert(id_args, '--id ' .. cid) end
      end
      if #id_args == 0 then callback({}) return end

      local args_str = table.concat(id_args, ' ')
      local children = {}

      -- Active children first, then closed (mirrors sync get_epic_children)
      run_cli_command_async('list ' .. args_str .. ' --format json', function(active, _)
        if type(active) == 'table' then
          for _, issue in ipairs(active.issues or active) do
            table.insert(children, issue)
          end
        end

        run_cli_command_async('list --status closed ' .. args_str .. ' --format json', function(closed, _)
          if type(closed) == 'table' then
            for _, issue in ipairs(closed.issues or closed) do
              issue._is_closed = true
              table.insert(children, issue)
            end
          end

          local status_order = { in_progress = 1, open = 2, blocked = 3, deferred = 4, closed = 5 }
          table.sort(children, function(a, b)
            return (status_order[a.status] or 99) < (status_order[b.status] or 99)
          end)
          callback(children)
        end)
      end)
    end)
  end)
end

--- Update an issue asynchronously.
--- Runs the CLI update command, then invalidates the issues + epics caches so
--- the next render shows fresh data.  callback receives (result, error).
---@param id string Issue ID
---@param updates table Updates: { status, title, description, priority, notes }
---@param callback function Called with (result, error)
function M.update_issue_async(id, updates, callback)
  if not id then callback(nil, 'Issue ID required') return end

  local args = 'update ' .. id

  if updates.status then args = args .. ' --status ' .. updates.status end
  if updates.priority then args = args .. ' --priority ' .. tostring(updates.priority) end
  if updates.title then
    args = args .. string.format(' --title="%s"', updates.title:gsub('"', '\\"'))
  end
  if updates.notes then
    args = args .. string.format(' --notes="%s"', updates.notes:gsub('"', '\\"'))
  end
  args = args .. ' --json'

  run_cli_command_async(args, function(result, err)
    if err then callback(nil, err) return end
    -- Invalidate both caches so the next get_*_async call fetches fresh data
    _last_refresh = 0
    _last_epic_refresh = 0
    callback(result, nil)
  end)
end

--- Close an issue asynchronously.  Invalidates caches on success.
---@param id string Issue ID
---@param reason string|nil Close reason
---@param callback function Called with (success, error)
function M.close_issue_async(id, reason, callback)
  if not id then callback(false, 'Issue ID required') return end

  local args = 'close ' .. id
  if reason and reason ~= '' then
    args = args .. string.format(' --reason="%s"', reason:gsub('"', '\\"'))
  end
  args = args .. ' --json'

  run_cli_command_async(args, function(_, err)
    if err then callback(false, err) return end
    _last_refresh = 0
    _last_epic_refresh = 0
    callback(true, nil)
  end)
end

--- Create an issue asynchronously.  Invalidates caches on success.
---@param title string Issue title
---@param opts table|nil Options: { type, priority, parent, description }
---@param callback function Called with (result, error)
function M.create_issue_async(title, opts, callback)
  opts = opts or {}

  local args = string.format('create --title="%s"', title:gsub('"', '\\"'))
  if opts.type then args = args .. ' --type=' .. opts.type end
  if opts.priority then args = args .. ' --priority=' .. tostring(opts.priority) end
  if opts.parent then args = args .. ' --parent=' .. opts.parent end
  args = args .. ' --json'

  run_cli_command_async(args, function(result, err)
    if err then callback(nil, err) return end
    _last_refresh = 0
    _last_epic_refresh = 0
    callback(result, nil)
  end)
end

--- Async refresh: invalidate the issues cache and re-fetch in the background.
--- Callers receive fresh data (or stale on error) via callback.
---@param filter string|nil Filter passed to get_issues_async
---@param callback function|nil Called with (issues, error) when done
function M.refresh_async(filter, callback)
  _last_refresh = 0  -- Invalidate so get_issues_async always fires a CLI call
  M.get_issues_async(filter, callback or function() end)
end

--- Fetch issues AND epics in a single round-trip where possible, then call
--- callback once both caches are populated.
---
--- * Non-'ready' filters: one `br list --json` call; results are partitioned
---   in Lua into _cached_issues (filtered by config filter) and _cached_epics
---   (type == 'epic').  One subprocess instead of two.
---
--- * 'ready' filter: fires `br ready --json` and `br list --type epic --json`
---   concurrently (two subprocesses) because the CLI has special unblocked-leaf
---   semantics that cannot be replicated by Lua-side filtering.  Join counter
---   ensures callback fires exactly once after both complete.
---
--- Invalidates both caches before fetching (force-fresh semantics, matching
--- the behaviour of `refresh_async` which is what init.lua previously called).
---@param callback function Called with no arguments once both caches are updated
function M.fetch_issues_and_epics_async(callback)
  local config = require('nexus.config').get()
  local filter = (config.beads and config.beads.filter) or 'ready'

  if not M.is_beads_available() or not M.is_cli_installed() then
    callback()
    return
  end

  -- Invalidate both caches so the CLI calls always fire (force-fresh).
  _last_refresh = 0
  _last_epic_refresh = 0

  if filter == 'ready' then
    -- Two concurrent CLI calls; join fires callback once both complete.
    local done_count = 0
    local function on_done()
      done_count = done_count + 1
      if done_count == 2 then callback() end
    end

    M.get_issues_async('ready', function() on_done() end)
    M.get_sorted_epics_async(true, function() on_done() end)
  else
    -- Single `br list --json` call; partition in Lua.
    -- Set _loading so the initial render shows "Loading issues..." placeholder.
    _loading = true
    _error = nil
    run_cli_command_async('list --json', function(result, err)
      _loading = false
      if err or type(result) ~= 'table' then
        _error = err or 'failed to parse br output'
        logger.warn('BEADS', 'fetch_issues_and_epics_async: CLI error: ' .. (err or 'unknown'))
        callback()
        return
      end

      local all_issues = normalize_issues(result)
      local now = os.time()

      -- Partition: epics go to the epic cache, everything else to issues cache.
      -- Apply filter to the issues partition (e.g. 'in_progress', 'all').
      local epics = {}
      local issues = {}
      local status_order = { in_progress = 1, open = 2, blocked = 3, deferred = 4, closed = 5 }

      for _, issue in ipairs(all_issues) do
        if issue.type == 'epic' then
          table.insert(epics, issue)
        else
          -- Apply status filter for the issues partition
          local include = false
          if filter == 'all' then
            include = true
          elseif filter == 'in_progress' then
            include = issue.status == 'in_progress'
          else
            -- Default: show open + in_progress (same as 'br list' default view)
            include = issue.status == 'open' or issue.status == 'in_progress'
          end
          if include then table.insert(issues, issue) end
        end
      end

      -- Sort epics by status then priority (mirrors get_sorted_epics_async)
      table.sort(epics, function(a, b)
        local as = status_order[a.status] or 99
        local bs = status_order[b.status] or 99
        if as ~= bs then return as < bs end
        return (a.priority or 2) < (b.priority or 2)
      end)

      _cached_issues = issues
      _cached_epics = epics
      _last_refresh = now
      _last_epic_refresh = now

      local state_mod = require('nexus.state')
      state_mod.set('beads', 'issues', issues)
      state_mod.set('beads', 'loaded', true)

      logger.debug('BEADS', string.format(
        'fetch_issues_and_epics_async: %d issues (filter: %s), %d epics (single call)',
        #issues, filter, #epics
      ))
      callback()
    end)
  end
end

return M
