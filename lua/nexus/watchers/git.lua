--- lua/nexus/watchers/git.lua
---
--- Live-refresh coordinator for the Nexus dashboard.
---
--- This module owns three precise fs_event handles on git's atomic-write
--- files, plus delegation to the change-suspicion gate (git_status_confirm).
--- It is never the one that calls refresh_buffer directly — all paths funnel
--- through the gate, which only fires when `git status` output actually
--- differs from the last seen hash.
---
--- fs_event handles (with mtime gate to filter atime-only wakes):
---   .git/HEAD       — branch switch, detached HEAD
---   .git/index      — `git add` / `git reset` / commit
---   .git/logs/HEAD  — every commit, every checkout (appends a line)
---
--- Additional signals are owned by git_status_confirm:
---   BufWritePost   — this-nvim saves inside the repo
---   FocusGained    — alt-tab back from another tool
---   CursorHold     — throttled safety net for external edits while idle
---
--- All signals are coalesced by the confirm gate's 150ms debounce and then
--- filtered by a hashed `git status` comparison. No path here can produce
--- a visible refresh without a real state change.

local M = {}

local uv = vim.uv or vim.loop

M._handles  = {}    -- fs_event handles, one per watched file
M._mtimes   = {}    -- last-seen mtime per path; gates spurious events
M._augroup  = nil   -- BufWipeout teardown autocmd group
M._buf      = nil   -- watched Nexus buffer

local WATCH_FILES = { 'HEAD', 'index', 'logs/HEAD' }

local function safe_close(handle)
  if handle and not handle:is_closing() then
    pcall(function() handle:stop() end)
    pcall(function() handle:close() end)
  end
end

-- Resolve the .git directory for the current cwd. Handles worktrees,
-- submodules, and `.git` files. Runs once per Nexus open.
local function resolve_git_dir()
  local out = vim.fn.systemlist({ 'git', 'rev-parse', '--git-dir' })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == '' then return nil end
  return vim.fn.fnamemodify(out[1], ':p')
end

-- Resolve the working-tree root (different from .git dir for separate
-- worktrees, submodules, --git-dir overrides).
local function resolve_repo_root()
  local out = vim.fn.systemlist({ 'git', 'rev-parse', '--show-toplevel' })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == '' then return nil end
  return vim.fn.fnamemodify(out[1], ':p')
end

-- Pack mtime as a sec.nsec string. Avoids Lua number precision on nanoseconds.
local function read_mtime(path)
  local st = uv.fs_stat(path)
  if not st or not st.mtime then return nil end
  return tostring(st.mtime.sec) .. '.' .. tostring(st.mtime.nsec or 0)
end

-- Open one fs_event handle on a single file. fs_event fires on any inode
-- metadata change including atime updates from external stat() calls; we
-- gate on mtime to filter those. Real writes (atomic rename into place by
-- git) always advance mtime.
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
        return  -- spurious wake (atime tick); ignore.
      end
      M._mtimes[path] = current
      require('nexus.watchers.git_status_confirm').poke()
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
  M._buf = buf

  local git_dir = resolve_git_dir()
  local repo_root = resolve_repo_root()
  if not git_dir or not repo_root then return end

  -- Light fs_event handles on the three canonical write targets.
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

  -- The confirm gate owns BufWritePost / FocusGained / CursorHold and runs
  -- the debounced `git status` hash check that decides whether a refresh
  -- actually happens.
  require('nexus.watchers.git_status_confirm').start(buf, {
    repo_root       = repo_root,
    refresh         = function(b)
      local ok, nexus = pcall(require, 'nexus')
      if ok then pcall(nexus.refresh_buffer, b, { quiet = true, git_only = true }) end
    end,
    debounce_ms     = tonumber(cfg.debounce_ms)     or 150,
    hold_throttle_s = tonumber(cfg.hold_throttle_s) or 10,
  })
end

--- Stop watching. Idempotent.
function M.stop()
  for _, h in ipairs(M._handles) do safe_close(h) end
  M._handles = {}
  M._mtimes = {}
  if M._augroup then
    pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
    M._augroup = nil
  end
  M._buf = nil
  pcall(function()
    require('nexus.watchers.git_status_confirm').stop()
  end)
end

return M
