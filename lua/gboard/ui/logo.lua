local M = {}

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

-- Function to render the actual image using image.nvim
function M.render_image_logo(buf, config, start_line, x_offset)
  if not config.use_image_logo then
    return false
  end
  
  local has_image, image = pcall(require, 'image')
  if not has_image then
    vim.notify("GBoard: image.nvim not available, falling back to ASCII logo", vim.log.levels.WARN)
    return false
  end
  
  -- Determine which image path to use
  local image_path = config.image_logo_path
  if not image_path then
    -- Default to plugin's included neovim.png - get the plugin root directory
    local current_file = debug.getinfo(1).source:sub(2)  -- Remove '@' prefix
    local plugin_root = vim.fn.fnamemodify(current_file, ':h:h:h:h')  -- Go up 4 levels from lua/gboard/ui/logo.lua to get to plugin root
    image_path = plugin_root .. '/assets/neovim.png'
  end
  
  -- Debug path resolution (uncomment for troubleshooting)
  -- print("DEBUG PATH: image_path=" .. image_path .. ", exists=" .. tostring(vim.fn.filereadable(image_path) == 1))
  
  -- Check if image file exists
  if vim.fn.filereadable(image_path) ~= 1 then
    vim.notify("GBoard: Image file not found at " .. image_path .. ", falling back to ASCII logo", vim.log.levels.WARN)
    return false
  end
  
  -- Get the actual display width (same logic as render.lua for consistency)
  local width = vim.fn.winwidth(0) -- default to vim width
  
  if vim.env.TMUX then
    local pane_width = vim.fn.system("tmux display-message -p '#{pane_width}'"):gsub('\n', '')
    local tmux_width = tonumber(pane_width)
    if tmux_width then
      width = tmux_width
    end
  end
  
  local win = vim.api.nvim_get_current_win()
  
  -- Calculate center position based on actual display width (same as ASCII logo)
  local img_width = config.image_logo_width or 30
  local img_height = config.image_logo_height or 6
  local center_x = math.max(1, math.floor((width - img_width) / 2))
  local center_y = 2  -- Start a couple lines down from the top
  
  -- Debug: print actual values being used (uncomment for troubleshooting)
  -- print("DEBUG IMAGE: width=" .. width .. ", center_x=" .. center_x .. ", tmux=" .. tostring(vim.env.TMUX ~= nil))
  -- print("DEBUG IMAGE: using image_path=" .. image_path)
  
  local img = image.from_file(image_path, {
    buffer = buf,
    window = win,  -- Bind to current window
    x = center_x,  -- Use calculated center position
    y = center_y,  -- Position at top like ASCII logo
    width = img_width,
    height = img_height
  })
  
  if img then
    img:render()
    return true
  end
  
  return false
end

return M