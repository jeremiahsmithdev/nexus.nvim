-- lua/nexus/ui/logo.lua
-- Logo dispatcher and image-rendering logic for the Nexus dashboard.
-- ASCII art data lives in lua/nexus/ui/logos/ and is lazy-loaded per variant.
local M = {}
local logger = require('nexus.logger')

-- Store current image reference for cleanup
M._current_image = nil
M._current_buffer = nil
M._current_tmux_pane = nil

function M.get_neovim_logo(config)
  local logo_selection = config and config.logo_selection or "nexus"

  if logo_selection == "image" then
    return M.get_image_logo(config)
  elseif logo_selection == "nexus" then
    return M.get_nexus_ascii_logo()
  elseif logo_selection == "neovim" then
    return M.get_ascii_logo()
  elseif logo_selection == "project" then
    return M.get_project_logo()
  else
    -- Default to nexus ASCII logo
    return M.get_nexus_ascii_logo()
  end
end

-- Alpha.nvim-style Neovim logo. Art data in logos/neovim.lua.
function M.get_ascii_logo()
  return require('nexus.ui.logos.neovim')
end

function M.get_nexus_ascii_logo()
  local project_name = M._get_project_name()
  -- Base art loaded lazily; only pulled in when this variant is selected.
  local logo_lines = vim.deepcopy(require('nexus.ui.logos.nexus'))
  
  if project_name then
    local padding = math.floor((48 - #project_name) / 2)
    -- Optimized: Use table concatenation for padding
    local centered_project_name = table.concat({string.rep(" ", padding), project_name})
    table.insert(logo_lines, centered_project_name)
    table.insert(logo_lines, "")
  end
  
  return logo_lines
end

-- Function to generate project logo using block-letter alphabet.
-- Alphabet data loaded lazily from logos/alphabet.lua.
function M.get_project_logo()
  local project_name = M._get_project_name()
  if not project_name then
    -- Fallback to nexus logo if no project name detected
    return M.get_nexus_ascii_logo()
  end

  local alphabet = require('nexus.ui.logos.alphabet')

  -- Convert to uppercase and filter out unsupported characters
  local upper_name = string.upper(project_name)
  local filtered_chars = {}
  for char in upper_name:gmatch(".") do
    if alphabet[char] then
      table.insert(filtered_chars, char)
    end
  end
  
  if #filtered_chars == 0 then
    -- No valid characters, fallback to nexus logo
    return M.get_nexus_ascii_logo()
  end
  
  -- Build the logo by combining character patterns
  local logo_lines = {""}
  
  -- Each character has 6 lines, combine them horizontally
  for line_idx = 1, 6 do
    local combined_line = ""
    for i, char in ipairs(filtered_chars) do
      local char_pattern = alphabet[char]
      if char_pattern and char_pattern[line_idx] then
        combined_line = combined_line .. char_pattern[line_idx]
        -- Add space between characters except for the last one
        if i < #filtered_chars then
          combined_line = combined_line .. " "
        end
      end
    end
    table.insert(logo_lines, combined_line)
  end
  
  -- Add closing empty line and subtitle
  table.insert(logo_lines, "")
  table.insert(logo_lines, "[ " .. project_name .. " - Developer Dashboard ]")
  table.insert(logo_lines, "")
  
  return logo_lines
end

-- Helper function to get the current project name
function M._get_project_name()
  -- Try to get project name from git repository
  local git_root = require('nexus.git.root').get()
  if git_root then
    local project_name = vim.fn.fnamemodify(git_root, ":t")
    if project_name and project_name ~= "" then
      -- Get current git branch
      local git_commits = require('nexus.git.commits')
      local current_branch = git_commits.get_current_branch()

      if current_branch and current_branch ~= "" then
        return string.format("%s on  %s", project_name, current_branch)
      else
        return project_name
      end
    end
  end

  -- Fallback to current working directory name
  local cwd = vim.fn.getcwd()
  local cwd_name = vim.fn.fnamemodify(cwd, ":t")
  return cwd_name and cwd_name ~= "" and cwd_name or nil
end

function M.get_image_logo(config)
  -- Check if image.nvim is available
  local has_image, image = pcall(require, 'image')
  logger.debug("IMAGE", "image.nvim detection: has_image=" .. tostring(has_image))
  if not has_image then
    -- Fallback to ASCII if image.nvim not available
    logger.warn("IMAGE", "image.nvim not found, falling back to ASCII logo", {error = tostring(image)})
    return M.get_ascii_logo()
  end
  
  -- Determine which image path to use
  local image_path = config.image_logo_path
  if not image_path then
    -- Default to plugin's included neovim.png
    local current_file = debug.getinfo(1).source:sub(2)  -- Remove '@' prefix
    local plugin_root = vim.fn.fnamemodify(current_file, ':h:h:h:h')  -- Go up 4 levels from lua/nexus/ui/logo.lua
    image_path = plugin_root .. '/assets/neovim.png'
  end
  
  -- Check if image file exists
  if vim.fn.filereadable(image_path) ~= 1 then
    logger.warn("IMAGE", "Image file not found at " .. image_path .. ", falling back to ASCII logo")
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
  if not vim.env.TMUX then
    logger.debug("IMAGE", "Not in tmux, allowing image render")
    return true -- Not in tmux, always show
  end
  
  local current_pane = M._get_tmux_pane_info()
  if not current_pane then
    logger.warn("IMAGE", "Could not get current tmux pane info")
    return false
  end
  
  logger.debug("IMAGE", "Pane check: current=" .. current_pane.id .. ", stored=" .. (M._current_tmux_pane or "nil"))
  
  -- If we don't have a stored pane (after cleanup), allow rendering
  -- The render function will store the current pane
  if not M._current_tmux_pane then
    logger.debug("IMAGE", "No stored pane, allowing render to set it")
    return true
  end
  
  -- Only show if we're in the exact same pane ID
  local should_show = current_pane.id == M._current_tmux_pane
  logger.debug("IMAGE", "Pane match result: " .. tostring(should_show))
  return should_show
end

-- Function to render the actual image using image.nvim with proper tmux isolation
function M.render_image_logo(buf, config, start_line, x_offset)
  local logo_selection = config and config.logo_selection or "nexus"
  
  
  if logo_selection ~= "image" then
    return false
  end
  
  local has_image, image = pcall(require, 'image')
  if not has_image then
    return false
  end
  
  -- Get current tmux pane info for coordinate-based positioning
  local pane_info = M._get_tmux_pane_info()
  local current_tmux_pane = pane_info and pane_info.id or nil
  
  -- Fix: If we don't have a stored pane but we're in tmux, use the current pane
  if not M._current_tmux_pane and current_tmux_pane then
    M._current_tmux_pane = current_tmux_pane
  end
  
  -- Clean up any existing image from different pane
  if M._current_image and M._current_tmux_pane and M._current_tmux_pane ~= current_tmux_pane then
    logger.info("IMAGE", "Cleaning up image due to pane change: " .. (M._current_tmux_pane or "nil") .. " -> " .. (current_tmux_pane or "nil"))
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
    logger.warn("IMAGE", "Image file not found at " .. image_path .. ", falling back to ASCII logo")
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
  local center_y = 2  -- Fixed position at line 2 in buffer
  
  -- Get current window scroll position for debugging
  local win = vim.api.nvim_get_current_win()
  local win_top_line = vim.fn.line('w0', win)  -- First visible line in window
  local cursor_line = vim.fn.line('.', win)    -- Current cursor line
  
  logger.debug("IMAGE", "Positioning: width=" .. width .. ", center_x=" .. center_x .. ", center_y=" .. center_y .. ", win_top=" .. win_top_line .. ", cursor=" .. cursor_line)
  
  -- Only render if we're in the correct pane
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
    logger.info("IMAGE", "Successfully rendered image logo for buffer " .. buf .. " in pane " .. (current_tmux_pane or "none"))
    return true
  end
  
  logger.error("IMAGE", "Failed to create image object for buffer " .. buf)
  return false
end

-- Clean up the current image if it exists
function M.cleanup_image()
  if M._current_image then
    logger.info("IMAGE", "Cleaning up image for buffer " .. (M._current_buffer or "unknown") .. " in pane " .. (M._current_tmux_pane or "unknown"))
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
    -- Validate we're in the correct tmux pane before re-rendering. nvim's own
    -- pane id is fixed for the process lifetime, so reuse the logger's memoized
    -- value instead of spawning another `tmux display-message`.
    if vim.env.TMUX and M._current_tmux_pane then
      local _, current_pane = logger.tmux_context()
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
  logger.debug("IMAGE", "Checking has_image_for_buffer: buf=" .. buf .. ", current_buffer=" .. (M._current_buffer or "nil") .. ", current_image=" .. tostring(M._current_image ~= nil))
  
  if M._current_buffer ~= buf or M._current_image == nil then
    logger.debug("IMAGE", "No image: buffer mismatch or no current image")
    return false
  end
  
  -- If we're in tmux, also validate we're in the correct pane. Reuse the
  -- logger's memoized pane id (nvim's pane is fixed for the process lifetime)
  -- rather than spawning another `tmux display-message`.
  if vim.env.TMUX and M._current_tmux_pane then
    local _, current_pane = logger.tmux_context()
    local has_image = current_pane == M._current_tmux_pane
    logger.debug("IMAGE", "Tmux pane check: current=" .. current_pane .. ", stored=" .. M._current_tmux_pane .. ", has_image=" .. tostring(has_image))
    return has_image
  end
  
  logger.debug("IMAGE", "Has image (not in tmux or no stored pane)")
  return true
end

-- Global timer for aggressive pane isolation
M._isolation_timer = nil

-- No monitoring functions needed - using event-driven approach

return M