--- Claude Code conversation scanner for Nexus dashboard
--- Provides async filesystem scan with in-memory and disk cache to prevent startup blocking.
--- Pattern: get_cached() returns immediately; refresh_async() runs in background and
--- updates memory + disk cache, then calls the supplied callback.

local M = {}

local logger = require('nexus.logger')
local git_commits = require('nexus.git.commits')

-- In-memory cache for current session. nil = not yet loaded; {} = loaded but empty
local _cache = nil
-- Guard against concurrent scans
local _scan_active = false

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function time_ago(seconds)
  local days = math.floor(seconds / 86400)
  if days > 0 then
    return days .. ' day' .. (days == 1 and '' or 's') .. ' ago'
  end
  local hours = math.floor(seconds / 3600)
  if hours > 0 then
    return hours .. ' hour' .. (hours == 1 and '' or 's') .. ' ago'
  end
  return 'today'
end

-- Disk cache path: ~/.cache/nexus/claude_conv_<hash16>.json
-- One file per (git_root, branch) pair; never grows unbounded across sessions.
local function get_disk_cache_path(git_root, branch)
  local hash = vim.fn.sha256(git_root .. ':' .. branch)
  return vim.fn.expand('~/.cache/nexus') .. '/claude_conv_' .. hash:sub(1, 16) .. '.json'
end

-- Resolve the Claude project directory for a given git_root.
-- Tries encoded git_root first, then encoded cwd as fallback.
local function resolve_project_path(git_root)
  local base = vim.fn.expand('~/.claude/projects')

  local encoded = git_root:gsub('/', '-')
  local path = base .. '/' .. encoded
  if vim.fn.isdirectory(path) == 1 then return path end

  local encoded_cwd = vim.fn.getcwd():gsub('/', '-')
  path = base .. '/' .. encoded_cwd
  if vim.fn.isdirectory(path) == 1 then return path end

  return nil
end

-- ---------------------------------------------------------------------------
-- Disk cache: read / write
-- ---------------------------------------------------------------------------

-- Try loading from disk cache.  Returns conversations[] or nil on miss/stale.
-- Invalidation: directory mtime — if the project dir was modified after scanned_at
-- the cache is considered stale and a fresh scan will be triggered.
local function try_disk_cache(cache_path, project_path)
  local f = io.open(cache_path, 'r')
  if not f then return nil end
  local content = f:read('*a')
  f:close()

  if not content or content == '' then return nil end

  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' or not data.conversations or not data.scanned_at then
    return nil
  end

  -- Invalidate when project directory mtime is newer than our scan timestamp
  local dir_stat = vim.uv.fs_stat(project_path)
  if dir_stat and dir_stat.mtime.sec > data.scanned_at then
    logger.debug('CLAUDE', 'Disk cache stale: dir was modified after scan')
    return nil
  end

  logger.debug('CLAUDE', 'Disk cache hit', { count = #data.conversations })
  return data.conversations
end

local function write_disk_cache(cache_path, conversations)
  local cache_dir = vim.fn.expand('~/.cache/nexus')
  if vim.fn.isdirectory(cache_dir) == 0 then
    vim.fn.mkdir(cache_dir, 'p')
  end

  local ok, json = pcall(vim.json.encode, {
    scanned_at = os.time(),
    conversations = conversations,
  })
  if not ok then return end

  local f = io.open(cache_path, 'w')
  if not f then return end
  f:write(json)
  f:close()
  logger.debug('CLAUDE', 'Disk cache written', { path = cache_path, count = #conversations })
end

-- ---------------------------------------------------------------------------
-- File content parsing (runs on main thread via vim.schedule)
-- ---------------------------------------------------------------------------

-- Parse a file's raw content into a conversation record.
-- Returns a table or nil if the file doesn't match git_root+branch.
local function parse_file_content(content, git_root, branch, mtime_sec, btime_sec)
  if not content or #content == 0 then return nil end

  local first_line = content:match('^([^\n]*)')
  if not first_line or first_line == '' then return nil end

  local ok, data = pcall(vim.json.decode, first_line)
  if not ok or type(data) ~= 'table' then return nil end

  -- Filter to conversations for this repo + branch only
  if data.cwd ~= git_root or data.gitBranch ~= branch then return nil end

  -- Extract first meaningful user message as summary
  local summary = 'No summary'
  if data.message and type(data.message.content) == 'string' then
    local msg = data.message.content
    if not msg:match('^Caveat:') and not msg:match('<command%-name>') then
      summary = msg
    end
  end

  -- Count messages by scanning lines (done in async context so main thread isn't blocked
  -- during initial render; processing happens in vim.schedule after file read completes)
  local msg_count = 0
  for line in content:gmatch('[^\n]+') do
    if line:match('"type":"user"') or line:match('"type":"assistant"') then
      msg_count = msg_count + 1
    end
  end

  local now = os.time()
  return {
    content = summary,
    messages = msg_count,
    timestamp = data.timestamp or '',
    session_id = data.sessionId,
    modified = time_ago(now - (mtime_sec or now)),
    created = time_ago(now - (btime_sec or now)),
  }
end

-- ---------------------------------------------------------------------------
-- Async directory + file scan via vim.uv
-- ---------------------------------------------------------------------------

-- Reads all *.jsonl files in project_path asynchronously.
-- All file I/O happens on libuv's thread pool; parsing runs on the main thread
-- inside vim.schedule callbacks (safe for vim.json.decode).
local function scan_async(project_path, git_root, branch, on_done)
  -- Step 1: list JSONL files asynchronously
  vim.uv.fs_scandir(project_path, function(scan_err, scanner)
    if scan_err or not scanner then
      vim.schedule(function() on_done({}) end)
      return
    end

    local jsonl_files = {}
    while true do
      local name, ftype = vim.uv.fs_scandir_next(scanner)
      if not name then break end
      if name:match('%.jsonl$') and (ftype == 'file' or ftype == nil) then
        table.insert(jsonl_files, project_path .. '/' .. name)
      end
    end

    if #jsonl_files == 0 then
      vim.schedule(function() on_done({}) end)
      return
    end

    -- Step 2: read each file asynchronously
    local results = {}
    local pending = #jsonl_files

    local function finish_one(conv)
      if conv then table.insert(results, conv) end
      pending = pending - 1
      if pending == 0 then
        table.sort(results, function(a, b) return (a.timestamp or '') > (b.timestamp or '') end)
        on_done(results)
      end
    end

    for _, file_path in ipairs(jsonl_files) do
      vim.uv.fs_open(file_path, 'r', 438, function(open_err, fd)
        if open_err or not fd then
          vim.schedule(function() finish_one(nil) end)
          return
        end

        vim.uv.fs_fstat(fd, function(stat_err, stat)
          if stat_err or not stat then
            vim.uv.fs_close(fd, function() end)
            vim.schedule(function() finish_one(nil) end)
            return
          end

          local mtime = stat.mtime.sec
          local btime = stat.birthtime and stat.birthtime.sec or mtime
          -- Cap at 1 MB to avoid memory pressure from very large conversation files
          local read_size = math.min(stat.size, 1024 * 1024)

          vim.uv.fs_read(fd, read_size, 0, function(read_err, data)
            vim.uv.fs_close(fd, function() end)

            vim.schedule(function()
              if read_err or not data or #data == 0 then
                finish_one(nil)
                return
              end
              local conv = parse_file_content(data, git_root, branch, mtime, btime)
              finish_one(conv)
            end)
          end)
        end)
      end)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Return conversations from the in-memory cache without any I/O.
--- Returns nil if the scan has not yet completed this session.
function M.get_cached()
  return _cache
end

--- Backward-compatible synchronous getter used by keymaps/claude.lua on <Enter>.
--- Returns cached conversations or an empty table (never blocks).
function M.get_claude_conversations(_config)
  return _cache or {}
end

--- Start an async refresh.  Checks disk cache first (cheap: one stat + small JSON
--- read); falls back to a full async scan via vim.uv only when the cache is stale.
--- callback(conversations) is always called; conversations may be {}.
--- Concurrent calls are no-ops — the first caller wins.
function M.refresh_async(config, callback)
  if _scan_active then
    logger.debug('CLAUDE', 'Scan already in progress, skipping duplicate call')
    return
  end

  local git_root = require('nexus.git.root').get()
  if not git_root then
    if callback then callback({}) end
    return
  end

  local branch = git_commits.get_current_branch()
  if not branch or branch == '' then
    if callback then callback({}) end
    return
  end

  local project_path = resolve_project_path(git_root)
  if not project_path then
    if callback then callback({}) end
    return
  end

  -- Disk cache check (sync — just a stat + small JSON read, cheap)
  local cache_path = get_disk_cache_path(git_root, branch)
  local disk_hit = try_disk_cache(cache_path, project_path)
  if disk_hit then
    _cache = disk_hit
    if callback then callback(disk_hit) end
    return
  end

  -- Full async scan
  _scan_active = true
  logger.debug('CLAUDE', 'Starting async conversation scan', { project_path = project_path })

  scan_async(project_path, git_root, branch, function(conversations)
    _scan_active = false
    _cache = conversations
    write_disk_cache(cache_path, conversations)
    logger.debug('CLAUDE', 'Async scan complete', { count = #conversations })
    if callback then callback(conversations) end
  end)
end

--- Invalidate memory and disk caches (call when a conversation file changes).
function M.invalidate_cache()
  _cache = nil
  local git_root = require('nexus.git.root').get()
  if not git_root then return end
  local branch = git_commits.get_current_branch()
  if not branch then return end
  local cache_path = get_disk_cache_path(git_root, branch)
  os.remove(cache_path)
  logger.debug('CLAUDE', 'Cache invalidated')
end

return M
