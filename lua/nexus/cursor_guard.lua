--[[
Cursor guard — single source of truth for "where can the cursor rest?"

The dashboard has zones the cursor must never sit in (logo, project_name
header, keyboard shortcuts, empty padding lines, section header titles).
Every previous attempt at this lived in a different module: navigation.lua
had its own predicate, init.lua hard-coded line 1, and nothing watched the
cursor after that. Tmux pane switches, gg/G, mouse clicks, or re-renders
that shifted content under a stationary cursor all left the cursor in
forbidden zones with nothing to pull it out.

This module owns the predicate (`is_forbidden_line`) and the enforcement
(`snap_to_legal` + the autocmd `install`). Other modules ask this module —
they do not re-derive the rules.
]]

local M = {}

-- Sections whose entire range is forbidden — cursor never rests here even
-- on lines that look "actionable" (e.g. the project name itself).
local FORBIDDEN_SECTIONS = {
  logo = true,
  project_name = true,
  keyboard_shortcuts = true,
}

--- Is the given line a place the cursor must not rest?
---@param buf number
---@param line_num number 1-indexed
---@return boolean
function M.is_forbidden_line(buf, line_num)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  if line_num < 1 then return true end

  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_num > line_count then return true end

  local section_ranges = vim.b[buf].nexus_section_ranges
  if section_ranges then
    for name, range in pairs(section_ranges) do
      if line_num >= range.start_line and line_num <= range.end_line then
        if FORBIDDEN_SECTIONS[name] then return true end
      end
    end
  end

  -- Read the actual line content for empty / header-title checks.
  local lines = vim.api.nvim_buf_get_lines(buf, line_num - 1, line_num, false)
  local line = lines[1]
  if not line then return true end

  if line:match("^%s*$") then return true end          -- empty / whitespace
  if line:match(":%s*$") then return true end          -- "Section Title:"

  return false
end

--- Find the nearest legal line to `from_line`, scanning forward then back.
--- Returns nil if the buffer has no legal line at all.
---@param buf number
---@param from_line number 1-indexed starting line
---@return number|nil
local function find_nearest_legal(buf, from_line)
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count == 0 then return nil end

  local start = math.max(1, math.min(from_line, line_count))

  for i = start, line_count do
    if not M.is_forbidden_line(buf, i) then return i end
  end
  for i = start - 1, 1, -1 do
    if not M.is_forbidden_line(buf, i) then return i end
  end
  return nil
end

--- If the cursor in a window showing `buf` is on a forbidden line, move it to
--- the nearest legal one. No-op if the cursor is already legal, or if no
--- window currently shows the buffer.
---@param buf number
function M.snap_to_legal(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      local cursor = vim.api.nvim_win_get_cursor(win)
      local line_num = cursor[1]
      if M.is_forbidden_line(buf, line_num) then
        local target = find_nearest_legal(buf, line_num)
        if target then
          pcall(vim.api.nvim_win_set_cursor, win, { target, 0 })
        end
      end
    end
  end
end

--- Install the per-buffer guard. Idempotent — uses a buffer-scoped augroup
--- name so re-running on the same buffer cleanly replaces prior autocmds.
---@param buf number
function M.install(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local group_name = 'NexusCursorGuard_' .. buf
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })

  -- Programmatic snap on every render or focus change. We schedule because
  -- some events fire mid-modify and reading the buffer needs a settled state.
  local function guarded_snap()
    vim.schedule(function() M.snap_to_legal(buf) end)
  end

  vim.api.nvim_create_autocmd(
    { 'CursorMoved', 'BufEnter', 'WinEnter', 'FocusGained' },
    {
      group = group,
      buffer = buf,
      callback = guarded_snap,
    }
  )

  vim.api.nvim_create_autocmd('BufDelete', {
    group = group,
    buffer = buf,
    callback = function()
      pcall(vim.api.nvim_del_augroup_by_name, group_name)
    end,
  })
end

return M
