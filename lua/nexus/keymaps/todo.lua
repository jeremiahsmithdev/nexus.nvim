---@class TodoKeymaps
local M = {}

local actions = require('nexus.actions')
local todo_state = require('nexus.state.todo')
local todo_component = require('nexus.render.components.todo')
local logger = require('nexus.logger')

-- Incremental todo re-render. Matches the pattern used by beads keymaps:
-- mutate state, then patch just the todos section rather than doing a full
-- buffer rewrite. Keeps cursor stable and prevents fold/layout flicker.
local function rerender_todos(buf)
  require('nexus.render').render_section(buf, 'todos')
end

-- Pull latest todos from disk and repaint the dashboard. Called before every
-- todo operation so the user always acts on the freshest state from any
-- parallel Neovim session.
local function sync_before_action(buf)
  todo_state.refresh()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    rerender_todos(buf)
  end
end

--- Handle Enter key in todo section
function M.handle_enter(current_line, line_num, config)
  todo_state.refresh()
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
  sync_before_action(buf)
  vim.ui.input({
    prompt = 'New todo: ',
    default = ''
  }, function(input)
    if input and #input > 0 then
      actions.execute('todo.create', {
        text = input
      })
      rerender_todos(buf)
    end
  end)
end

--- Handle 'e' key in todo section - edit todo
function M.handle_edit(todo_id, buf, render_callback, config)
  sync_before_action(buf)
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
      rerender_todos(buf)
    end
  end)
end

--- Handle 'd' key in todo section - mark todo as done
function M.handle_done(todo_id, buf, render_callback, config)
  sync_before_action(buf)
  actions.execute('todo.done', {
    id = todo_id
  })
  rerender_todos(buf)
end

--- Handle '!' key in todo section - toggle important
function M.handle_important(todo_id, buf, render_callback, config)
  sync_before_action(buf)
  actions.execute('todo.important', {
    id = todo_id
  })
  rerender_todos(buf)
end

--- Handle 'D' key in todo section - confirm deletion of cursor's todo via fzf
function M.handle_delete(todo_id, buf, render_callback, config)
  sync_before_action(buf)

  local todo = todo_state.get_todo_by_id(todo_id)
  if not todo then
    vim.notify("Todo not found", vim.log.levels.ERROR)
    return
  end

  local function do_delete()
    actions.execute('todo.delete', { id = todo_id })
    rerender_todos(buf)
    vim.notify(string.format('Deleted: %s', todo.text), vim.log.levels.INFO)
  end

  local ok_fzf, fzf = pcall(require, 'fzf-lua')
  if ok_fzf then
    fzf.fzf_exec({ 'Yes', 'No' }, {
      prompt = string.format('Delete "%s"? ', todo.text),
      winopts = {
        width = 0.4,
        height = 0.2,
        row = 0.4,
        col = 0.5,
        border = 'rounded',
        preview = { hidden = 'hidden' },
      },
      actions = {
        ['default'] = function(selected)
          if selected and selected[1] == 'Yes' then do_delete() end
        end,
      },
    })
    return
  end

  -- Fallback: vim.ui.select (uses dressing.nvim / telescope-ui-select if installed)
  vim.ui.select({ 'Yes', 'No' }, {
    prompt = string.format('Delete todo: "%s"?', todo.text),
  }, function(choice)
    if choice == 'Yes' then do_delete() end
  end)
end

--- Handle 'E' key - edit all todos in a popup buffer
function M.handle_edit_all(buf, render_callback, config)
  sync_before_action(buf)
  local todos = todo_state.get_todos()

  -- Build editable lines with checkbox syntax (stored order)
  local lines = {}

  for _, todo in ipairs(todos) do
    local prefix
    if todo.completed then
      prefix = "[x]"
    elseif todo.important then
      prefix = "[!]"
    else
      prefix = "[ ]"
    end
    table.insert(lines, prefix .. " " .. todo.text)
  end

  -- Add blank line at end for easy adding
  if #lines == 0 then
    table.insert(lines, "[ ] ")
  end

  -- Create popup buffer
  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(popup_buf, 'buftype', 'acwrite')
  vim.api.nvim_buf_set_option(popup_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_name(popup_buf, 'nexus://todos-' .. vim.loop.now())

  -- Calculate popup size
  local ui = vim.api.nvim_list_uis()[1]
  local width = math.min(70, ui.width - 10)
  local height = math.min(#lines + 4, ui.height - 6)

  local popup_win = vim.api.nvim_open_win(popup_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((ui.height - height) / 2),
    col = math.floor((ui.width - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Edit Todos (s: save, q: cancel) ',
    title_pos = 'center',
  })

  -- Position cursor at end of first line for immediate editing
  vim.api.nvim_win_set_cursor(popup_win, {1, #lines[1]})

  -- Build lookup of existing todos by text for preserving metadata
  local existing_by_text = {}
  for _, todo in ipairs(todos) do
    existing_by_text[todo.text] = todo
  end

  -- Save function
  local function save_todos()
    local edited_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
    local new_todos = {}
    local used_ids = {}

    for _, line in ipairs(edited_lines) do
      -- Skip empty lines
      if line:match("^%s*$") then goto continue end

      -- Parse checkbox prefix and text
      local prefix, text = line:match("^%[([x!%s])%]%s*(.*)")
      if not prefix then
        -- Line without prefix - treat as active todo with the whole line as text
        text = line:gsub("^%s+", ""):gsub("%s+$", "")
        prefix = " "
      end

      if text and text ~= "" then
        local completed = prefix == "x"
        local important = prefix == "!"

        -- Try to match existing todo by text to preserve id/created_at
        local existing = existing_by_text[text]
        if existing and not used_ids[existing.id] then
          used_ids[existing.id] = true
          existing.completed = completed
          existing.important = important
          existing.updated_at = os.time()
          table.insert(new_todos, existing)
        else
          table.insert(new_todos, {
            id = tostring(os.time() .. math.random(1000, 9999)),
            text = text,
            completed = completed,
            important = important,
            created_at = os.time(),
            updated_at = os.time(),
          })
        end
      end

      ::continue::
    end

    -- Replace all todos in state
    todo_state.replace_all(new_todos)

    -- Close popup
    if vim.api.nvim_win_is_valid(popup_win) then
      vim.api.nvim_win_close(popup_win, true)
    end

    vim.notify(string.format("Saved %d todos", #new_todos), vim.log.levels.INFO)
    rerender_todos(buf)
  end

  local function close_popup()
    if vim.api.nvim_win_is_valid(popup_win) then
      vim.api.nvim_win_close(popup_win, true)
    end
  end

  -- Support :w and :wq via BufWriteCmd
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = popup_buf,
    callback = function()
      save_todos()
    end
  })

  -- Keymaps
  local opts = { noremap = true, silent = true, buffer = popup_buf }
  vim.keymap.set('n', 's', save_todos, opts)
  vim.keymap.set('n', 'q', close_popup, opts)
  vim.keymap.set('n', '<Esc>', close_popup, opts)
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