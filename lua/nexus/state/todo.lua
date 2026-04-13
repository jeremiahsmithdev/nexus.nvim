local M = {}

local state = require('nexus.state')
local git_utils = require('nexus.git.utils')
local logger = require('nexus.logger')

-- Todo file name (stored in git repo root)
local TODO_FILENAME = '.nexus-todo.json'

-- Get todo file path for current git repository
local function get_todo_file_path()
  local git_root = git_utils.get_git_root()
  if not git_root then
    return nil
  end
  return git_root .. '/' .. TODO_FILENAME
end

-- Load todos from file
local function load_todos_from_file()
  local file_path = get_todo_file_path()
  if not file_path then
    logger.debug('TODO', 'No git root found, cannot load todos')
    return {}
  end
  
  local file = io.open(file_path, 'r')
  if not file then
    logger.debug('TODO', 'Todo file does not exist, starting with empty list', { file_path = file_path })
    return {}
  end
  
  local content = file:read('*a')
  file:close()
  
  if not content or content == '' then
    return {}
  end
  
  local ok, todos = pcall(vim.json.decode, content)
  if not ok then
    logger.warn('TODO', 'Failed to parse todo file, starting with empty list', { 
      file_path = file_path,
      error = todos 
    })
    return {}
  end
  
  logger.debug('TODO', 'Loaded todos from file', { 
    file_path = file_path,
    count = #todos 
  })
  
  return todos or {}
end

-- Save todos to file
local function save_todos_to_file(todos)
  local file_path = get_todo_file_path()
  if not file_path then
    logger.warn('TODO', 'No git root found, cannot save todos')
    return false
  end
  
  local ok, json_content = pcall(vim.json.encode, todos)
  if not ok then
    logger.error('TODO', 'Failed to encode todos to JSON', { error = json_content })
    return false
  end
  
  local file = io.open(file_path, 'w')
  if not file then
    logger.error('TODO', 'Failed to open todo file for writing', { file_path = file_path })
    return false
  end
  
  file:write(json_content)
  file:close()
  
  logger.debug('TODO', 'Saved todos to file', { 
    file_path = file_path,
    count = #todos 
  })
  
  return true
end

-- Initialize todo state
function M.init()
  local todos = load_todos_from_file()
  state.set('todo', 'items', todos)
  state.set('todo', 'loaded', true)
  
  logger.info('TODO', 'Todo state initialized', { count = #todos })
end

-- Get all todos
function M.get_todos()
  if not state.get('todo', 'loaded') then
    M.init()
  end
  return state.get('todo', 'items') or {}
end

-- Ensure todo state is initialized (lazy loading)
local function ensure_initialized()
  if not state.get('todo', 'loaded') then
    M.init()
  end
end

-- Add a new todo item
function M.add_todo(text)
  if not text or text == '' then
    return nil, 'Todo text cannot be empty'
  end

  ensure_initialized()
  local todos = M.get_todos()
  local new_todo = {
    id = tostring(os.time() .. math.random(1000, 9999)), -- Simple ID generation
    text = text,
    completed = false,
    important = false,
    created_at = os.time(),
    updated_at = os.time(),
    display_position = nil -- Will be set during rendering
  }
  
  table.insert(todos, new_todo)
  state.set('todo', 'items', todos)
  
  local success = save_todos_to_file(todos)
  if not success then
    return nil, 'Failed to save todo to file'
  end
  
  logger.info('TODO', 'Added new todo', { id = new_todo.id, text = text })
  state.notify('todo', 'item_added', new_todo, todos)
  
  return new_todo
end

-- Edit a todo item
function M.edit_todo(id, new_text)
  if not id or not new_text or new_text == '' then
    return nil, 'Invalid todo ID or text'
  end

  ensure_initialized()
  local todos = M.get_todos()
  local todo_index = nil
  
  for i, todo in ipairs(todos) do
    if todo.id == id then
      todo_index = i
      break
    end
  end
  
  if not todo_index then
    return nil, 'Todo not found'
  end
  
  local old_text = todos[todo_index].text
  todos[todo_index].text = new_text
  todos[todo_index].updated_at = os.time()
  
  state.set('todo', 'items', todos)
  
  local success = save_todos_to_file(todos)
  if not success then
    return nil, 'Failed to save todo changes'
  end
  
  logger.info('TODO', 'Edited todo', { 
    id = id, 
    old_text = old_text, 
    new_text = new_text 
  })
  state.notify('todo', 'item_updated', todos[todo_index], todos)
  
  return todos[todo_index]
end

-- Mark a todo as done/completed
function M.mark_todo_done(id)
  if not id then
    return nil, 'Invalid todo ID'
  end

  ensure_initialized()
  local todos = M.get_todos()
  local todo_index = nil
  
  for i, todo in ipairs(todos) do
    if todo.id == id then
      todo_index = i
      break
    end
  end
  
  if not todo_index then
    return nil, 'Todo not found'
  end
  
  todos[todo_index].completed = true
  todos[todo_index].updated_at = os.time()
  
  state.set('todo', 'items', todos)
  
  local success = save_todos_to_file(todos)
  if not success then
    return nil, 'Failed to save todo changes'
  end
  
  logger.info('TODO', 'Marked todo as done', { 
    id = id, 
    text = todos[todo_index].text 
  })
  state.notify('todo', 'item_completed', todos[todo_index], todos)
  
  return todos[todo_index]
end

-- Toggle important flag on a todo
function M.toggle_important(id)
  if not id then
    return nil, 'Invalid todo ID'
  end

  ensure_initialized()
  local todos = M.get_todos()
  local todo_index = nil

  for i, todo in ipairs(todos) do
    if todo.id == id then
      todo_index = i
      break
    end
  end

  if not todo_index then
    return nil, 'Todo not found'
  end

  todos[todo_index].important = not todos[todo_index].important
  todos[todo_index].updated_at = os.time()

  state.set('todo', 'items', todos)

  local success = save_todos_to_file(todos)
  if not success then
    return nil, 'Failed to save todo changes'
  end

  local status = todos[todo_index].important and 'important' or 'normal'
  logger.info('TODO', 'Toggled todo importance', {
    id = id,
    text = todos[todo_index].text,
    important = todos[todo_index].important
  })
  state.notify('todo', 'item_updated', todos[todo_index], todos)

  return todos[todo_index]
end

-- Remove completed todos
function M.clear_completed()
  ensure_initialized()
  local todos = M.get_todos()
  local active_todos = {}
  local removed_count = 0
  
  for _, todo in ipairs(todos) do
    if not todo.completed then
      table.insert(active_todos, todo)
    else
      removed_count = removed_count + 1
    end
  end
  
  state.set('todo', 'items', active_todos)
  
  local success = save_todos_to_file(active_todos)
  if not success then
    return nil, 'Failed to save todo changes'
  end
  
  logger.info('TODO', 'Cleared completed todos', { removed_count = removed_count })
  state.notify('todo', 'items_cleared', removed_count, active_todos)
  
  return active_todos, removed_count
end

-- Get todo by ID
function M.get_todo_by_id(id)
  ensure_initialized()
  local todos = M.get_todos()
  for _, todo in ipairs(todos) do
    if todo.id == id then
      return todo
    end
  end
  return nil
end

-- Force refresh todos from file
function M.refresh()
  local todos = load_todos_from_file()
  state.set('todo', 'items', todos)
  state.notify('todo', 'refreshed', todos)
  return todos
end

-- Update display positions and save to file
function M.update_display_positions(display_order)
  ensure_initialized()
  local todos = M.get_todos()
  
  -- Clear all positions first
  for _, todo in ipairs(todos) do
    todo.display_position = nil
  end
  
  -- Set positions based on display order
  for position, todo in ipairs(display_order) do
    todo.display_position = position
  end
  
  -- Save updated todos with positions
  state.set('todo', 'items', todos)
  save_todos_to_file(todos)
  
  logger.debug('TODO', 'Updated display positions', { count = #display_order })
end

-- Get todo by display position
function M.get_todo_by_position(position)
  ensure_initialized()
  local todos = M.get_todos()
  for _, todo in ipairs(todos) do
    if todo.display_position == position then
      return todo
    end
  end
  return nil
end

-- Replace all todos (used by bulk edit)
function M.replace_all(new_todos)
  state.set('todo', 'items', new_todos)
  local success = save_todos_to_file(new_todos)
  if not success then
    logger.error('TODO', 'Failed to save bulk-edited todos')
    return false
  end
  logger.info('TODO', 'Replaced all todos', { count = #new_todos })
  state.notify('todo', 'items_replaced', new_todos)
  return true
end

-- Delete a todo item
function M.delete_todo(id)
  if not id then
    return false, 'Invalid todo ID'
  end

  ensure_initialized()
  local todos = M.get_todos()
  local todo_index = nil
  local todo_to_delete = nil
  
  for i, todo in ipairs(todos) do
    if todo.id == id then
      todo_index = i
      todo_to_delete = todo
      break
    end
  end
  
  if not todo_index then
    return false, 'Todo not found'
  end
  
  -- Remove the todo from the list
  table.remove(todos, todo_index)
  
  state.set('todo', 'items', todos)
  
  local success = save_todos_to_file(todos)
  if not success then
    return false, 'Failed to save todo changes'
  end
  
  logger.info('TODO', 'Deleted todo', { 
    id = id, 
    text = todo_to_delete.text 
  })
  state.notify('todo', 'item_deleted', todo_to_delete, todos)
  
  return true
end

return M