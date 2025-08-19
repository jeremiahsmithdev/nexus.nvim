local M = {}

function M.create_gboard_buffer(is_manual_open)
  -- Create listed buffer for manual opens, unlisted for auto opens
  local buf = vim.api.nvim_create_buf(is_manual_open, not is_manual_open)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'gboard')
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  
  -- Make persistent if manually opened, otherwise wipe on hide
  if is_manual_open then
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
    vim.api.nvim_buf_set_option(buf, 'buflisted', true)
  else
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(buf, 'buflisted', false)
  end
  
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

function M.open_buffer(buf, is_manual_open)
  -- Check if GBoard buffer already exists and is persistent
  if is_manual_open then
    -- Look for existing GBoard buffer
    for _, existing_buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(existing_buf) and vim.api.nvim_buf_get_name(existing_buf):match('GBoard$') then
        -- Switch to existing GBoard buffer
        vim.api.nvim_win_set_buf(0, existing_buf)
        M.setup_window_options()
        return
      end
    end
  end
  
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
    -- For manual opens, just switch to the buffer in current window
    vim.api.nvim_win_set_buf(0, buf)
  end
  
  M.setup_window_options()
end

return M