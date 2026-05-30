--- nexus/git/root.lua
--- Memoized git root resolver. Returns the top-level git repository path for
--- the current working directory, caching the result per-cwd so repeated callers
--- pay only one shell invocation even across multiple requires.
---
--- The cwd guard is required because the user may `:cd` between repos in a
--- session; a naive module-level cache would return stale data for the second repo.

local M = {}

local _cached_root = nil
local _cache_cwd   = nil

---Return the git repository root for the current working directory, or nil if
---not inside a git repo. Result is memoized per-cwd.
---@return string|nil root Absolute path with no trailing newline, or nil
function M.get()
  local cwd = vim.fn.getcwd()
  if _cached_root ~= nil and _cache_cwd == cwd then
    return _cached_root
  end
  local result = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null')
  if vim.v.shell_error ~= 0 then
    -- Not a git repo (or git not found) — cache nil so we don't retry on every call
    _cached_root = false
    _cache_cwd   = cwd
    return nil
  end
  _cached_root = result:gsub('%s+$', '')
  _cache_cwd   = cwd
  return _cached_root
end

---Cheap yes/no "are we inside a git repo?" check that spawns NO subprocess.
---
---Walks up from the current working directory looking for a `.git` entry
---(directory in the normal case, a file for worktrees/submodules) using
---vim.uv.fs_stat — sub-millisecond versus the ~10-30ms of a `git rev-parse`
---process spawn. Used at the VimEnter gate, where we only need the boolean and
---must answer synchronously before Vim paints its intro screen.
---
---This deliberately does NOT resolve the canonical root path. Use M.get() when
---you need the path: it shells out to `git rev-parse --show-toplevel` so its
---result matches the symlink-resolved cwd that Claude/cache keys compare against.
---@return boolean
function M.is_repo()
  -- An explicit git environment means we're in a repo regardless of layout.
  if vim.env.GIT_DIR and vim.env.GIT_DIR ~= '' then
    return true
  end
  local uv = vim.uv or vim.loop
  local dir = vim.fn.getcwd()
  while dir and dir ~= '' do
    if uv.fs_stat(dir .. '/.git') then
      return true
    end
    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then
      break -- reached filesystem root
    end
    dir = parent
  end
  return false
end

---Invalidate the memoized root. Call this if the user changes into a new
---directory and you need to force re-detection on the next M.get() call.
function M.invalidate()
  _cached_root = nil
  _cache_cwd   = nil
end

return M
