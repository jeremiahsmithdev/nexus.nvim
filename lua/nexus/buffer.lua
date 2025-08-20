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

function M.setup_window_options()
  vim.api.nvim_win_set_option(0, 'number', false)
  vim.api.nvim_win_set_option(0, 'relativenumber', false)
  vim.api.nvim_win_set_option(0, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(0, 'wrap', false)
  vim.api.nvim_win_set_option(0, 'cursorline', true)
end

function M.open_buffer(buf, is_manual_open)
  -- Check if Nexus buffer already exists and is persistent
  if is_manual_open then
    -- Look for existing Nexus buffer
    for _, existing_buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(existing_buf) and vim.api.nvim_buf_get_name(existing_buf):match('Nexus$') then
        -- Switch to existing Nexus buffer
        vim.api.nvim_win_set_buf(0, existing_buf)
        M.setup_window_options()
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
  
  M.setup_window_options()
  
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
  
  -- Re-render image when entering the buffer (in correct pane)
  vim.api.nvim_create_autocmd('BufEnter', {
    group = group_name,
    buffer = buf,
    callback = function()
      logger.buf_enter(buf)
      vim.defer_fn(function()
        local logo = require('nexus.ui.logo')
        local current_config = require('nexus.config').get()
        local should_show = logo.should_show_image_in_current_pane()
        local has_image = logo.has_image_for_buffer(buf)
        
        logger.image_render_attempt(buf, should_show, has_image, current_config.use_image_logo)
        
        if current_config.use_image_logo and should_show then
          if not has_image then
            logger.debug("IMAGE", "No image for buffer, rendering new image")
            logo.render_image_logo(buf, current_config, 0, 0)
          else
            logger.debug("IMAGE", "Image exists for buffer, refreshing it")
            logo.refresh_image()
          end
        else
          logger.debug("IMAGE", "Not rendering image: use_image_logo=" .. tostring(current_config.use_image_logo) .. ", should_show=" .. tostring(should_show))
        end
      end, 50)
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
  
  -- Clean up when buffer is deleted
  vim.api.nvim_create_autocmd('BufDelete', {
    group = group_name,
    buffer = buf,
    callback = function()
      local logo = require('nexus.ui.logo')
      logo.cleanup_image()
      -- Clean up the autocmd group
      pcall(vim.api.nvim_del_augroup_by_name, group_name)
    end
  })
end

return M