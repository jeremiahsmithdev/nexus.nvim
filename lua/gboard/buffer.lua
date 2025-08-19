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
  
  -- Only clean up image when buffer is actually being deleted or hidden permanently
  -- DON'T clean up on BufLeave as that triggers when navigating between tmux panes
  vim.api.nvim_create_autocmd('BufDelete', {
    group = group_name,
    buffer = buf,
    callback = function()
      local logo = require('gboard.ui.logo')
      if logo.has_image_for_buffer(buf) then
        logo.cleanup_image()
      end
    end
  })
  
  -- Re-render image when entering the buffer, but only if we're in the correct pane
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group_name,
    buffer = buf,
    callback = function()
      -- Small delay to ensure buffer content is ready
      vim.defer_fn(function()
        local logo = require('gboard.ui.logo')
        local current_config = require('gboard.config').get()
        
        -- Only render if image logo is enabled and we should show in this pane
        if current_config.use_image_logo and logo.should_show_image_in_current_pane() then
          logo.render_image_logo(buf, current_config, 0, 0)
        end
      end, 50)
    end
  })
  
  -- Focus handling is now managed by the coordinate-based monitoring system
  -- Removed FocusLost/FocusGained autocommands as they interfere with tmux pane navigation
  
  -- Window-level monitoring for re-rendering after tmux window switches (not pane switches)
  if vim.env.TMUX then
    local timer = vim.uv.new_timer()
    local initial_window = vim.fn.system("tmux display-message -p '#{window_id}'"):gsub('\n', '')
    local initial_pane = vim.fn.system("tmux display-message -p '#{pane_id}'"):gsub('\n', '')
    
    -- Check every 300ms for window changes only
    timer:start(300, 300, function()
      -- Use pcall to prevent any errors from affecting rendering
      pcall(function()
        -- Stop timer if the buffer is no longer valid
        if not vim.api.nvim_buf_is_valid(buf) then
          if timer then
            timer:stop()
            timer:close()
          end
          return
        end
        
        -- Stop timer if no GBoard buffers are visible anywhere
        local has_gboard_buffer = false
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local win_buf = vim.api.nvim_win_get_buf(win)
          if vim.api.nvim_buf_is_valid(win_buf) and 
             vim.api.nvim_buf_get_option(win_buf, 'filetype') == 'gboard' then
            has_gboard_buffer = true
            break
          end
        end
        
        if not has_gboard_buffer then
          if timer then
            timer:stop()
            timer:close()
          end
          return
        end
        
        local logo = require('gboard.ui.logo')
        local current_window = vim.fn.system("tmux display-message -p '#{window_id}'"):gsub('\n', '')
        local current_pane = vim.fn.system("tmux display-message -p '#{pane_id}'"):gsub('\n', '')
        local current_buf = vim.api.nvim_get_current_buf()
        
        -- Only re-render if:
        -- 1. We're back in the original window AND original pane
        -- 2. We're viewing the GBoard buffer
        -- 3. We don't have an active image (it was cleaned up by window switch)
        -- 4. The buffer is valid and has content
        if current_window == initial_window and 
           current_pane == initial_pane and
           current_buf == buf and
           vim.api.nvim_buf_is_valid(buf) and
           vim.api.nvim_buf_line_count(buf) > 2 and
           not logo.has_image_for_buffer(buf) then
          
          local current_config = require('gboard.config').get()
          if current_config.use_image_logo then
            -- Small delay to ensure buffer is ready
            vim.defer_fn(function()
              pcall(function()
                logo.render_image_logo(buf, current_config, 0, 0)
              end)
            end, 100)
          end
        end
      end)
    end)
    
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