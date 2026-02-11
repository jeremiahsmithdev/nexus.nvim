---@class TodoKeymaps
local M = {}

local actions = require('nexus.actions')
local todo_state = require('nexus.state.todo')
local todo_component = require('nexus.render.components.todo')
local logger = require('nexus.logger')

--- Handle Enter key in todo section
function M.handle_enter(current_line, line_num, config)
  local todo_id = todo_component.get_todo_id_from_line_num(line_num)
  if todo_id then
    local todo = todo_state.get_todo_by_id(todo_id)
    if todo then
      M.show_todo_details(todo, config)
    end
  end
end

--- Handle 'c' key in todo section - create new todo
function M.handle_create(buf, render_callback, config)
  vim.ui.input({ 
    prompt = 'New todo: ',
    default = ''
  }, function(input)
    if input and #input > 0 then
      actions.execute('todo.create', {
        text = input
      })
      -- Refresh the buffer after creating todo
      render_callback(buf)
    end
  end)
end

--- Handle 'e' key in todo section - edit todo
function M.handle_edit(todo_id, buf, render_callback, config)
  local todo = todo_state.get_todo_by_id(todo_id)
  if not todo then
    vim.notify("Todo not found", vim.log.levels.ERROR)
    return
  end
  
  vim.ui.input({
    prompt = 'Edit todo: ',
    default = todo.text
  }, function(input)
    if input and #input > 0 and input ~= todo.text then
      actions.execute('todo.edit', {
        id = todo_id,
        text = input
      })
      -- Refresh the buffer after editing
      render_callback(buf)
    end
  end)
end

--- Handle 'd' key in todo section - mark todo as done
function M.handle_done(todo_id, buf, render_callback, config)
  actions.execute('todo.done', {
    id = todo_id
  })
  -- Refresh the buffer after marking done
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  render_callback(buf)
end

--- Handle '!' key in todo section - toggle important
function M.handle_important(todo_id, buf, render_callback, config)
  actions.execute('todo.important', {
    id = todo_id
  })
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  render_callback(buf)
end

--- Handle 'D' key in todo section - delete todo
function M.handle_delete(todo_id, buf, render_callback, config)
  local todo = todo_state.get_todo_by_id(todo_id)
  if not todo then
    vim.notify("Todo not found", vim.log.levels.ERROR)
    return
  end
  
  -- Confirm deletion
  vim.ui.select({'Yes', 'No'}, {
    prompt = string.format('Delete todo: "%s"?', todo.text)
  }, function(choice)
    if choice == 'Yes' then
      actions.execute('todo.delete', {
        id = todo_id
      })
      -- Refresh the buffer after deleting
      vim.api.nvim_buf_set_option(buf, 'modifiable', true)
      render_callback(buf)
    end
  end)
end

--- Show todo details popup
function M.show_todo_details(todo, config)
  local todo_details = {}
  
  -- Header
  table.insert(todo_details, string.format("Todo: %s", todo.text))
  table.insert(todo_details, string.rep("=", #todo_details[1]))
  table.insert(todo_details, "")
  
  -- Status
  local status = todo.completed and "✅ Completed" or "⭕ Pending"
  table.insert(todo_details, string.format("Status: %s", status))
  if todo.important then
    table.insert(todo_details, "Priority: ★ Important")
  end
  table.insert(todo_details, "")
  
  -- Timestamps
  if todo.created_at then
    local created_date = os.date("%Y-%m-%d %H:%M:%S", todo.created_at / 1000)
    table.insert(todo_details, string.format("Created: %s", created_date))
  end
  
  if todo.updated_at then
    local updated_date = os.date("%Y-%m-%d %H:%M:%S", todo.updated_at / 1000)
    table.insert(todo_details, string.format("Updated: %s", updated_date))
  end
  
  table.insert(todo_details, "")
  
  -- Actions
  table.insert(todo_details, "Actions:")
  if not todo.completed then
    table.insert(todo_details, "  d - Mark as done")
    local important_label = todo.important and "Remove important" or "Mark as important"
    table.insert(todo_details, "  ! - " .. important_label)
  end
  table.insert(todo_details, "  e - Edit")
  table.insert(todo_details, "  D - Delete")
  table.insert(todo_details, "  q - Close")
  
  -- Create popup
  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, todo_details)
  
  -- Calculate popup size
  local width = math.max(50, vim.fn.max(vim.tbl_map(vim.fn.strlen, todo_details)) + 4)
  local height = #todo_details + 2
  
  -- Center the popup
  local ui = vim.api.nvim_list_uis()[1]
  local popup_win = vim.api.nvim_open_win(popup_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = (ui.height - height) / 2,
    col = (ui.width - width) / 2,
    style = 'minimal',
    border = 'rounded',
    title = ' Todo Details ',
    title_pos = 'center'
  })
  
  -- Set popup options
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(popup_buf, 'readonly', true)
  
  -- Close on 'q' or Escape
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'q', '<cmd>close<cr>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<Esc>', '<cmd>close<cr>', { noremap = true, silent = true })
end

return M