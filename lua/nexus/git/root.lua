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

---Invalidate the memoized root. Call this if the user changes into a new
---directory and you need to force re-detection on the next M.get() call.
function M.invalidate()
  _cached_root = nil
  _cache_cwd   = nil
end

return M
