-- Buffer management for Nexus.nvim dashboard
-- Handles creation, opening, and lifecycle management of Nexus buffers
-- Sets up autocommands for automatic git status refresh and image rendering
local M = {}
local logger = require('nexus.logger')

-- Debounced resize state management
local resize_state = {
  timers = {},  -- Per-buffer timers
  debounce_ms = 50,  -- Debounce delay
  batch_queue = {}   -- Batch operations queue
}

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
  
  -- Consolidated buffer lifecycle management
  vim.api.nvim_create_autocmd('BufDelete', {
    group = group_name,
    buffer = buf,
    callback = function()
      local logo = require('nexus.ui.logo')
      if logo.has_image_for_buffer(buf) then
        logo.cleanup_image()
      end
      
      -- Clean up all resize state for this buffer
      M.cleanup_resize_state(buf)
      
      -- Clean up the autocmd group
      pcall(vim.api.nvim_del_augroup_by_name, group_name)
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
  
  
  -- Consolidated focus management for images
  vim.api.nvim_create_autocmd({'FocusGained', 'FocusLost'}, {
    group = group_name,
    buffer = buf,
    callback = function(event)
      local logo = require('nexus.ui.logo')
      local current_config = require('nexus.config').get()
      
      if event.event == 'FocusGained' and current_config.logo_selection == "image" then
        vim.defer_fn(function()
          if logo.should_show_image_in_current_pane() then
            logo.render_image_logo(buf, current_config, 0, 0)
          end
        end, 100)
      elseif event.event == 'FocusLost' and logo.has_image_for_buffer(buf) then
        logo.cleanup_image()
      end
    end
  })
  
  -- Git-specific autocommands (currently disabled for performance)
  -- Users can manually refresh with 'r' key if needed
  -- Uncomment and modify if auto-refresh is needed:
  -- local git_utils = require('nexus.git.utils')
  -- if git_utils.is_git_repo() then
  --   vim.api.nvim_create_autocmd({'BufWritePost', 'ShellCmdPost'}, {
  --     group = group_name,
  --     pattern = '*',
  --     callback = function()
  --       -- Auto-refresh logic here
  --     end
  --   })
  -- end
  
  -- Handle all resize events using debounced handler
  vim.api.nvim_create_autocmd({'VimResized', 'WinResized'}, {
    group = group_name,
    callback = function()
      M.debounced_resize(buf, vim.v.event and vim.v.event.windows or {})
    end
  })
  
  -- Handle splits using debounced handler
  vim.api.nvim_create_autocmd({'WinNew', 'WinEnter', 'BufWinEnter'}, {
    group = group_name,
    callback = function()
      -- Use immediate resize for splits to handle layout changes
      M.debounced_resize(buf, {}, true)  -- immediate = true
    end
  })
  
  -- Note: Buffer cleanup is handled in the consolidated BufDelete autocmd above
end

--- Debounced resize handler with improved performance and batching
---@param buf number Buffer number of the Nexus buffer
---@param changed_windows table List of changed window IDs
---@param immediate boolean Whether to execute immediately (for splits)
function M.debounced_resize(buf, changed_windows, immediate)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  -- Find windows that need updating
  local windows_to_update = M.find_nexus_windows(buf, changed_windows)
  if #windows_to_update == 0 then
    return
  end
  
  -- Clean up existing timer for this buffer
  M.cleanup_resize_state(buf)
  
  if immediate then
    M.execute_resize(buf, windows_to_update)
  else
    -- Start debounced timer
    resize_state.timers[buf] = vim.defer_fn(function()
      resize_state.timers[buf] = nil
      M.execute_resize(buf, windows_to_update)
    end, resize_state.debounce_ms)
  end
end

--- Find all windows showing the Nexus buffer that need updating
---@param buf number Buffer number
---@param changed_windows table Specific windows that changed (empty for all)
---@return table List of window IDs to update
function M.find_nexus_windows(buf, changed_windows)
  local windows_to_update = {}
  
  if #changed_windows > 0 then
    -- Check only specific changed windows
    for _, win_id in ipairs(changed_windows) do
      if vim.api.nvim_win_is_valid(win_id) and vim.api.nvim_win_get_buf(win_id) == buf then
        table.insert(windows_to_update, win_id)
      end
    end
  else
    -- Check all windows
    for _, win_id in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win_id) and vim.api.nvim_win_get_buf(win_id) == buf then
        table.insert(windows_to_update, win_id)
      end
    end
  end
  
  return windows_to_update
end

--- Execute resize operation with batched buffer operations
---@param buf number Buffer number
---@param windows_to_update table List of window IDs
function M.execute_resize(buf, windows_to_update)
  if not vim.api.nvim_buf_is_valid(buf) or #windows_to_update == 0 then
    return
  end
  
  local config = require('nexus.config').get()
  local render = require('nexus.render')
  local original_win = vim.api.nvim_get_current_win()
  
  -- Batch all window operations
  local cursor_positions = {}
  
  -- Store cursor positions for all windows
  for _, win_id in ipairs(windows_to_update) do
    if vim.api.nvim_win_is_valid(win_id) then
      cursor_positions[win_id] = vim.api.nvim_win_get_cursor(win_id)
    end
  end
  
  -- Re-render for the first window (content will be same for all)
  vim.api.nvim_set_current_win(windows_to_update[1])
  render.render_git_status(buf, config)
  
  -- Restore cursor positions for all windows
  local line_count = vim.api.nvim_buf_line_count(buf)
  for _, win_id in ipairs(windows_to_update) do
    if vim.api.nvim_win_is_valid(win_id) and cursor_positions[win_id] then
      local cursor_pos = cursor_positions[win_id]
      if cursor_pos[1] <= line_count then
        vim.api.nvim_win_set_cursor(win_id, cursor_pos)
      end
    end
  end
  
  -- Restore original window
  if vim.api.nvim_win_is_valid(original_win) then
    vim.api.nvim_set_current_win(original_win)
  end
end

--- Clean up resize state for a specific buffer
---@param buf number Buffer number
function M.cleanup_resize_state(buf)
  if resize_state.timers[buf] then
    resize_state.timers[buf]:stop()
    resize_state.timers[buf]:close()
    resize_state.timers[buf] = nil
  end
  
  -- Clear any batch queue entries for this buffer
  resize_state.batch_queue[buf] = nil
end

--- Clean up all resize state (called on plugin shutdown)
function M.cleanup_all_resize_state()
  for buf, timer in pairs(resize_state.timers) do
    if timer then
      timer:stop()
      timer:close()
    end
  end
  resize_state.timers = {}
  resize_state.batch_queue = {}
end

return M
