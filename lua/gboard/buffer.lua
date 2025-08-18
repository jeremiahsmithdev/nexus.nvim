local M = {}

function M.create_gboard_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'gboard')
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  return buf
end

function M.setup_window_options()
  vim.api.nvim_win_set_option(0, 'number', false)
  vim.api.nvim_win_set_option(0, 'relativenumber', false)
  vim.api.nvim_win_set_option(0, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(0, 'wrap', false)
  vim.api.nvim_win_set_option(0, 'cursorline', true)
end

function M.open_buffer(buf)
  -- If this is startup (only empty buffer exists), replace it
  local current_buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(current_buf)
  local buf_lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
  local is_empty_startup = buf_name == '' and #buf_lines == 1 and buf_lines[1] == ''
  
  if is_empty_startup then
    -- Replace the empty startup buffer
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_delete(current_buf, { force = true })
  else
    -- Open in new tab
    vim.cmd('tabnew')
    vim.api.nvim_win_set_buf(0, buf)
  end
  
  M.setup_window_options()
end

return M