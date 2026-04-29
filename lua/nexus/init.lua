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

  -- Phase 1: Immediate render (logo + loading placeholders) - must complete fast
  local async_loader = registry.get('nexus.async_loader')
  local keymaps = registry.get('nexus.keymaps')

  logger.log_timing_event("RENDER_IMMEDIATE_START")
  async_loader.render_immediate_ui(buf, current_config)
  logger.log_timing_event("RENDER_IMMEDIATE_COMPLETE")

  -- Set up minimal keymaps immediately (quit, refresh)
  logger.log_timing_event("KEYMAPS_MINIMAL_START")
  keymaps.setup_minimal_keymaps(buf, current_config)
  logger.log_timing_event("KEYMAPS_MINIMAL_COMPLETE")

  -- Phase 2: Async load git data and update buffer when ready
  logger.log_timing_event("ASYNC_LOAD_START")
  async_loader.load_git_data_async(buf, current_config, function(git_data)
    logger.log_timing_event("ASYNC_LOAD_CALLBACK_START")

    -- Verify buffer is still valid
    if not vim.api.nvim_buf_is_valid(buf) then
      logger.log_timing_event("ASYNC_LOAD_BUFFER_INVALID")
      return
    end

    -- IMPORTANT: Update git_state cache with async data BEFORE rendering
    -- This ensures any re-renders or callbacks that access git_state get the correct data
    local state = require('nexus.state')
    state.set('git', 'files', git_data.files or {})
    state.set('git', 'commits', git_data.commits or {})
    state.set('git', 'is_git_repo', git_data.is_git_repo)
    state.set('git', 'diff_stats', git_data.diff_stats or {})
    state.set('cache', 'git_status_timestamp', os.time())
    state.set('cache', 'git_commits_timestamp', os.time())
    logger.log_timing_event("GIT_STATE_CACHE_UPDATED")

    -- Kick off beads async refresh BEFORE the full render so the initial render
    -- shows "Loading issues..." instead of a misleading "No ready issues".
    -- The callback re-renders after both issues and epics finish loading.
    local config_mod = require('nexus.config')
    local is_git_repo = git_data.is_git_repo
    local render = registry.get('nexus.render')

    if config_mod.is_section_enabled("beads_issues") then
      local beads_state_mod = require('nexus.state.beads')
      if beads_state_mod.is_beads_available() and beads_state_mod.is_cli_installed() then
        -- Single combined fetch: one CLI call for non-ready filters (br list --json +
        -- Lua partition), or two concurrent calls joined internally for the ready filter.
        -- Either way, the callback fires exactly once when both caches are populated.
        beads_state_mod.fetch_issues_and_epics_async(function()
          if not vim.api.nvim_buf_is_valid(buf) then return end
          logger.log_timing_event("BEADS_ASYNC_RENDER_START")
          local bf, br = render.render_git_status(buf, current_config, git_data.files, git_data.commits)
          keymaps.setup_keymaps(buf, bf, current_config, is_git_repo, function(rbuf, cf)
            render.render_git_status(rbuf, current_config, cf)
          end, br)
          logger.log_timing_event("BEADS_ASYNC_RENDER_COMPLETE")
        end)
      end
    end

    -- Full render with actual git data (pass both files AND commits)
    logger.log_timing_event("FULL_RENDER_START")
    local files, section_ranges = render.render_git_status(buf, current_config, git_data.files, git_data.commits)
    logger.log_timing_event("FULL_RENDER_COMPLETE")

    -- Set up full keymaps with file navigation
    logger.log_timing_event("KEYMAPS_FULL_START")
    keymaps.setup_keymaps(buf, files, current_config, is_git_repo, function(refresh_buf, cached_files)
      logger.log_timing_event("REFRESH_CALLBACK_START")
      render.render_git_status(refresh_buf, current_config, cached_files)
      logger.log_timing_event("REFRESH_CALLBACK_COMPLETE")
    end, section_ranges)
    logger.log_timing_event("KEYMAPS_FULL_COMPLETE")

    -- Position cursor on first actionable line
    logger.log_timing_event("CURSOR_POSITIONING_START")
    M.position_cursor_on_actionable_line(buf, section_ranges)
    logger.log_timing_event("CURSOR_POSITIONING_COMPLETE")

    -- Trigger async Claude conversation scan (if section enabled).
    -- The initial render already showed a "Loading conversations..." placeholder.
    -- When the scan completes (disk cache hit = immediate; full scan = background),
    -- re-render the buffer so the section updates with actual conversation data.
    if config_mod.is_section_enabled("claude_conversations") then
      local claude_mod = require('nexus.claude')
      logger.log_timing_event("CLAUDE_SCAN_START")
      claude_mod.refresh_async(current_config, function(conversations)
        logger.log_timing_event("CLAUDE_SCAN_CALLBACK")
        if not vim.api.nvim_buf_is_valid(buf) then return end
        -- Re-render so the Claude section shows loaded data instead of the placeholder
        local new_files, new_ranges = render.render_git_status(buf, current_config, git_data.files, git_data.commits)
        keymaps.setup_keymaps(buf, new_files, current_config, is_git_repo, function(refresh_buf, cached_files)
          render.render_git_status(refresh_buf, current_config, cached_files)
        end, new_ranges)
        logger.log_timing_event("CLAUDE_SCAN_RENDER_COMPLETE")
      end)
    end

    logger.log_timing_event("ASYNC_LOAD_CALLBACK_COMPLETE")
  end)

  logger.log_timing_event("OPEN_COMPLETE")
  logger.end_timing_session()
end

-- Position cursor at the top of the buffer so the logo and all sections are
-- visible. We previously hunted for the "first actionable line" (first dashboard
-- button) as a QoL optimization, but that forced the viewport to scroll past the
-- logo whenever the target line sat below window height. Neovim's internal
-- invariant (topline <= cursor_line <= topline + win_height) overrides any
-- winrestview topline=1 when the cursor is deep in the buffer — there's no way
-- to show both the logo AND a cursor halfway down the buffer in a small window.
-- Keeping cursor at line 1 guarantees the dashboard renders as designed.
function M.position_cursor_on_actionable_line(buf, section_ranges)
  logger.log_timing_event("CURSOR_POSITIONING_INNER_START")
  pcall(vim.api.nvim_win_set_cursor, 0, {1, 0})
  logger.log_timing_event("CURSOR_POSITIONING_INNER_COMPLETE")
end

-- Refresh an existing Nexus buffer asynchronously.
-- Mirrors M.open()'s Phase-2 path: kicks off load_git_data_async, updates the
-- state cache when it returns, then re-renders and re-installs keymaps. Linear
-- and Huly refreshes piggy-back on the same trigger so a single 'r' press
-- refreshes everything the dashboard shows.
function M.refresh_buffer(buf)
  logger.log_timing_event("REFRESH_BUFFER_START")
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    logger.log_timing_event("REFRESH_BUFFER_INVALID_BUFFER")
    return
  end

  local buf_name = vim.api.nvim_buf_get_name(buf)
  if not buf_name:match('Nexus$') then
    logger.log_timing_event("REFRESH_BUFFER_NOT_NEXUS")
    return
  end

  local current_config = config.get()
  local refresh_start = vim.uv and vim.uv.hrtime() or vim.loop.hrtime()

  -- Fire-and-forget refresh for issue trackers, deferred to the next event-loop
  -- tick. Linear's refresh_data does a *synchronous* HTTP call to api.linear.app
  -- and would otherwise block the keypress (and delay the async git fetch from
  -- starting). Deferring lets the git child process launch immediately; Linear
  -- paints in later via state.notify when its call returns.
  vim.defer_fn(function()
    if current_config.linear and current_config.linear.enabled then
      local linear_state = require('nexus.state.linear')
      linear_state.refresh_data(current_config)
    end
    if current_config.huly and current_config.huly.enabled then
      local huly_state = require('nexus.state.huly')
      huly_state.refresh_data(current_config)
    end
  end, 0)

  -- Invalidate git cache so any concurrent reader doesn't see stale data while
  -- the async fetch is in flight. The async callback below will repopulate it.
  local git_state = registry.get('nexus.state.git')
  git_state.invalidate_cache()

  local async_loader = registry.get('nexus.async_loader')
  local render = registry.get('nexus.render')
  local keymaps = registry.get('nexus.keymaps')

  logger.log_timing_event("REFRESH_ASYNC_LOAD_START")
  async_loader.load_git_data_async(buf, current_config, function(git_data)
    if not vim.api.nvim_buf_is_valid(buf) then
      logger.log_timing_event("REFRESH_BUFFER_INVALIDATED_DURING_LOAD")
      return
    end

    -- Repopulate git_state cache so subsequent re-renders (including those
    -- triggered by other state.notify subscribers) see the fresh data.
    local state = require('nexus.state')
    state.set('git', 'files', git_data.files or {})
    state.set('git', 'commits', git_data.commits or {})
    state.set('git', 'is_git_repo', git_data.is_git_repo)
    state.set('git', 'diff_stats', git_data.diff_stats or {})
    state.set('cache', 'git_status_timestamp', os.time())
    state.set('cache', 'git_commits_timestamp', os.time())

    local is_git_repo = git_data.is_git_repo
    logger.log_timing_event("REFRESH_RENDER_START")
    local files, section_ranges = render.render_git_status(buf, current_config, git_data.files, git_data.commits)
    logger.log_timing_event("REFRESH_RENDER_COMPLETE")

    keymaps.setup_keymaps(buf, files, current_config, is_git_repo, function(refresh_buf, cached_files)
      render.render_git_status(refresh_buf, current_config, cached_files)
    end, section_ranges)

    local elapsed_ms = ((vim.uv and vim.uv.hrtime() or vim.loop.hrtime()) - refresh_start) / 1e6
    vim.notify(string.format('Nexus refreshed (%dms)', math.floor(elapsed_ms)), vim.log.levels.INFO)

    logger.log_timing_event("REFRESH_BUFFER_COMPLETE")
  end)
end

return M