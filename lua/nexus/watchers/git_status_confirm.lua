--- lua/nexus/watchers/git_status_confirm.lua
---
--- Hash-confirm gate. Every "something might have changed" signal lands here.
--- We coalesce with a 150ms debounce, then run a bundle of
---   * git status --porcelain=v2 -z --untracked-files=all
---   * git diff --numstat                  (unstaged +/- per file)
---   * git diff --cached --numstat         (staged   +/- per file)
--- hash the combined output, and only fire the downstream refresh when the
--- hash actually differs from what we last saw. The numstat folds are
--- required: porcelain=v2 only emits HEAD+index object hashes for modified
--- files, so it is *blind* to further worktree edits of an already-modified
--- file. Including numstat makes any +/- change move the bundle hash.
---
--- DESIGN NOTE (avoid the priming race):
---   We do NOT prime a baseline hash up-front. last_hash starts nil. The
---   first poke after start() runs git status; the hash differs from nil so
---   the refresh fires once (idempotent — refresh_buffer's own fingerprint
---   guard absorbs the no-op render). Every subsequent poke compares against
---   the previously seen hash. This avoids the race where an edit that
---   arrives during async priming gets silently folded into the baseline.

local M = {}

local uv = vim.uv or vim.loop

local LOG_PATH = '/tmp/nexus-watcher.log'

local state = {
  buf             = nil,
  repo_root       = nil,
  refresh         = nil,
  debounce_ms     = 150,
  hold_throttle_s = 10,
  debug           = false,
  last_hash       = nil,
  last_confirm_ns = 0,
  timer           = nil,
  augroup         = nil,
  inflight        = false,
  pending         = false,
}

local function log(msg)
  if not state.debug then return end
  pcall(function()
    local f = io.open(LOG_PATH, 'a')
    if not f then return end
    f:write(os.date('%H:%M:%S ') .. msg .. '\n')
    f:close()
  end)
end

local function hash_bytes(s)
  if not s or s == '' then return 0 end
  local h = 5381
  for i = 1, #s do
    h = ((h * 33) + s:byte(i)) % 2147483647
  end
  return h
end

-- Build the hashed bundle. porcelain=v2 alone can't see worktree-content
-- changes on already-modified files (it only emits HEAD+index object
-- hashes), so we also fold in diff --numstat (unstaged +/- per file) and
-- diff --cached --numstat (staged +/-). Any meaningful change to dashboard
-- content moves the bundle's hash.
local function run_status(on_done)
  local script = table.concat({
    'git status --porcelain=v2 -z --untracked-files=all',
    "printf '\\0DIFF\\0'",
    'git diff --numstat',
    "printf '\\0CACHED\\0'",
    'git diff --cached --numstat',
  }, '; ')
  local cmd = { 'sh', '-c', script }
  if vim.system then
    vim.system(cmd, { text = true, cwd = state.repo_root, timeout = 3000 }, vim.schedule_wrap(function(res)
      on_done(res.code == 0 and (res.stdout or '') or nil, res.code, res.stderr)
    end))
  else
    local chunks = {}
    local errs = {}
    vim.fn.jobstart(cmd, {
      cwd = state.repo_root,
      stdout_buffered = true, stderr_buffered = true,
      on_stdout = function(_, data) if data then vim.list_extend(chunks, data) end end,
      on_stderr = function(_, data) if data then vim.list_extend(errs, data) end end,
      on_exit = function(_, code)
        vim.schedule(function()
          on_done(code == 0 and table.concat(chunks, '\n') or nil, code, table.concat(errs, '\n'))
        end)
      end,
    })
  end
end

local function do_confirm()
  if not state.refresh or not state.repo_root then return end
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  if state.inflight then
    -- A confirm is already running. Queue another for when it returns so
    -- pokes that arrive mid-flight aren't silently lost.
    state.pending = true
    log('confirm queued (inflight)')
    return
  end
  state.inflight = true
  state.last_confirm_ns = uv.hrtime()
  log('git status running')
  run_status(function(output, code, stderr)
    state.inflight = false
    if output == nil then
      log(('git status FAILED code=%d stderr=%s'):format(code or -1, (stderr or ''):sub(1, 200)))
    else
      local h = hash_bytes(output)
      local same = (state.last_hash == h)
      log(('git status ok hash=%d prev=%s same=%s out_bytes=%d'):format(
        h, tostring(state.last_hash), tostring(same), #output))
      if not same then
        state.last_hash = h
        log('FIRING refresh')
        pcall(state.refresh, state.buf)
      end
    end
    if state.pending then
      state.pending = false
      log('draining pending confirm')
      vim.schedule(do_confirm)
    end
  end)
end

local function schedule_confirm()
  if not state.refresh then return end
  if not state.timer or state.timer:is_closing() then
    state.timer = uv.new_timer()
  end
  state.timer:stop()
  state.timer:start(state.debounce_ms, 0, vim.schedule_wrap(do_confirm))
end

function M.poke(source)
  log('poke from ' .. (source or '?'))
  schedule_confirm()
end

function M.start(buf, opts)
  M.stop()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  if not (opts and opts.repo_root and opts.refresh) then return end

  state.buf             = buf
  state.repo_root       = opts.repo_root
  state.refresh         = opts.refresh
  state.debounce_ms     = tonumber(opts.debounce_ms)     or 150
  state.hold_throttle_s = tonumber(opts.hold_throttle_s) or 10
  state.debug           = opts.debug == true
  state.last_hash       = nil
  state.last_confirm_ns = 0
  state.inflight        = false
  state.pending         = false

  if state.debug then
    pcall(function()
      local f = io.open(LOG_PATH, 'a')
      if f then f:write('\n===== watcher start ' .. os.date() .. ' repo=' .. state.repo_root .. ' =====\n'); f:close() end
    end)
  end
  log('start buf=' .. tostring(buf) .. ' debounce_ms=' .. state.debounce_ms)

  local g = vim.api.nvim_create_augroup('NexusGitStatusConfirm_' .. buf, { clear = true })
  state.augroup = g

  vim.api.nvim_create_autocmd('BufWritePost', {
    group = g,
    callback = function(ev)
      if ev.buf == state.buf then return end
      local fname = vim.api.nvim_buf_get_name(ev.buf)
      if fname == '' then return end
      if not fname:find(state.repo_root, 1, true) then return end
      M.poke('BufWritePost')
    end,
  })

  -- FocusGained: throttled identically to CursorHold. Some terminals/tmux
  -- emit focus events many times per second; un-throttled, each one spawns
  -- a git status subprocess for nothing (recursive tree watch already
  -- catches real edits).
  vim.api.nvim_create_autocmd('FocusGained', {
    group = g,
    callback = function()
      local since_s = (uv.hrtime() - state.last_confirm_ns) / 1e9
      if since_s >= state.hold_throttle_s then M.poke('FocusGained') end
    end,
  })

  vim.api.nvim_create_autocmd('CursorHold', {
    group = g,
    callback = function()
      local since_s = (uv.hrtime() - state.last_confirm_ns) / 1e9
      if since_s >= state.hold_throttle_s then M.poke('CursorHold') end
    end,
  })
end

function M.stop()
  if state.timer and not state.timer:is_closing() then
    pcall(function() state.timer:stop(); state.timer:close() end)
  end
  state.timer = nil
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    state.augroup = nil
  end
  state.buf = nil
  state.repo_root = nil
  state.refresh = nil
  state.last_hash = nil
  state.inflight = false
  state.pending = false
end

--- Expose state for diagnostic commands.
function M.debug_state()
  return {
    buf = state.buf,
    repo_root = state.repo_root,
    last_hash = state.last_hash,
    inflight = state.inflight,
    pending = state.pending,
    debounce_ms = state.debounce_ms,
    debug = state.debug,
  }
end

return M
