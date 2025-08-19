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
        -- Ensure autocommands are set up for this buffer
        M.setup_image_autocommands(existing_buf)
        -- Force render image for this buffer after a small delay to ensure buffer content is ready
        vim.defer_fn(function()
          local logo = require('gboard.ui.logo')
          local current_config = require('gboard.config').get()
          if current_config.use_image_logo then
            logo.render_image_logo(existing_buf, current_config, 0, 0)
          end
        end, 50)
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
  
  -- Set up image management autocommands for this buffer
  M.setup_image_autocommands(buf)
end

function M.setup_image_autocommands(buf)
  -- Create autocmd group for this buffer
  local group_name = 'GBoardImage' .. buf
  vim.api.nvim_create_augroup(group_name, { clear = true })
  
  -- Clean up image when leaving the buffer
  vim.api.nvim_create_autocmd({ 'BufLeave', 'BufHidden' }, {
    group = group_name,
    buffer = buf,
    callback = function()
      local logo = require('gboard.ui.logo')
      -- Only cleanup if this is the buffer with the image
      if logo.has_image_for_buffer(buf) then
        logo.cleanup_image()
      end
    end
  })
  
  -- Re-render image when entering the buffer (force render every time)
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group_name,
    buffer = buf,
    callback = function()
      -- Small delay to ensure buffer content is ready
      vim.defer_fn(function()
        local logo = require('gboard.ui.logo')
        local current_config = require('gboard.config').get()
        
        -- Always try to render if image logo is enabled
        if current_config.use_image_logo then
          -- Force render regardless of current state
          logo.render_image_logo(buf, current_config, 0, 0)
        end
      end, 50)
    end
  })
  
  -- Handle focus changes (tmux pane switching)
  vim.api.nvim_create_autocmd({ 'FocusLost', 'VimSuspend' }, {
    group = group_name,
    buffer = buf,
    callback = function()
      local logo = require('gboard.ui.logo')
      if logo.has_image_for_buffer(buf) then
        logo.cleanup_image()
      end
    end
  })
  
  vim.api.nvim_create_autocmd({ 'FocusGained', 'VimResume' }, {
    group = group_name,
    buffer = buf,
    callback = function()
      -- Small delay to ensure tmux has finished switching
      vim.defer_fn(function()
        local logo = require('gboard.ui.logo')
        if logo.has_image_for_buffer(buf) then
          logo.refresh_image()
        end
      end, 100)
    end
  })
  
  -- Additional tmux-specific handling with timer-based cleanup
  if vim.env.TMUX then
    -- Set up a timer to periodically check if we're still in the right tmux context
    local timer = vim.uv.new_timer()
    local last_tmux_pane = nil
    
    -- Function to get current tmux pane info
    local function get_tmux_context()
      local pane_id = vim.fn.system("tmux display-message -p '#{pane_id}'"):gsub('\n', '')
      local window_id = vim.fn.system("tmux display-message -p '#{window_id}'"):gsub('\n', '')
      return pane_id, window_id
    end
    
    -- Store initial context
    local initial_pane, initial_window = get_tmux_context()
    last_tmux_pane = initial_pane
    
    -- Check every 500ms for tmux context changes
    timer:start(500, 500, vim.schedule_wrap(function()
      local logo = require('gboard.ui.logo')
      local current_pane, current_window = get_tmux_context()
      
      -- If we have an image and context changed, cleanup
      if logo.has_image_for_buffer(buf) and current_pane ~= last_tmux_pane then
        logo.cleanup_image()
        last_tmux_pane = current_pane
      end
      
      -- If we don't have an image but we're viewing this GBoard buffer, re-render
      if not logo.has_image_for_buffer(buf) and 
         vim.api.nvim_get_current_buf() == buf then
        
        -- Check if we should have an image (buffer is GBoard with image enabled)
        local current_config = require('gboard.config').get()
        if current_config.use_image_logo then
          -- Re-render the image
          logo.render_image_logo(buf, current_config, 0, 0)
        end
        last_tmux_pane = current_pane
      end
    end))
    
    -- Clean up timer when buffer is deleted
    vim.api.nvim_create_autocmd('BufDelete', {
      group = group_name,
      buffer = buf,
      once = true,
      callback = function()
        if timer then
          timer:stop()
          timer:close()
        end
      end
    })
  end
  
  -- Clean up when buffer is deleted
  vim.api.nvim_create_autocmd('BufDelete', {
    group = group_name,
    buffer = buf,
    callback = function()
      local logo = require('gboard.ui.logo')
      logo.cleanup_image()
      -- Clean up the autocmd group
      pcall(vim.api.nvim_del_augroup_by_name, group_name)
    end
  })
end

return M