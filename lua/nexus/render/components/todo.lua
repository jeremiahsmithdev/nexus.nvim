---@class TodoComponent
local M = {}

local todo_state = require('nexus.state.todo')
local logger = require('nexus.logger')

-- Store mapping of line numbers to todo IDs for the current render
-- This will be populated during rendering with absolute line numbers
local _line_to_todo_map = {}
local _todos_cache = {} -- Cache todos for lookup

-- Icons for todo states
local ICONS = {
  todo = "☐",
  done = "✓",
  error = "❌",
  info = "ℹ️",
  empty = "📝"
}

---Build Todo section
---@param config table Nexus configuration
---@return table section
function M.build_todo_section(config)
  local config_module = require('nexus.config')
  local is_enabled = config_module.is_section_enabled("todos")
  logger.debug("TODO", "Building Todo section", { enabled = is_enabled })

  if not is_enabled then
    return {}
  end
  
  local lines = {}
  
  -- Section header
  table.insert(lines, "Todo:")
  table.insert(lines, "")
  
  -- Get todos from state
  local todos = todo_state.get_todos()
  if not todos or #todos == 0 then
    table.insert(lines, "  " .. ICONS.empty .. " No todos (press 'c' to create)")
    table.insert(lines, "")
    return lines
  end
  
  -- Clear previous caches
  _todos_cache = {}
  _line_to_todo_map = {}
  
  -- Store todos in cache for lookup
  for _, todo in ipairs(todos) do
    _todos_cache[todo.id] = todo
  end
  
  -- Separate active and completed todos  
  local active_todos = {}
  local completed_todos = {}
  
  for _, todo in ipairs(todos) do
    if todo.completed then
      table.insert(completed_todos, todo)
    else
      table.insert(active_todos, todo)
    end
  end
  
  -- Keep track of todos in display order
  local display_todos = {}
  
  -- Render active todos first
  local max_todos = config.max_todos or 10
  local total_displayed = 0
  
  for i, todo in ipairs(active_todos) do
    if total_displayed >= max_todos then
      break
    end
    
    local todo_line = M.format_todo_line(todo, false)
    table.insert(lines, "  " .. todo_line)
    table.insert(display_todos, todo)
    total_displayed = total_displayed + 1
  end
  
  -- Add completed todos (up to remaining limit)
  for i, todo in ipairs(completed_todos) do
    if total_displayed >= max_todos then
      break
    end
    
    local todo_line = M.format_todo_line(todo, true)
    table.insert(lines, "  " .. todo_line)
    table.insert(display_todos, todo)
    total_displayed = total_displayed + 1
  end
  
  -- Update display positions in the JSON file
  todo_state.update_display_positions(display_todos)
  
  -- Show summary if there are more todos
  local remaining_active = math.max(0, #active_todos - total_displayed)
  local remaining_completed = math.max(0, #completed_todos - (total_displayed - math.min(total_displayed, #active_todos)))
  
  if remaining_active > 0 or remaining_completed > 0 then
    local summary_parts = {}
    if remaining_active > 0 then
      table.insert(summary_parts, string.format("%d more active", remaining_active))
    end
    if remaining_completed > 0 then
      table.insert(summary_parts, string.format("%d more completed", remaining_completed))
    end
    table.insert(lines, string.format("  ... and %s", table.concat(summary_parts, ", ")))
  end

  return lines
end

---Apply todo highlighting to buffer
---@param buf number Buffer handle
---@param todo_section_start number Start line of todo section
function M.apply_todo_highlighting(buf, todo_section_start)
  local todo_ns = vim.api.nvim_create_namespace('nexus_todo')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  
  -- Highlight todo items
  for i = todo_section_start + 2, #lines do -- +2 to skip header and empty line
    local line_content = lines[i]
    if not line_content or line_content == "" then
      break -- End of section
    end
    
    -- Check if it's a todo line with completed tick
    if line_content:match("^%s*✓") then
      local tick_start, tick_end = line_content:find('✓')
      if tick_start then
        vim.api.nvim_buf_add_highlight(buf, todo_ns, 'DiagnosticOk', i - 1, tick_start - 1, tick_end)
      end
    end
  end
end

---Format single todo line
---@param todo table Todo item data
---@param is_completed boolean Whether this is in the completed section
---@return string formatted_line
function M.format_todo_line(todo, is_completed)
  local icon = todo.completed and ICONS.done or ICONS.todo
  local text = todo.text
  
  -- Truncate long todo text
  local max_length = 80
  if #text > max_length then
    text = text:sub(1, max_length - 3) .. "..."
  end
  
  local line = string.format("%s %s", icon, text)
  
  return line
end

---Get todo ID from line number using position lookup
---@param line_num number The line number in the buffer
---@return string? todo_id The todo ID, or nil if not found
function M.get_todo_id_from_line_num(line_num)
  -- Find the Todo section header first
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  
  local todo_header_line = nil
  for i, line in ipairs(lines) do
    if line:match("^%s*Todo:") then -- Allow for centered spacing
      todo_header_line = i
      break
    end
  end
  
  if not todo_header_line then
    return nil
  end
  
  -- Calculate position relative to Todo section start
  -- Todo section structure: "Todo:", "", first todo (pos 1), second todo (pos 2)...
  local position = line_num - todo_header_line - 1 -- -1 for the empty line after header
  
  -- Debug logging
  local logger = require('nexus.logger')
  logger.debug('TODO_LOOKUP', 'Looking up todo', { 
    line_num = line_num,
    todo_header_line = todo_header_line,
    calculated_position = position
  })
  
  -- Get todo by position from JSON file
  local todo = todo_state.get_todo_by_position(position)
  
  logger.debug('TODO_LOOKUP', 'Found todo', { 
    position = position,
    found_todo = todo and todo.text or 'nil',
    todo_id = todo and todo.id or 'nil'
  })
  
  return todo and todo.id or nil
end

---Get todo text from a todo line (for display purposes)
---@param line string The todo line text
---@return string todo_text The clean todo text without icon
function M.get_todo_text_from_line(line)
  -- Remove the icon and clean up whitespace
  local text = line:gsub("^%s*[☐✓]%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

---Check if a line is a todo line
---@param line string The line to check
---@return boolean is_todo_line Whether the line represents a todo item
function M.is_todo_line(line)
  return line:match("^%s*[☐✓]%s*.+") ~= nil
end

return M