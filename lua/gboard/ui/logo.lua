local M = {}

-- Store current image reference for cleanup
M._current_image = nil
M._current_buffer = nil
M._current_tmux_pane = nil

function M.get_neovim_logo(config)
  if config and config.use_image_logo then
    return M.get_image_logo(config)
  else
    return M.get_ascii_logo()
  end
end

function M.get_ascii_logo()
  return {
    [[                                  __]],
    [[     ___     ___    ___   __  __ /\_\    ___ ___]],
    [[    / _ `\  / __`\ / __`\/\ \/\ \\/\ \  / __` __`\]],
    [[   /\ \/\ \/\  __//\ \_\ \ \ \_/ |\ \ \/\ \/\ \/\ \]],
    [[   \ \_\ \_\ \____\ \____/\ \___/  \ \_\ \_\ \_\ \_\]],
    [[    \/_/\/_/\/____/\/___/  \/__/    \/_/\/_/\/_/\/_/]],
    ""
  }
end

function M.get_image_logo(config)
  -- Check if image.nvim is available
  local has_image, image = pcall(require, 'image')
  if not has_image then
    -- Fallback to ASCII if image.nvim not available
    vim.notify("GBoard: image.nvim not found, falling back to ASCII logo", vim.log.levels.WARN)
    return M.get_ascii_logo()
  end
  
  -- Determine which image path to use
  local image_path = config.image_logo_path
  if not image_path then
    -- Default to plugin's included neovim.png
    local current_file = debug.getinfo(1).source:sub(2)  -- Remove '@' prefix
    local plugin_root = vim.fn.fnamemodify(current_file, ':h:h:h:h')  -- Go up 4 levels from lua/gboard/ui/logo.lua
    image_path = plugin_root .. '/assets/neovim.png'
  end
  
  -- Check if image file exists
  if vim.fn.filereadable(image_path) ~= 1 then
    vim.notify("GBoard: Image file not found at " .. image_path .. ", falling back to ASCII logo", vim.log.levels.WARN)
    return M.get_ascii_logo()
  end
  
  -- Return placeholder lines for image - the actual image will be rendered separately
  -- We return empty lines to reserve space for the image
  local height = config.image_logo_height or 6
  local placeholder = {}
  for i = 1, height + 1 do  -- +1 for spacing like ASCII logo
    table.insert(placeholder, "")
  end
  return placeholder
end

-- Get detailed tmux pane coordinates and geometry
function M._get_tmux_pane_info()
  if not vim.env.TMUX then
    return nil
  end
  
  -- Get comprehensive pane information in one call
  local pane_info = vim.fn.system("tmux display-message -p '#{pane_id},#{pane_left},#{pane_top},#{pane_width},#{pane_height},#{pane_active}'"):gsub('\n', '')
  local parts = vim.split(pane_info, ',')
  
  if #parts ~= 6 then
    return nil
  end
  
  return {
    id = parts[1],
    left = tonumber(parts[2]),
    top = tonumber(parts[3]), 
    width = tonumber(parts[4]),
    height = tonumber(parts[5]),
    active = parts[6] == '1'
  }
end

-- Check if current pane is the original pane where image should be shown
function M.should_show_image_in_current_pane()
  if not vim.env.TMUX or not M._current_tmux_pane then
    return true -- Not in tmux, always show
  end
  
  local current_pane = M._get_tmux_pane_info()
  if not current_pane then
    return false
  end
  
  -- Only show if we're in the exact same pane ID
  return current_pane.id == M._current_tmux_pane
end

-- Function to render the actual image using image.nvim with proper tmux isolation
function M.render_image_logo(buf, config, start_line, x_offset)
  if not config.use_image_logo then
    return false
  end
  
  local has_image, image = pcall(require, 'image')
  if not has_image then
    vim.notify("GBoard: image.nvim not available, falling back to ASCII logo", vim.log.levels.WARN)
    return false
  end
  
  -- Get current tmux pane info for coordinate-based positioning
  local pane_info = M._get_tmux_pane_info()
  local current_tmux_pane = pane_info and pane_info.id or nil
  
  -- Clean up any existing image from different pane
  if M._current_image and M._current_tmux_pane and M._current_tmux_pane ~= current_tmux_pane then
    M.cleanup_image()
  end
  
  -- Determine which image path to use
  local image_path = config.image_logo_path
  if not image_path then
    local current_file = debug.getinfo(1).source:sub(2)
    local plugin_root = vim.fn.fnamemodify(current_file, ':h:h:h:h')
    image_path = plugin_root .. '/assets/neovim.png'
  end
  
  -- Check if image file exists
  if vim.fn.filereadable(image_path) ~= 1 then
    vim.notify("GBoard: Image file not found at " .. image_path .. ", falling back to ASCII logo", vim.log.levels.WARN)
    return false
  end
  
  -- Check if buffer has enough lines for image positioning
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count < 3 then
    return false
  end
  
  -- Calculate positioning with tmux pane awareness
  local width = vim.fn.winwidth(0)
  if pane_info then
    width = pane_info.width
  end
  
  local img_width = config.image_logo_width or 30
  local img_height = config.image_logo_height or 6
  local center_x = math.max(1, math.floor((width - img_width) / 2))
  local center_y = 2
  
  -- CRITICAL: Only render if we're in the correct pane
  if not M.should_show_image_in_current_pane() then
    return false
  end
  
  local win = vim.api.nvim_get_current_win()
  local img = image.from_file(image_path, {
    buffer = buf,
    window = win,
    x = center_x,
    y = center_y,
    width = img_width,
    height = img_height
  })
  
  if img then
    M.cleanup_image()
    
    M._current_image = img
    M._current_buffer = buf
    M._current_tmux_pane = current_tmux_pane
    
    img:render()
    
    -- Start window-level monitoring (cleanup on window switch, but not pane switch)
    if vim.env.TMUX then
      M._start_window_monitoring()
    end
    
    return true
  end
  
  return false
end

-- Clean up the current image if it exists
function M.cleanup_image()
  if M._current_image then
    -- Clear/hide the image
    pcall(function()
      M._current_image:clear()
    end)
    M._current_image = nil
    M._current_buffer = nil
    M._current_tmux_pane = nil
  end
  
  -- Stop isolation monitoring timer
  if M._isolation_timer then
    M._isolation_timer:stop()
    M._isolation_timer:close()
    M._isolation_timer = nil
  end
end

-- Re-render the image for the current buffer if it exists and we're in the right tmux pane
function M.refresh_image()
  if M._current_image and M._current_buffer then
    -- Validate we're in the correct tmux pane before re-rendering
    if vim.env.TMUX and M._current_tmux_pane then
      local current_pane = vim.fn.system("tmux display-message -p '#{pane_id}'"):gsub('\n', '')
      if current_pane ~= M._current_tmux_pane then
        -- We're in a different pane, don't re-render here
        return
      end
    end
    
    pcall(function()
      -- Clear and re-render to handle position changes
      M._current_image:clear()
      M._current_image:render()
    end)
  end
end

-- Check if we have an active image for a specific buffer and tmux pane
function M.has_image_for_buffer(buf)
  if M._current_buffer ~= buf or M._current_image == nil then
    return false
  end
  
  -- If we're in tmux, also validate we're in the correct pane
  if vim.env.TMUX and M._current_tmux_pane then
    local current_pane = vim.fn.system("tmux display-message -p '#{pane_id}'"):gsub('\n', '')
    return current_pane == M._current_tmux_pane
  end
  
  return true
end

-- Global timer for aggressive pane isolation
M._isolation_timer = nil

-- Window-level monitoring - cleanup when switching tmux windows (not panes)
function M._start_window_monitoring()
  -- Stop any existing timer first
  if M._isolation_timer then
    M._isolation_timer:stop()
    M._isolation_timer:close()
    M._isolation_timer = nil
  end
  
  if not vim.env.TMUX or not M._current_tmux_pane then
    return
  end
  
  -- Get the initial window where the image was created
  local initial_window = vim.fn.system("tmux display-message -p '#{window_id}'"):gsub('\n', '')
  
  -- Monitor at 400ms intervals - less frequent since we only care about window switches
  M._isolation_timer = vim.uv.new_timer()
  
  M._isolation_timer:start(400, 400, function()
    -- Use pcall to prevent any errors from affecting rendering
    pcall(function()
      -- Stop monitoring if we no longer have an image OR the buffer is no longer valid
      if not M._current_image or 
         not M._current_buffer or 
         not vim.api.nvim_buf_is_valid(M._current_buffer) then
        M.cleanup_image()
        if M._isolation_timer then
          M._isolation_timer:stop()
          M._isolation_timer:close() 
          M._isolation_timer = nil
        end
        return
      end
      
      -- Stop monitoring if no GBoard buffers are currently visible
      local has_gboard_buffer = false
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) and 
           vim.api.nvim_buf_get_option(buf, 'filetype') == 'gboard' then
          has_gboard_buffer = true
          break
        end
      end
      
      if not has_gboard_buffer then
        M.cleanup_image()
        if M._isolation_timer then
          M._isolation_timer:stop()
          M._isolation_timer:close() 
          M._isolation_timer = nil
        end
        return
      end
      
      local current_window = vim.fn.system("tmux display-message -p '#{window_id}'"):gsub('\n', '')
      
      -- Only clean up if we've switched to a different tmux window
      if current_window ~= initial_window then
        M.cleanup_image()
        if M._isolation_timer then
          M._isolation_timer:stop()
          M._isolation_timer:close()
          M._isolation_timer = nil
        end
      end
    end)
  end)
end

return M