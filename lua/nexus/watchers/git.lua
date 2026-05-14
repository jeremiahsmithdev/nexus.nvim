--- lua/nexus/watchers/git.lua
---
--- Live-refresh the Nexus dashboard on real git state changes only.
---
--- Strictly event-scoped: we watch three specific files that git writes
--- atomically when (and only when) user-meaningful state changes:
---
---   .git/HEAD       — branch switch, detached HEAD
---   .git/index      — `git add` / `git reset` / commit (stage/unstage)
---   .git/logs/HEAD  — every commit, every checkout (appends a line)
---
--- We do NOT:
---   * watch `.git/` as a directory   (loose objects, packfiles, fsmonitor,
---                                     FETCH_HEAD churn from statuslines,
---                                     lockfiles — all noise)
---   * watch BufWritePost             (a save isn't a git event until `add`)
---   * watch FocusGained              (tmux/nvim pane switches aren't events)
---
--- All three handles funnel into one shared 200ms debounce timer so a single
--- `git commit` (touches HEAD + index + logs/HEAD) coalesces into one refresh.

local M = {}

local uv = vim.uv or vim.loop

M._handles  = {}    -- fs_event handles, one per watched file
M._mtimes   = {}    -- last-seen mtime per path; gates spurious events
M._timer    = nil   -- shared debounce timer
M._augroup  = nil   -- BufWipeout teardown autocmd group
M._buf      = nil   -- watched Nexus buffer
M._debounce = 200

local WATCH_FILES = { 'HEAD', 'index', 'logs/HEAD' }

local function safe_close(handle)
  if handle and not handle:is_closing() then
    pcall(function() handle:stop() end)
    pcall(function() handle:close() end)
  end
end

-- Resolve the .git directory for the current cwd. `git rev-parse --git-dir`
-- handles worktrees, submodules, and `.git` files. Runs once per Nexus open.
local function resolve_git_dir()
  local out = vim.fn.systemlist({ 'git', 'rev-parse', '--git-dir' })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == '' then return nil end
  return vim.fn.fnamemodify(out[1], ':p')
end

-- Single sink for "a watched git file was written". Debounced so a commit
-- (which touches all three watched files in quick succession) collapses to
-- one refresh.
local function schedule_refresh()
  if not (M._buf and vim.api.nvim_buf_is_valid(M._buf)) then return end

  if M._timer then
    safe_close(M._timer)
    M._timer = nil
  end

  local t = uv.new_timer()
  if not t then return end
  M._timer = t
  t:start(M._debounce, 0, vim.schedule_wrap(function()
    safe_close(M._timer)
    M._timer = nil
    if not (M._buf and vim.api.nvim_buf_is_valid(M._buf)) then return end
    local ok, nexus = pcall(require, 'nexus')
    if not ok then return end
    pcall(nexus.refresh_buffer, M._buf, { quiet = true, git_only = true })
  end))
end

-- Read mtime as a packed string (sec + nsec). Returns nil if file gone.
-- We compare equality of this string between events; a write advances either
-- field. Using a string sidesteps Lua-number precision on nanoseconds.
local function read_mtime(path)
  local st = uv.fs_stat(path)
  if not st or not st.mtime then return nil end
  return tostring(st.mtime.sec) .. '.' .. tostring(st.mtime.nsec or 0)
end

-- Open one fs_event handle on a single file. git uses atomic rename-into-place
-- for HEAD / index / logs/HEAD, so the handle survives the write.
--
-- IMPORTANT: fs_event fires on *any* inode metadata change, including atime
-- updates from external `stat()` calls (statusline plugins, language servers,
-- shell prompts all stat .git/index constantly). Without a content-change gate
-- the dashboard would re-render on every spurious wake. We gate on mtime: only
-- schedule a refresh when mtime actually advanced since the last event.
local function watch_file(path)
  if vim.fn.filereadable(path) == 0 then return end
  M._mtimes[path] = read_mtime(path)
  local handle = uv.new_fs_event()
  if not handle then return end
  local ok = pcall(function()
    handle:start(path, {}, vim.schedule_wrap(function(err)
      if err then return end
      local current = read_mtime(path)
      if current == M._mtimes[path] then
        -- Spurious wake (atime tick, fsnotify quirk). Ignore.
        return
      end
      M._mtimes[path] = current
      schedule_refresh()
    end))
  end)
  if ok then
    table.insert(M._handles, handle)
  else
    safe_close(handle)
  end
end

--- Begin watching for `buf` (the Nexus dashboard buffer). Idempotent.
function M.start(buf, config)
  M.stop()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end

  config = config or {}
  local cfg = config.git_auto_refresh or {}
  if cfg.enabled == false then return end
  M._debounce = tonumber(cfg.debounce_ms) or 200
  M._buf = buf

  local git_dir = resolve_git_dir()
  if not git_dir then return end

  for _, rel in ipairs(WATCH_FILES) do
    watch_file(git_dir .. rel)
  end

  -- Self-teardown when the Nexus buffer is wiped.
  M._augroup = vim.api.nvim_create_augroup('NexusGitWatcher', { clear = true })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = M._augroup,
    buffer = buf,
    callback = function() M.stop() end,
  })
end

--- Stop watching. Idempotent.
function M.stop()
  safe_close(M._timer); M._timer = nil
  for _, h in ipairs(M._handles) do safe_close(h) end
  M._handles = {}
  M._mtimes = {}
  if M._augroup then
    pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
    M._augroup = nil
  end
  M._buf = nil
end

return M
