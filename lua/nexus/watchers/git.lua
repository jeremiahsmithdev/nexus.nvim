--- lua/nexus/watchers/git.lua
---
--- Live-refresh the Nexus dashboard on git state changes with minimum cost.
--- Idle cost is one libuv fs_event handle + two autocmds — no polling, no timers
--- running while nothing is happening.
---
--- Signals (cheapest first):
---   * fs_event on `.git/`   -> covers commits, branch switches, add/reset (index)
---   * BufWritePost          -> covers in-nvim edits that change working-tree status
---   * FocusGained           -> covers edits made in another terminal while away
---
--- All signals collapse into one shared debounce timer that fires
--- `nexus.refresh_buffer(buf)` — the same path the manual `r` keybinding uses.

local M = {}

local uv = vim.uv or vim.loop

M._fs_handle = nil   -- single fs_event on .git/
M._timer     = nil   -- shared debounce timer
M._augroup   = nil   -- autocmd group id
M._buf       = nil   -- watched Nexus buffer
M._git_dir   = nil   -- resolved .git path (file or dir)
M._debounce  = 200   -- ms, overridden in start()

local function safe_close(handle)
  if handle and not handle:is_closing() then
    pcall(function() handle:stop() end)
    pcall(function() handle:close() end)
  end
end

-- Resolve the .git directory for the current cwd. Returns absolute path or nil.
-- `git rev-parse --git-dir` is the only reliable way: it handles worktrees,
-- submodules, and `.git` files (which point elsewhere). Synchronous is fine —
-- this runs once per Nexus open.
local function resolve_git_dir()
  local out = vim.fn.systemlist({ 'git', 'rev-parse', '--git-dir' })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == '' then return nil end
  return vim.fn.fnamemodify(out[1], ':p')
end

-- Single entry point for "something git-ish changed". All callbacks land here,
-- and the timer collapses bursts into one refresh.
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
    -- quiet:    no "Nexus refreshed (Xms)" toast on every fs event.
    -- git_only: skip Linear/Huly HTTP refetch — they aren't affected by
    --           a local `git add` / commit / branch switch.
    pcall(nexus.refresh_buffer, M._buf, { quiet = true, git_only = true })
  end))
end

--- Begin watching for `buf` (the Nexus dashboard buffer). Idempotent: a second
--- call replaces any prior watch. Reads debounce_ms from config.
function M.start(buf, config)
  M.stop()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end

  config = config or {}
  local cfg = config.git_auto_refresh or {}
  if cfg.enabled == false then return end
  M._debounce = tonumber(cfg.debounce_ms) or 200
  M._buf = buf

  local git_dir = resolve_git_dir()
  M._git_dir = git_dir

  -- fs_event on .git/ (non-recursive). Non-recursive is enough: git's atomic
  -- renames for index/HEAD/refs writes all touch the .git directory entry,
  -- which fires this watcher. Cheaper than recursive and avoids being woken
  -- by every loose object write under .git/objects/.
  if git_dir then
    local handle = uv.new_fs_event()
    if handle then
      M._fs_handle = handle
      local ok = pcall(function()
        handle:start(git_dir, {}, vim.schedule_wrap(function(err)
          if err then return end
          schedule_refresh()
        end))
      end)
      if not ok then
        safe_close(handle)
        M._fs_handle = nil
      end
    end
  end

  -- Autocmds: catch the cases fs_event can't see cheaply.
  --   BufWritePost — working-tree edits (status changes without index write).
  --   FocusGained  — external git operations while nvim was unfocused.
  M._augroup = vim.api.nvim_create_augroup('NexusGitWatcher', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufWritePost', 'FocusGained' }, {
    group = M._augroup,
    callback = function(args)
      -- Skip writes to the Nexus buffer itself (it's nofile anyway, but cheap guard).
      if args.buf == M._buf then return end
      schedule_refresh()
    end,
  })

  -- Tear down automatically when the Nexus buffer goes away.
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = M._augroup,
    buffer = buf,
    callback = function() M.stop() end,
  })
end

--- Stop watching. Idempotent. Releases the fs_event handle, debounce timer,
--- and autocmd group.
function M.stop()
  safe_close(M._timer);     M._timer = nil
  safe_close(M._fs_handle); M._fs_handle = nil
  if M._augroup then
    pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
    M._augroup = nil
  end
  M._buf = nil
  M._git_dir = nil
end

return M
