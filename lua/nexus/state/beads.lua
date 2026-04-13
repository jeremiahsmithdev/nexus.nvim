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

-- Line to issue mapping for navigation
local _line_to_issue_map = {}

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
  local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
  if vim.v.shell_error ~= 0 or git_root == '' then
    return false
  end

  local beads_dir = git_root .. '/.beads'
  return vim.fn.isdirectory(beads_dir) == 1
end

--- Check if beads CLI is installed
---@return boolean
function M.is_cli_installed()
  local cli = get_cli()
  local result = vim.fn.system('which ' .. cli .. ' 2>/dev/null')
  return vim.v.shell_error == 0 and result ~= ''
end

--- Execute beads CLI command and parse JSON output
---@param args string Command arguments
---@return table|nil result Parsed JSON or nil on error
---@return string|nil error Error message if failed
local function run_cli_command(args)
  local cli = get_cli()
  local cmd = cli .. ' ' .. args .. ' 2>/dev/null'
  local output = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    logger.debug('BEADS', cli .. ' command failed: ' .. cmd)
    return nil, cli .. ' command failed'
  end

  if output == '' or output == '\n' then
    return {}, nil
  end

  -- Parse JSON output
  local ok, result = pcall(vim.json.decode, output)
  if not ok then
    logger.debug('BEADS', 'Failed to parse JSON: ' .. output)
    return nil, 'Failed to parse ' .. cli .. ' output'
  end

  return result, nil
end

--- Initialize beads state
function M.init()
  state.set('beads', 'issues', {})
  state.set('beads', 'loaded', false)
  state.set('beads', 'error', nil)
  _cached_issues = {}
  _last_refresh = 0
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
  if not M.is_beads_available() then
    _error = 'No .beads directory found'
    return {}
  end

  if not M.is_cli_installed() then
    _error = get_cli() .. ' CLI not installed'
    return {}
  end

  _loading = true
  _error = nil

  -- Build command based on filter
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

  local result, err = run_cli_command(cmd_args)
  _loading = false

  if err then
    _error = err
    logger.warn('BEADS', 'Failed to get issues: ' .. err)
    return _cached_issues -- Return stale cache on error
  end

  -- Normalize result to array
  local issues = {}
  if type(result) == 'table' then
    if result.issues then
      issues = result.issues
    elseif #result > 0 or next(result) == nil then
      issues = result
    else
      -- Single issue returned as object
      issues = { result }
    end
  end

  _cached_issues = issues
  _last_refresh = now
  state.set('beads', 'issues', issues)
  state.set('beads', 'loaded', true)

  logger.debug('BEADS', string.format('Loaded %d issues (filter: %s)', #issues, filter))
  return issues
end

--- Get a single issue by ID
---@param id string Issue ID (e.g., "Prefix-a3f8")
---@return table|nil issue Issue details or nil
function M.get_issue_by_id(id)
  if not id then return nil end

  -- First check cache
  for _, issue in ipairs(_cached_issues) do
    if issue.id == id then
      return issue
    end
  end

  -- Fetch from CLI
  local result, err = run_cli_command('show ' .. id .. ' --json')
  if err or not result then
    logger.debug('BEADS', 'Failed to get issue ' .. id .. ': ' .. (err or 'unknown error'))
    return nil
  end

  return result
end

--- Create a new issue
---@param title string Issue title
---@param opts table|nil Options: { type, priority, parent, description }
---@return table|nil issue Created issue or nil
---@return string|nil error Error message if failed
function M.create_issue(title, opts)
  opts = opts or {}

  local args = string.format('create --title="%s"', title:gsub('"', '\\"'))

  if opts.type then
    args = args .. ' --type=' .. opts.type
  end

  if opts.priority then
    args = args .. ' --priority=' .. tostring(opts.priority)
  end

  if opts.parent then
    args = args .. ' --parent=' .. opts.parent
  end

  args = args .. ' --json'

  local result, err = run_cli_command(args)
  if err then
    return nil, err
  end

  -- Force refresh to get updated list
  M.get_issues(nil, true)

  return result, nil
end

--- Update an issue
---@param id string Issue ID
---@param updates table Updates: { status, title, description, priority, notes }
---@return table|nil issue Updated issue or nil
---@return string|nil error Error message if failed
function M.update_issue(id, updates)
  if not id then
    return nil, 'Issue ID required'
  end

  local args = 'update ' .. id

  if updates.status then
    args = args .. ' --status ' .. updates.status
  end

  if updates.priority then
    args = args .. ' --priority ' .. tostring(updates.priority)
  end

  if updates.title then
    args = args .. string.format(' --title="%s"', updates.title:gsub('"', '\\"'))
  end

  if updates.notes then
    args = args .. string.format(' --notes="%s"', updates.notes:gsub('"', '\\"'))
  end

  args = args .. ' --json'

  local result, err = run_cli_command(args)
  if err then
    return nil, err
  end

  -- Force refresh
  M.get_issues(nil, true)

  return result, nil
end

--- Close an issue
---@param id string Issue ID
---@param reason string|nil Close reason
---@return boolean success
---@return string|nil error Error message if failed
function M.close_issue(id, reason)
  if not id then
    return false, 'Issue ID required'
  end

  local args = 'close ' .. id
  if reason and reason ~= '' then
    args = args .. string.format(' --reason="%s"', reason:gsub('"', '\\"'))
  end
  args = args .. ' --json'

  local _, err = run_cli_command(args)
  if err then
    return false, err
  end

  -- Force refresh
  M.get_issues(nil, true)

  return true, nil
end

--- Force refresh issues
function M.refresh()
  M.get_issues(nil, true)
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

--- Get epics sorted by activity (in_progress first, then with in_progress children, then others)
---@param force_refresh boolean|nil Force refresh
---@return table epics Sorted list of epics
function M.get_sorted_epics(force_refresh)
  -- Get all epics
  local all_issues = M.get_issues('all', force_refresh)
  local epics = {}

  -- Filter to only epics
  for _, issue in ipairs(all_issues) do
    if issue.type == 'epic' then
      table.insert(epics, issue)
    end
  end

  -- Get in_progress issues for grouping
  local in_progress_issues = {}
  for _, issue in ipairs(all_issues) do
    if issue.status == 'in_progress' then
      in_progress_issues[issue.id] = true
    end
  end

  -- Sort epics: in_progress first, then with in_progress children, then others
  local group0 = {} -- in_progress epics
  local group1 = {} -- epics with in_progress children
  local group2 = {} -- other epics

  for _, epic in ipairs(epics) do
    if epic.status == 'in_progress' then
      table.insert(group0, epic)
    else
      -- Check if epic has in_progress children
      local has_in_progress_child = false
      for issue_id, _ in pairs(in_progress_issues) do
        if issue_id:match('^' .. epic.id .. '%.') then
          has_in_progress_child = true
          break
        end
      end

      if has_in_progress_child then
        table.insert(group1, epic)
      else
        table.insert(group2, epic)
      end
    end
  end

  -- Combine groups
  local sorted_epics = {}
  for _, epic in ipairs(group0) do table.insert(sorted_epics, epic) end
  for _, epic in ipairs(group1) do table.insert(sorted_epics, epic) end
  for _, epic in ipairs(group2) do table.insert(sorted_epics, epic) end

  return sorted_epics
end

--- Get children of an epic (both active and closed)
---@param epic_id string Epic ID
---@return table children List of child issues
function M.get_epic_children(epic_id)
  if not epic_id then return {} end

  -- Get all issues (including closed)
  local all_open = M.get_issues('all', false)
  local children = {}

  -- Pattern: epic_id followed by a dot
  local pattern = '^' .. epic_id:gsub('%-', '%%-') .. '%.'

  for _, issue in ipairs(all_open) do
    if issue.id and issue.id:match(pattern) then
      table.insert(children, issue)
    end
  end

  -- Also get closed children
  local closed_result, _ = run_cli_command('list --status closed --json')
  if closed_result and type(closed_result) == 'table' then
    local closed_issues = closed_result.issues or closed_result or {}
    for _, issue in ipairs(closed_issues) do
      if issue.id and issue.id:match(pattern) then
        issue._is_closed = true -- Mark as closed for rendering
        table.insert(children, issue)
      end
    end
  end

  -- Sort: in_progress first, then open, then blocked, deferred, closed
  local status_order = {
    in_progress = 1,
    open = 2,
    blocked = 3,
    deferred = 4,
    closed = 5
  }

  table.sort(children, function(a, b)
    local a_order = status_order[a.status] or 99
    local b_order = status_order[b.status] or 99
    return a_order < b_order
  end)

  return children
end

--- Get ready issues (no dependencies blocking)
---@param force_refresh boolean|nil Force refresh
---@return table issues List of ready issues
function M.get_ready_issues(force_refresh)
  return M.get_issues('ready', force_refresh)
end

return M
