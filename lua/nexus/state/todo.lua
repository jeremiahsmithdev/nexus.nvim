--[[
Todo state — multi-session safe.

The on-disk file (.nexus-todo.json at git root) is the single source of truth.
Every mutation re-reads the file, applies the change, and writes atomically.
The in-memory `state.get('todo','items')` is only a UI cache for renderers.

Concurrency model: per-record last-writer-wins by `updated_at`. Deletes use
tombstones (`deleted=true, deleted_at=ts`) so a parallel session can't
resurrect a deleted item by writing a stale snapshot. Tombstones older than
the TTL are pruned on load.

Atomic write: temp file + fs_rename. POSIX rename(2) is atomic on the same
filesystem, so a reader either sees the old file or the new one — never a
half-written one.
]]

local M = {}

local state = require('nexus.state')
local git_utils = require('nexus.git.utils')
local logger = require('nexus.logger')

local TODO_FILENAME = '.nexus-todo.json'
local TOMBSTONE_TTL_SECONDS = 7 * 24 * 3600

local function get_todo_file_path()
  local git_root = git_utils.get_git_root()
  if not git_root then return nil end
  return git_root .. '/' .. TODO_FILENAME
end

local function now_ts()
  return os.time()
end

-- Read and parse the JSON list at `path`. Returns nil on any failure so the
-- caller can decide whether to fall back to a backup. No pruning here.
local function read_raw(path)
  if not path then return nil end
  local file = io.open(path, 'r')
  if not file then return nil end
  local content = file:read('*a')
  file:close()
  if not content or content == '' then return nil end
  local ok, items = pcall(vim.json.decode, content)
  if not ok or type(items) ~= 'table' then return nil end
  return items
end

-- Read items from disk. If the main file is missing, empty, or unparseable,
-- transparently fall back to the .bak we wrote on the previous successful
-- save. Tombstones older than the TTL are pruned.
local function read_disk()
  local file_path = get_todo_file_path()
  if not file_path then return {} end

  local items = read_raw(file_path)
  if not items then
    items = read_raw(file_path .. '.bak')
    if items then
      logger.warn('TODO', 'Main file unreadable; recovered from .bak', {
        file_path = file_path,
      })
    else
      return {}
    end
  end

  local cutoff = now_ts() - TOMBSTONE_TTL_SECONDS
  local pruned = {}
  for _, t in ipairs(items) do
    if not (t.deleted and (t.deleted_at or 0) < cutoff) then
      table.insert(pruned, t)
    end
  end
  return pruned
end

-- Atomic write: temp file + rename. Uses libuv so we get proper error codes.
local function write_disk(items)
  local file_path = get_todo_file_path()
  if not file_path then
    logger.warn('TODO', 'No git root found, cannot save todos')
    return false
  end

  local ok, json_content = pcall(vim.json.encode, items)
  if not ok then
    logger.error('TODO', 'Failed to encode todos', { error = json_content })
    return false
  end

  local tmp_path = file_path .. '.tmp.' .. vim.fn.getpid()
  local fd = vim.uv.fs_open(tmp_path, 'w', 420) -- 0644
  if not fd then
    logger.error('TODO', 'Failed to open temp file', { path = tmp_path })
    return false
  end
  vim.uv.fs_write(fd, json_content, 0)
  vim.uv.fs_close(fd)

  local rename_ok, rename_err = vim.uv.fs_rename(tmp_path, file_path)
  if not rename_ok then
    logger.error('TODO', 'Atomic rename failed', { err = rename_err })
    pcall(vim.uv.fs_unlink, tmp_path)
    return false
  end
  return true
end

-- Merge `incoming` into `base` by id. Per-id last-writer-wins on updated_at.
-- Items only on one side are kept. Used when bulk-replacing — single-item
-- mutations don't need this because they read-then-write on the same list.
local function merge_by_id(base, incoming)
  local by_id = {}
  for _, t in ipairs(base) do by_id[t.id] = t end
  for _, t in ipairs(incoming) do
    local existing = by_id[t.id]
    if not existing or (t.updated_at or 0) > (existing.updated_at or 0) then
      by_id[t.id] = t
    end
  end
  local out = {}
  for _, t in pairs(by_id) do table.insert(out, t) end
  table.sort(out, function(a, b)
    local ap = a.display_position or math.huge
    local bp = b.display_position or math.huge
    if ap ~= bp then return ap < bp end
    return (a.created_at or 0) > (b.created_at or 0)
  end)
  return out
end

-- Sync the in-memory cache to whatever's on disk. Active items only.
local function sync_state_cache(items)
  local active = {}
  for _, t in ipairs(items) do
    if not t.deleted then table.insert(active, t) end
  end
  state.set('todo', 'items', active)
  state.set('todo', 'loaded', true)
  return active
end

-- Find the array index of an item with `id` in `list`, or nil.
local function find_index(list, id)
  for i, t in ipairs(list) do
    if t.id == id then return i end
  end
  return nil
end

-- Public: initialize. Loads from disk into the UI cache.
function M.init()
  local items = read_disk()
  local active = sync_state_cache(items)
  logger.info('TODO', 'Todo state initialized', { count = #active })
end

-- Public: get active todos (for rendering). Filters tombstones.
function M.get_todos()
  if not state.get('todo', 'loaded') then M.init() end
  return state.get('todo', 'items') or {}
end

-- Public: force a re-read from disk into the UI cache. Returns active todos.
function M.refresh()
  local items = read_disk()
  return sync_state_cache(items)
end

-- Public: lookup by id. Reads from cache (fine for read-only paths).
function M.get_todo_by_id(id)
  for _, t in ipairs(M.get_todos()) do
    if t.id == id then return t end
  end
  return nil
end

function M.get_todo_by_position(position)
  for _, t in ipairs(M.get_todos()) do
    if t.display_position == position then return t end
  end
  return nil
end

-- Internal: read-modify-write helper. `mutate(items)` mutates the disk-fresh
-- list in place and returns (ok, result, error). The list is then written and
-- the cache synced. This is the safe pattern that prevents lost updates.
local function rmw(mutate)
  local items = read_disk()
  local ok, result, err = mutate(items)
  if not ok then return nil, err end
  if not write_disk(items) then return nil, 'Failed to save todo file' end
  sync_state_cache(items)
  return result
end

function M.add_todo(text)
  if not text or text == '' then return nil, 'Todo text cannot be empty' end

  local new_todo
  return rmw(function(items)
    new_todo = {
      id = tostring(now_ts()) .. '-' .. vim.fn.getpid() .. '-' .. math.random(100000, 999999),
      text = text,
      completed = false,
      important = false,
      created_at = now_ts(),
      updated_at = now_ts(),
      display_position = nil,
    }
    table.insert(items, 1, new_todo)
    logger.info('TODO', 'Added todo', { id = new_todo.id, text = text })
    return true, new_todo
  end)
end

function M.edit_todo(id, new_text)
  if not id or not new_text or new_text == '' then
    return nil, 'Invalid todo ID or text'
  end
  return rmw(function(items)
    local idx = find_index(items, id)
    if not idx or items[idx].deleted then return false, nil, 'Todo not found' end
    items[idx].text = new_text
    items[idx].updated_at = now_ts()
    logger.info('TODO', 'Edited todo', { id = id, new_text = new_text })
    return true, items[idx]
  end)
end

function M.mark_todo_done(id)
  if not id then return nil, 'Invalid todo ID' end
  return rmw(function(items)
    local idx = find_index(items, id)
    if not idx or items[idx].deleted then return false, nil, 'Todo not found' end
    items[idx].completed = true
    items[idx].updated_at = now_ts()
    logger.info('TODO', 'Marked todo done', { id = id })
    return true, items[idx]
  end)
end

function M.toggle_important(id)
  if not id then return nil, 'Invalid todo ID' end
  return rmw(function(items)
    local idx = find_index(items, id)
    if not idx or items[idx].deleted then return false, nil, 'Todo not found' end
    items[idx].important = not items[idx].important
    items[idx].updated_at = now_ts()
    logger.info('TODO', 'Toggled important', { id = id, important = items[idx].important })
    return true, items[idx]
  end)
end

-- Tombstone delete: mark deleted instead of removing. A parallel session
-- holding a stale "alive" copy of this item will lose to the tombstone on
-- merge because its updated_at will be older.
function M.delete_todo(id)
  if not id then return false, 'Invalid todo ID' end
  local result, err = rmw(function(items)
    local idx = find_index(items, id)
    if not idx or items[idx].deleted then return false, nil, 'Todo not found' end
    items[idx].deleted = true
    items[idx].deleted_at = now_ts()
    items[idx].updated_at = now_ts()
    logger.info('TODO', 'Deleted todo', { id = id })
    return true, true
  end)
  if result == nil then return false, err end
  return true
end

function M.clear_completed()
  local removed_count = 0
  local result, err = rmw(function(items)
    for _, t in ipairs(items) do
      if t.completed and not t.deleted then
        t.deleted = true
        t.deleted_at = now_ts()
        t.updated_at = now_ts()
        removed_count = removed_count + 1
      end
    end
    logger.info('TODO', 'Cleared completed todos', { removed_count = removed_count })
    return true, true
  end)
  if not result then return nil, err end
  return M.get_todos(), removed_count
end

-- Bulk replace from the "edit all" popup. Re-read disk first so additions
-- from another session aren't lost. Items removed by the user become
-- tombstones; items added by other sessions (not in our snapshot) are kept.
function M.replace_all(new_todos)
  local disk_items = read_disk()
  local incoming_ids = {}
  for _, t in ipairs(new_todos) do incoming_ids[t.id] = true end

  -- Snapshot of what was visible in the UI when the bulk editor opened.
  local snapshot_ids = {}
  for _, t in ipairs(state.get('todo', 'items') or {}) do
    snapshot_ids[t.id] = true
  end

  local merged = {}
  local seen = {}

  -- Items the user kept/edited.
  for _, t in ipairs(new_todos) do
    table.insert(merged, t)
    seen[t.id] = true
  end

  -- Reconcile against disk.
  for _, t in ipairs(disk_items) do
    if not seen[t.id] then
      if snapshot_ids[t.id] then
        -- User saw it and removed it from the popup: tombstone.
        t.deleted = true
        t.deleted_at = now_ts()
        t.updated_at = now_ts()
      end
      -- Either tombstone-of-removal or external addition: include it.
      table.insert(merged, t)
      seen[t.id] = true
    end
  end

  if not write_disk(merged) then
    logger.error('TODO', 'Failed to save bulk-edited todos')
    return false
  end
  sync_state_cache(merged)
  logger.info('TODO', 'Replaced all todos', { count = #new_todos })
  return true
end

function M.update_display_positions(display_order)
  return rmw(function(items)
    local pos_by_id = {}
    for position, todo in ipairs(display_order) do
      pos_by_id[todo.id] = position
    end
    for _, t in ipairs(items) do
      t.display_position = pos_by_id[t.id]
    end
    return true, true
  end)
end

-- Watch the todo file for external changes. Calls `on_change` (scheduled to
-- the main loop) after re-reading and updating the cache. Returns a handle
-- with :stop() so callers can clean up.
function M.start_file_watcher(on_change)
  local file_path = get_todo_file_path()
  if not file_path then return nil end

  local handle = vim.uv.new_fs_event()
  if not handle then return nil end

  local ok, err = pcall(function()
    handle:start(file_path, {}, function(watch_err)
      if watch_err then return end
      vim.schedule(function()
        M.refresh()
        if on_change then pcall(on_change) end
      end)
    end)
  end)

  if not ok then
    logger.warn('TODO', 'fs_event start failed', { err = err })
    pcall(function() handle:close() end)
    return nil
  end

  return {
    stop = function()
      pcall(function() handle:stop() end)
      pcall(function() handle:close() end)
    end,
  }
end

return M
