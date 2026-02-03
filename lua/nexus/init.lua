local M = {}

-- Performance optimization: Use module registry for cached requires
local registry = require('nexus.registry')
registry.init()

-- Load critical components immediately (using registry for performance)
local config = registry.get('nexus.config')
local logger = registry.get('nexus.logger')
local buffer_mod = registry.get('nexus.buffer')

-- Setup function to allow user configuration
function M.setup(user_config)
  -- Initialize essential components only
  logger.init()
  logger.log_timing_event("SETUP_START")
  config.setup(user_config)
  logger.log_timing_event("CONFIG_SETUP_COMPLETE")

  -- Defer non-critical initialization with longer delay to prevent startup blocking
  vim.defer_fn(function()
    -- Initialize core git state (needed for dashboard)
    local git_state = registry.get('nexus.state.git')
    git_state.init()

    -- Initialize action system (needed for todo functionality)
    local actions = registry.get('nexus.actions')
    actions.init()

    -- Lazy load other components only when needed
    -- These will be initialized on first access by individual modules
  end, 100) -- 100ms delay to ensure startup completes first
end


function M.open(is_manual_open)
  logger.log_timing_event("OPEN_START", { manual = is_manual_open })

  -- Check if Nexus buffer already exists and is loaded
  logger.log_timing_event("BUFFER_EXISTENCE_CHECK_START")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match('Nexus$') then
        -- Found existing loaded Nexus buffer, just switch to it
        logger.info('NEXUS', 'Switching to existing Nexus buffer')
        logger.log_timing_event("EXISTING_BUFFER_FOUND")
        buffer_mod.open_buffer(buf, is_manual_open)
        logger.log_timing_event("SWITCH_TO_EXISTING_BUFFER_COMPLETE")
        logger.end_timing_session()
        return
      end
    end
  end
  logger.log_timing_event("BUFFER_EXISTENCE_CHECK_COMPLETE")

  -- Actions system is initialized in setup(), no need to re-initialize
  -- Just get the actions module from registry
  local actions = registry.get('nexus.actions')

  logger.info('NEXUS', 'Opening new Nexus dashboard, manual=' .. tostring(is_manual_open))

  -- Check if we should treat auto-open as persistent due to keep_open_after_startup
  logger.log_timing_event("CONFIG_RETRIEVAL_START")
  local current_config = config.get()
  local should_be_persistent = is_manual_open or current_config.keep_open_after_startup
  logger.log_timing_event("CONFIG_RETRIEVAL_COMPLETE")

  logger.log_timing_event("BUFFER_CREATION_START")
  local buf = buffer_mod.create_nexus_buffer(should_be_persistent)
  vim.api.nvim_buf_set_name(buf, 'Nexus')
  logger.log_timing_event("BUFFER_CREATION_COMPLETE")

  logger.log_timing_event("BUFFER_OPEN_START")
  buffer_mod.open_buffer(buf, is_manual_open)
  logger.log_timing_event("BUFFER_OPEN_COMPLETE")

  -- Use regular render system without delays
  local render = registry.get('nexus.render')
  local files, section_ranges

  -- Render immediately - enhanced width detection handles tmux correctly
  logger.log_timing_event("RENDER_START")
  files, section_ranges = render.render_git_status(buf, current_config)
  logger.log_timing_event("RENDER_COMPLETE")

  logger.log_timing_event("GIT_STATE_CHECK_START")
  local git_state = registry.get('nexus.state.git')
  local is_git_repo = git_state.is_git_repo()
  logger.log_timing_event("GIT_STATE_CHECK_COMPLETE")

  -- Lazy-load keymaps system (using registry for performance)
  logger.log_timing_event("KEYMAPS_SETUP_START")
  local keymaps = registry.get('nexus.keymaps')
  keymaps.setup_keymaps(buf, files, current_config, is_git_repo, function(buf, cached_files)
    logger.log_timing_event("REFRESH_CALLBACK_START")
    render.render_git_status(buf, current_config, cached_files)
    logger.log_timing_event("REFRESH_CALLBACK_COMPLETE")
  end, section_ranges)
  logger.log_timing_event("KEYMAPS_SETUP_COMPLETE")

  -- Position cursor on first actionable line (dashboard buttons)
  logger.log_timing_event("CURSOR_POSITIONING_START")
  M.position_cursor_on_actionable_line(buf, section_ranges)
  logger.log_timing_event("CURSOR_POSITIONING_COMPLETE")
  logger.log_timing_event("OPEN_COMPLETE")
  logger.end_timing_session()
end

-- Position cursor on first actionable line (dashboard buttons)
function M.position_cursor_on_actionable_line(buf, section_ranges)
  logger.log_timing_event("CURSOR_POSITIONING_INNER_START")
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local logo = registry.get('nexus.ui.logo')
  local current_config = registry.get('nexus.config').get()
  local logo_lines = logo.get_neovim_logo(current_config)
  local logo_end_line = #logo_lines  -- Logo only

  -- Find first actionable line (should be first dashboard button)
  for i = logo_end_line + 1, #lines do
    if lines[i] then
      -- Skip keyboard shortcuts section
      if section_ranges and section_ranges.keyboard_shortcuts then
        local shortcuts_range = section_ranges.keyboard_shortcuts
        if i >= shortcuts_range.start_line and i <= shortcuts_range.end_line then
          goto continue
        end
      end

      -- Skip empty lines
      if lines[i]:match("^%s*$") then
        goto continue
      end

      -- Skip section titles (lines ending with colon)
      if lines[i]:match(":$") then
        goto continue
      end

      -- This is an actionable line
      logger.log_timing_event("CURSOR_POSITIONING_INNER_COMPLETE")
      -- First scroll to top to keep logo visible, then set cursor
      vim.cmd('normal! gg')
      vim.api.nvim_win_set_cursor(0, {i, 0})
      break
    end
    ::continue::
  end
end

-- Function to refresh an existing Nexus buffer
function M.refresh_buffer(buf)
  logger.log_timing_event("REFRESH_BUFFER_START")
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    logger.log_timing_event("REFRESH_BUFFER_INVALID_BUFFER")
    return
  end

  -- Check if this is actually a Nexus buffer
  logger.log_timing_event("REFRESH_BUFFER_VALIDATION_START")
  local buf_name = vim.api.nvim_buf_get_name(buf)
  if not buf_name:match('Nexus$') then
    logger.log_timing_event("REFRESH_BUFFER_NOT_NEXUS")
    return
  end
  logger.log_timing_event("REFRESH_BUFFER_VALIDATION_COMPLETE")

  logger.log_timing_event("REFRESH_RENDER_START")
  local current_config = config.get()
  local render = registry.get('nexus.render')
  local files, section_ranges = render.render_git_status(buf, current_config)
  logger.log_timing_event("REFRESH_RENDER_COMPLETE")

  logger.log_timing_event("REFRESH_GIT_STATE_START")
  local git_state = registry.get('nexus.state.git')
  local is_git_repo = git_state.is_git_repo()
  logger.log_timing_event("REFRESH_GIT_STATE_COMPLETE")

  logger.log_timing_event("REFRESH_KEYMAPS_START")
  local keymaps = registry.get('nexus.keymaps')
  keymaps.setup_keymaps(buf, files, current_config, is_git_repo, function(buf, cached_files)
    logger.log_timing_event("REFRESH_CALLBACK_START")
    render.render_git_status(buf, current_config, cached_files)
    logger.log_timing_event("REFRESH_CALLBACK_COMPLETE")
  end, section_ranges)
  logger.log_timing_event("REFRESH_KEYMAPS_COMPLETE")
  logger.log_timing_event("REFRESH_BUFFER_COMPLETE")
end

return M