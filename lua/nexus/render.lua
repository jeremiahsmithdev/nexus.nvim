local M = {}

-- NOTE: Module imports are lazy-loaded inside render_git_status() to avoid
-- blocking startup. This prevents synchronous loading of 7+ modules when
-- render.lua is first required.

function M.render_git_status(buf, config, cached_files, cached_commits)
  -- Lazy load all dependencies inside function to avoid startup blocking
  local logger = require('nexus.logger')
  local layout = require('nexus.render.layout')
  local sections_component = require('nexus.render.components.sections')
  local highlighting = require('nexus.render.components.highlighting')
  local events = require('nexus.render.components.events')
  local git_state = require('nexus.state.git')
  local ui_state = require('nexus.state.ui')
  local logo = require('nexus.ui.logo')
  -- Update configuration in state
  ui_state.update_config(config or {})

  -- Get git state without forcing refresh (data comes from async loader or cache)
  -- NOTE: force_refresh() removed to prevent blocking - async_loader handles git data
  local is_git_repo = git_state.is_git_repo()
  local files = cached_files or git_state.get_git_status()
  local commits = cached_commits or git_state.get_git_commits()

  -- Get display width
  local width = layout.get_display_width()

  -- Build sections using component (pass both files and commits)
  local sections = sections_component.build_sections(config, is_git_repo, files, commits)
  
  -- Layout sections using component
  local lines, section_ranges, logo_section = layout.layout_sections(sections, config, width)

  -- Update beads line mapping with absolute line numbers (if beads section exists)
  if section_ranges.beads_issues then
    local beads_component = require('nexus.render.components.beads')
    beads_component.update_line_mapping(section_ranges.beads_issues.start_line)
  end

  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Render image logo if enabled (after buffer content is set)
  if config.logo_selection == "image" then
    logo.render_image_logo(buf, config, 0, 0)
  end

  -- Set up folding for git status overflow
  sections_component.setup_folding(buf, lines, config, files)

  -- Set up section folds for all collapsible sections
  local folding = require('nexus.ui.folding')
  folding.setup_section_folds(buf, section_ranges)

  -- Update state with section ranges and logo info
  ui_state.update_section_ranges(section_ranges)
  ui_state.update_logo_section(logo_section)

  -- Add syntax highlighting using component
  highlighting.apply_highlighting(buf, lines, config, is_git_repo, files, logo_section, section_ranges)

  -- Update UI state with section ranges for dynamic shortcuts
  ui_state.update_section_ranges(section_ranges)

  -- Set up dynamic shortcut updating on cursor movement (only if shortcuts are enabled)
  local config_module = require('nexus.config')
  if config_module.is_section_enabled("keyboard_shortcuts") then
    events.setup_dynamic_shortcuts(buf, config, is_git_repo, section_ranges)
  end

  -- Conditionally initialize and apply fold states.
  -- Skipped when layout is identical to the last apply and no fold toggles occurred,
  -- avoiding redundant cursor movement (and visible flicker) on stable 'r' refreshes.
  local fold_state_mod = require('nexus.state.folds')
  local ranges_hash = folding.compute_ranges_hash(section_ranges)
  if fold_state_mod.is_apply_needed(ranges_hash) then
    -- Initialize all folds to open state (establishes baseline before applying saved states)
    folding.initialize_folds_to_open(buf, section_ranges)
    -- Apply saved fold states from persistent storage (pass hash to avoid recompute)
    folding.apply_fold_states(buf, section_ranges, ranges_hash)
  else
    logger.debug("FOLD", "Skipping fold state apply (layout and state unchanged)")
  end

  -- Update section arrows to reflect fold states
  folding.update_section_arrows(buf, section_ranges)

  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  return files, section_ranges
end


return M