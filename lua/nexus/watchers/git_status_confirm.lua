--- lua/nexus/watchers/git_status_confirm.lua
---
--- Change-suspicion sink. Cheap, broad signals (gitdir fs_events, BufWritePost,
--- FocusGained, CursorHold) all "poke" this module. A debounced runner then
--- executes `git status --porcelain=v2` and hashes the output. The downstream
--- refresh only fires when the hash differs from the previous run.
---
--- Why this design (and why earlier ones didn't work):
---   * Recursive fs_event on the working tree — atime wakes from external
---     stat() calls flood the loop. Filtering by .gitignore per-event is
---     expensive and incomplete.
---   * BufWritePost as a render trigger — only catches edits from this nvim;
---     misses VSCode, sed, other nvim instances.
---   * FocusGained as a render trigger — fired on every tmux pane switch and
---     re-rendered against the wrong window width.
---
--- This module accepts the same noisy signals but uses them only as
--- *suspicions*: actual visible work happens only when `git status` output
--- has actually changed. False wakes cost one ~5–10 ms subprocess and stop
--- there.
---
--- For large repos, users should enable git's built-in fsmonitor to make
--- the confirm step near-free:
---     git config core.fsmonitor true
---     git config core.untrackedCache true
--- (See `git help fsmonitor--daemon`.) This plugin will not change git
--- config; it's a user opt-in.

local M = {}

local uv = vim.uv or vim.loop

local state = {
  buf             = nil,
  repo_root       = nil,
  refresh         = nil,    -- function(buf) -> downstream refresh sink
  debounce_ms     = 150,
  hold_throttle_s = 10,
  last_hash       = nil,
  last_confirm_ns = 0,
  timer           = nil,
  augroup         = nil,
  inflight        = false,
}

-- djb2 over the porcelain bytes. Fast in LuaJIT, collision-safe enough for
-- "did the output change" — worst case is one missed refresh that the next
-- signal will correct.
local function hash_bytes(s)
  if not s or s == '' then return 0 end
  local h = 5381
  for i = 1, #s do
    h = ((h * 33) + s:byte(i)) % 2147483647
  end
  return h
end

local function run_status(on_done)
  local cmd = {
    'git', '-C', state.repo_root,
    'status', '--porcelain=v2', '-z', '--untracked-files=all',
    'HEAD',
  }
  if vim.system then
    vim.system(cmd, { text = true, timeout = 2000 }, vim.schedule_wrap(function(res)
      on_done(res.code == 0 and (res.stdout or '') or nil)
    end))
  else
    -- Fallback for nvim < 0.10. jobstart is async; collect stdout.
    local chunks = {}
    vim.fn.jobstart(cmd, {
      stdout_buffered = true,
      on_stdout = function(_, data) if data then vim.list_extend(chunks, data) end end,
      on_exit = function(_, code)
        vim.schedule(function()
          on_done(code == 0 and table.concat(chunks, '\n') or nil)
        end)
      end,
    })
  end
end

local function confirm()
  if state.inflight or not state.refresh or not state.repo_root then return end
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
  state.inflight = true
  state.last_confirm_ns = uv.hrtime()
  run_status(function(output)
    state.inflight = false
    if output == nil then return end
    local h = hash_bytes(output)
    if state.last_hash == nil then
      -- Priming run: capture the baseline without firing a refresh.
      state.last_hash = h
      return
    end
    if h ~= state.last_hash then
      state.last_hash = h
      if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        state.refresh(state.buf)
      end
    end
  end)
end

local function schedule_confirm()
  if not state.refresh then return end
  if not state.timer then state.timer = uv.new_timer() end
  if state.timer:is_closing() then
    state.timer = uv.new_timer()
  end
  state.timer:stop()
  state.timer:start(state.debounce_ms, 0, vim.schedule_wrap(confirm))
end

--- Any subsystem with a change suspicion calls this. Cheap and idempotent;
--- many calls inside the debounce window collapse to one git status run.
function M.poke()
  schedule_confirm()
end

--- Begin watching. The downstream `refresh(buf)` is invoked only when
--- `git status` output hash actually differs from the previous run.
---@param buf number          Nexus dashboard buffer
---@param opts table {
---   repo_root: string,
---   refresh: function(buf),
---   debounce_ms?: number   = 150
---   hold_throttle_s?: number = 10
--- }
function M.start(buf, opts)
  M.stop()
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  if not (opts and opts.repo_root and opts.refresh) then return end

  state.buf             = buf
  state.repo_root       = opts.repo_root
  state.refresh         = opts.refresh
  state.debounce_ms     = tonumber(opts.debounce_ms)     or 150
  state.hold_throttle_s = tonumber(opts.hold_throttle_s) or 10
  state.last_hash       = nil
  state.last_confirm_ns = 0

  local g = vim.api.nvim_create_augroup('NexusGitStatusConfirm_' .. buf, { clear = true })
  state.augroup = g

  -- BufWritePost: this-nvim save inside the repo. Cheap fast path; the
  -- hash gate downstream absorbs writes that don't change `git status`.
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = g,
    callback = function(ev)
      if ev.buf == state.buf then return end
      local fname = vim.api.nvim_buf_get_name(ev.buf)
      if fname == '' then return end
      if not fname:find(state.repo_root, 1, true) then return end
      schedule_confirm()
    end,
  })

  -- FocusGained: regaining focus from VSCode / another terminal / tmux pane
  -- (with focus-events on). No render unless the hash actually differs, so
  -- spurious tmux pane switches are free.
  vim.api.nvim_create_autocmd('FocusGained', {
    group = g,
    callback = schedule_confirm,
  })

  -- CursorHold: safety net for "another tool edited a file while nvim is
  -- foregrounded and the cursor hasn't moved." Throttled — we only confirm
  -- when more than `hold_throttle_s` has elapsed since the last confirm.
  vim.api.nvim_create_autocmd('CursorHold', {
    group = g,
    callback = function()
      local since_s = (uv.hrtime() - state.last_confirm_ns) / 1e9
      if since_s >= state.hold_throttle_s then schedule_confirm() end
    end,
  })

  -- Prime the baseline hash so the first real change fires a refresh.
  confirm()
end

--- Stop watching. Idempotent.
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
end

return M
