-- Buffer management for Nexus.nvim dashboard
-- Handles creation, opening, and lifecycle management of Nexus buffers
-- Sets up autocommands for automatic git status refresh and image rendering
local M = {}
local logger = require('nexus.logger')

function M.create_nexus_buffer(is_manual_open)
  -- Create listed buffer for manual opens, unlisted for auto opens
  local buf = vim.api.nvim_create_buf(is_manual_open, not is_manual_open)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'nexus')
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

function M.setup_window_options(buf)
  -- Use vim commands with setlocal to set buffer-local window options
  vim.cmd('setlocal nonumber norelativenumber signcolumn=no cursorline')
end

function M.open_buffer(buf, is_manual_open)
  -- Check if Nexus buffer already exists and is persistent
  if is_manual_open then
    -- Look for existing Nexus buffer
    for _, existing_buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(existing_buf) and vim.api.nvim_buf_get_name(existing_buf):match('Nexus$') then
        -- Switch to existing Nexus buffer
        vim.api.nvim_win_set_buf(0, existing_buf)
        M.setup_window_options(existing_buf)
        -- Ensure autocommands are set up for this buffer
        M.setup_image_autocommands(existing_buf)
        -- Force render image for this buffer after a small delay to ensure buffer content is ready
        vim.defer_fn(function()
          local logo = require('nexus.ui.logo')
          local current_config = require('nexus.config').get()
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
  
  M.setup_window_options(buf)
  
  -- Set up image management autocommands for this buffer
  M.setup_image_autocommands(buf)
end

function M.setup_image_autocommands(buf)
  -- Create autocmd group for this buffer
  local group_name = 'NexusImage' .. buf
  vim.api.nvim_create_augroup(group_name, { clear = true })
  
  -- Log buffer creation
  local window = vim.env.TMUX and vim.fn.system("tmux display-message -p '#{window_id}'"):gsub('\n', '') or nil
  local pane = vim.env.TMUX and vim.fn.system("tmux display-message -p '#{pane_id}'"):gsub('\n', '') or nil
  logger.buf_created(buf, window, pane)
  
  -- Only clean up image when buffer is actually being deleted or hidden permanently
  -- DON'T clean up on BufLeave as that triggers when navigating between tmux panes
  vim.api.nvim_create_autocmd('BufDelete', {
    group = group_name,
    buffer = buf,
    callback = function()
      local logo = require('nexus.ui.logo')
      if logo.has_image_for_buffer(buf) then
        logo.cleanup_image()
      end
    end
  })
  
  -- Re-render image and refresh git status when entering the buffer
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group_name,
    buffer = buf,
    callback = function()
      logger.buf_enter(buf)
      -- Only handle image rendering without delay for better performance
      local logo = require('nexus.ui.logo')
      local current_config = require('nexus.config').get()
      
      if current_config.logo_selection == "image" then
        local should_show = logo.should_show_image_in_current_pane()
        local has_image = logo.has_image_for_buffer(buf)
        
        if should_show then
          if not has_image then
            logo.render_image_logo(buf, current_config, 0, 0)
          else
            logo.refresh_image()
          end
        end
      end
      
      -- Skip automatic git refresh on BufEnter to improve performance
      -- Users can manually refresh with 'r' if needed
    end
  })
  
  -- Handle tmux window focus changes
  vim.api.nvim_create_autocmd('FocusGained', {
    group = group_name,
    buffer = buf,
    callback = function()
      logger.info("BUFFER", "FocusGained for buffer " .. buf .. ", checking if image needs re-render")
      vim.defer_fn(function()
        local logo = require('nexus.ui.logo')
        local current_config = require('nexus.config').get()
        
        if current_config.use_image_logo then
          local should_show = logo.should_show_image_in_current_pane()
          if should_show then
            logger.info("IMAGE", "Re-rendering image after focus gained")
            logo.render_image_logo(buf, current_config, 0, 0)
          end
        end
      end, 100) -- Longer delay for focus events
    end
  })
  
  -- Simple cleanup on focus lost
  vim.api.nvim_create_autocmd('FocusLost', {
    group = group_name,
    buffer = buf,
    callback = function()
      logger.info("BUFFER", "FocusLost for buffer " .. buf)
      local logo = require('nexus.ui.logo')
      if logo.has_image_for_buffer(buf) then
        logo.cleanup_image()
      end
    end
  })
  
  -- Add git-specific autocommands for automatic refresh
  local git_utils = require('nexus.git.utils')
  if git_utils.is_git_repo() then
    -- Refresh when files are written (git status might change)
    vim.api.nvim_create_autocmd('BufWritePost', {
      group = group_name,
      pattern = '*',
      callback = function()
        -- Only refresh if the Nexus buffer is currently visible
        local nexus_buf = nil
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local win_buf = vim.api.nvim_win_get_buf(win)
          if win_buf == buf then
            nexus_buf = buf
            break
          end
        end
        
        -- Skip auto-refresh on file write for better performance
        -- Users can manually refresh with 'r' if needed
      end
    })
    
    -- Refresh when shell commands complete (for git operations outside nvim)
    vim.api.nvim_create_autocmd('ShellCmdPost', {
      group = group_name,
      pattern = '*',
      callback = function()
        -- Only refresh if the Nexus buffer is currently visible
        local nexus_buf = nil
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local win_buf = vim.api.nvim_win_get_buf(win)
          if win_buf == buf then
            nexus_buf = buf
            break
          end
        end
        
        -- Skip auto-refresh on shell command for better performance
        -- Users can manually refresh with 'r' if needed
      end
    })
    
    -- Refresh when focus is gained (might have git changes from outside)
    vim.api.nvim_create_autocmd('FocusGained', {
      group = group_name,
      pattern = '*',
      callback = function()
        -- Only refresh if the Nexus buffer is currently visible
        local nexus_buf = nil
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          local win_buf = vim.api.nvim_win_get_buf(win)
          if win_buf == buf then
            nexus_buf = buf
            break
          end
        end
        
        -- Skip auto-refresh on focus for better performance
        -- Users can manually refresh with 'r' if needed
      end
    })
  end
  
  -- Handle all resize events using proper Neovim WinResized event
  vim.api.nvim_create_autocmd({'VimResized', 'WinResized'}, {
    group = group_name,
    callback = function()
      logger.debug("RESIZE", "Resize event triggered", {
        event_type = vim.v.event and vim.v.event.event or "unknown",
        windows = vim.v.event and vim.v.event.windows or {}
      })
      -- Use v:event.windows to check if any window with our buffer was resized
      M.handle_window_resize(buf)
    end
  })
  
  -- Handle splits - re-render ALL Nexus windows immediately
  vim.api.nvim_create_autocmd({'WinNew', 'WinEnter', 'BufWinEnter'}, {
    group = group_name,
    callback = function()
      -- Re-render all windows containing the Nexus buffer
      local config = require('nexus.config').get()
      local render = require('nexus.render')
      local current_win = vim.api.nvim_get_current_win()
      
      for _, win_id in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win_id) and vim.api.nvim_win_get_buf(win_id) == buf then
          logger.debug("RESIZE", "Split handling: re-rendering Nexus window", {
            buf = buf,
            win_id = win_id,
            win_width = vim.api.nvim_win_get_width(win_id),
            win_height = vim.api.nvim_win_get_height(win_id)
          })
          
          -- Switch to this window and re-render
          vim.api.nvim_set_current_win(win_id)
          render.render_git_status(buf, config)
          
          logger.debug("RESIZE", "Split re-render completed for window", {
            win_id = win_id,
            final_width = vim.fn.winwidth(0),
            final_height = vim.fn.winheight(0)
          })
        end
      end
      
      -- Restore original window
      if vim.api.nvim_win_is_valid(current_win) then
        vim.api.nvim_set_current_win(current_win)
      end
    end
  })
  
  -- Clean up when buffer is deleted
  vim.api.nvim_create_autocmd('BufDelete', {
    group = group_name,
    buffer = buf,
    callback = function()
      local logo = require('nexus.ui.logo')
      logo.cleanup_image()
      
      -- Clean up resize timer if it exists
      if M._resize_timer then
        M._resize_timer:stop()
        M._resize_timer:close()
        M._resize_timer = nil
      end
      
      
      -- Clean up the autocmd group
      pcall(vim.api.nvim_del_augroup_by_name, group_name)
    end
  })
end

--- Handle window resize events using proper WinResized event with v:event.windows
---@param buf number Buffer number of the Nexus buffer
function M.handle_window_resize(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    logger.debug("RESIZE", "Buffer not valid", { buf = buf })
    return
  end
  
  -- Get list of windows that were resized from v:event.windows
  local changed_windows = vim.v.event and vim.v.event.windows or {}
  logger.debug("RESIZE", "Checking resize", {
    buf = buf,
    changed_windows = changed_windows,
    all_windows = vim.api.nvim_list_wins()
  })
  
  -- Check if any of the changed windows contain our Nexus buffer
  local needs_resize = false
  for _, win_id in ipairs(changed_windows) do
    local win_buf = vim.api.nvim_win_is_valid(win_id) and vim.api.nvim_win_get_buf(win_id) or -1
    logger.debug("RESIZE", "Checking changed window", { win_id = win_id, win_buf = win_buf, target_buf = buf })
    if vim.api.nvim_win_is_valid(win_id) and win_buf == buf then
      needs_resize = true
      logger.debug("RESIZE", "Found changed window with Nexus buffer", { win_id = win_id })
      break
    end
  end
  
  -- If no specific windows provided (VimResized), check all windows with our buffer
  if #changed_windows == 0 then
    logger.debug("RESIZE", "No specific windows, checking all windows")
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win_id) and vim.api.nvim_win_get_buf(win_id) == buf then
        needs_resize = true
        logger.debug("RESIZE", "Found window with Nexus buffer", { win_id = win_id })
        break
      end
    end
  end
  
  if not needs_resize then
    logger.debug("RESIZE", "No resize needed")
    return
  end
  
  logger.debug("RESIZE", "Starting resize process")
  
  -- Debounce resize events
  if M._resize_timer then
    M._resize_timer:stop()
    M._resize_timer:close()
  end
  
  M._resize_timer = vim.defer_fn(function()
    M._resize_timer = nil
    
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    
    -- Re-render all windows showing the Nexus buffer that were affected
    local config = require('nexus.config').get()
    local render = require('nexus.render')
    
    for _, win_id in ipairs(changed_windows) do
      if vim.api.nvim_win_is_valid(win_id) and vim.api.nvim_win_get_buf(win_id) == buf then
        -- Store current window and cursor position
        local original_win = vim.api.nvim_get_current_win()
        local cursor_pos = vim.api.nvim_win_get_cursor(win_id)
        
        -- Switch to the resized window temporarily
        vim.api.nvim_set_current_win(win_id)
        
        -- Re-render with new dimensions
        render.render_git_status(buf, config)
        
        -- Restore cursor position
        local line_count = vim.api.nvim_buf_line_count(buf)
        if cursor_pos[1] <= line_count then
          vim.api.nvim_win_set_cursor(win_id, cursor_pos)
        end
        
        -- Restore original window
        if vim.api.nvim_win_is_valid(original_win) then
          vim.api.nvim_set_current_win(original_win)
        end
      end
    end
    
    -- If no specific windows were provided, re-render current if it's showing Nexus
    if #changed_windows == 0 then
      local current_win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_get_buf(current_win) == buf then
        local cursor_pos = vim.api.nvim_win_get_cursor(current_win)
        render.render_git_status(buf, config)
        local line_count = vim.api.nvim_buf_line_count(buf)
        if cursor_pos[1] <= line_count then
          vim.api.nvim_win_set_cursor(current_win, cursor_pos)
        end
      end
    end
    
  end, 50) -- 50ms debounce
end

return M
