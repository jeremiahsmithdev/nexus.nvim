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
  local lines, section_ranges, logo_section, left_padding = layout.layout_sections(sections, config, width)

  -- Store section ranges as buffer-local var so keymap handlers can access it
  -- for O(1) section detection without it being threaded through every closure.
  vim.b[buf].nexus_section_ranges = section_ranges
  -- Store left_padding so incremental section renders can apply the same alignment.
  vim.b[buf].nexus_git_left_padding = left_padding or 0

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

  -- Rebuild and restore folds as ONE atomic operation in the real Nexus window.
  --
  -- WHY ONE BLOCK: nvim_buf_set_lines above destroys all manual folds every
  -- render, so we must wipe (zE), recreate, and re-apply saved state together.
  -- Folds are *window-local*: when the git watcher fires a refresh while the
  -- user is focused in another window (BufWritePost on a saved file, FocusGained
  -- on alt-tab), nvim_buf_call falls back to nvim's hidden autocmd window and the
  -- fold ops there evaporate when it closes. The result is exactly the reported
  -- drift: stale folds from the *previous* layout survive in the visible window
  -- on top of the new content, so "(N lines hidden)" lands mid-section. A later
  -- focused 'r' render wipes them and it looks "fixed". Running every fold op
  -- inside a single nvim_win_call on the real window closes that gap — and a
  -- single block (vs the previous two) means the wipe and the recreate can never
  -- straddle two different window contexts.
  --
  -- WINDOW RESOLUTION: prefer the window in the current tabpage (the one the
  -- user is actually looking at) before falling back to any window across tabs.
  local folding = require('nexus.ui.folding')
  local function resolve_nexus_win()
    local cur = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(cur) and vim.api.nvim_win_get_buf(cur) == buf then
      return cur
    end
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(w) == buf then return w end
    end
    return (vim.fn.win_findbuf(buf) or {})[1]
  end
  local nexus_win = resolve_nexus_win()
  local ranges_hash = folding.compute_ranges_hash(section_ranges)
  if nexus_win and vim.api.nvim_win_is_valid(nexus_win) then
    vim.api.nvim_win_call(nexus_win, function()
      pcall(function() vim.cmd('normal! zE') end)
      sections_component.setup_folding(buf, lines, config, files)
      folding.setup_section_folds(buf, section_ranges)
      folding.apply_fold_states(buf, section_ranges, ranges_hash)
      folding.update_section_arrows(buf, section_ranges)
    end)
  end

  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  -- Re-anchor cursor in case the new layout left it on a forbidden line.
  -- nvim_buf_set_lines doesn't fire CursorMoved when a stationary cursor's
  -- underlying content changes, so an explicit snap is required.
  require('nexus.cursor_guard').snap_to_legal(buf)

  return files, section_ranges
end

--- Re-render a single named section in-place without touching the rest of the buffer.
--- Reads the current section range from vim.b[buf].nexus_section_ranges and replaces
--- only those lines.  Updates section_ranges metadata and shifts downstream entries
--- when the new line count differs from the old one.
---
--- Primary consumer: T9 optimistic beads updates (status / close / priority / note).
--- Full render is still used on cold open and on explicit 'r' refresh.
---
--- Supported section names: any key from section_ranges
--- (most tested path: 'beads_issues').
---
---@param buf number Buffer handle
---@param section_name string Key as it appears in section_ranges (e.g. 'beads_issues')
function M.render_section(buf, section_name)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local section_ranges = vim.b[buf].nexus_section_ranges
  if not section_ranges or not section_ranges[section_name] then
    -- Section not tracked yet (e.g. cold open hasn't finished); fall back to full render.
    local logger_mod = require('nexus.logger')
    logger_mod.debug('RENDER', 'render_section: ' .. section_name .. ' not in section_ranges; falling back to full render')
    local config_mod = require('nexus.config')
    M.render_git_status(buf, config_mod.get())
    return
  end

  local old_range = section_ranges[section_name]
  local old_start = old_range.start_line  -- 1-indexed, inclusive
  local old_end   = old_range.end_line    -- 1-indexed, inclusive

  -- Build fresh lines for just this section.
  local config_mod  = require('nexus.config')
  local current_config = config_mod.get()

  -- Route to section-specific builder to avoid rebuilding all sections.
  local raw_lines
  if section_name == 'beads_issues' then
    local beads_component = require('nexus.render.components.beads')
    raw_lines = beads_component.build_beads_section(current_config)
  elseif section_name == 'todos' then
    local todo_component = require('nexus.render.components.todo')
    raw_lines = todo_component.build_todo_section(current_config)
  else
    -- Generic fallback: rebuild all sections and extract the one we need.
    local git_state_mod = require('nexus.state.git')
    local sections_component = require('nexus.render.components.sections')
    local all_sections = sections_component.build_sections(
      current_config,
      git_state_mod.is_git_repo(),
      git_state_mod.get_git_status(),
      git_state_mod.get_git_commits()
    )
    raw_lines = all_sections[section_name] or {}
  end

  -- Apply the left_padding that was recorded during the last full render.
  -- Button sections (dashboard_buttons, keyboard_shortcuts) use centering instead;
  -- they are not expected incremental-render targets so we leave them as-is.
  local is_button_section = (section_name == 'dashboard_buttons' or section_name == 'keyboard_shortcuts')
  local new_lines
  if is_button_section then
    new_lines = raw_lines
  else
    local padding_str = string.rep(" ", vim.b[buf].nexus_git_left_padding or 0)
    new_lines = {}
    for _, line in ipairs(raw_lines) do
      table.insert(new_lines, padding_str .. line)
    end
  end

  -- Replace only the section's lines.
  -- nvim_buf_set_lines(buf, start, end, strict, repl):
  --   start/end are 0-indexed; end is exclusive.
  --   old_start-1 = 0-indexed inclusive start
  --   old_end     = 0-indexed exclusive end (== 1-indexed inclusive end)
  local new_line_count = #new_lines
  local old_line_count = old_end - old_start + 1
  local delta = new_line_count - old_line_count

  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, old_start - 1, old_end, false, new_lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  -- Update section_ranges metadata.
  -- Must use vim.deepcopy so we don't mutate the cached buffer-local table in-place
  -- (Neovim serialises vim.b values, but being explicit avoids surprises).
  local new_ranges = vim.deepcopy(section_ranges)
  new_ranges[section_name].end_line = old_end + delta

  -- Shift every section that starts after the replaced block.
  if delta ~= 0 then
    for name, range in pairs(new_ranges) do
      if name ~= section_name and range.start_line > old_end then
        new_ranges[name] = {
          start_line = range.start_line + delta,
          end_line   = range.end_line   + delta,
        }
      end
    end
  end

  vim.b[buf].nexus_section_ranges = new_ranges

  -- Keep ui_state in sync (used by events / shortcuts dynamic update).
  local ui_state = require('nexus.state.ui')
  ui_state.update_section_ranges(new_ranges)

  -- Section-specific post-render hooks.
  if section_name == 'beads_issues' and new_ranges.beads_issues then
    -- Re-build the line-number → issue-id map for Enter / status keymaps.
    local beads_component = require('nexus.render.components.beads')
    beads_component.update_line_mapping(new_ranges.beads_issues.start_line)

    -- Clear stale beads highlights in the replaced range, then re-apply.
    local ns_id = vim.api.nvim_create_namespace('nexus_beads')
    local new_start = new_ranges.beads_issues.start_line
    local new_end   = new_ranges.beads_issues.end_line
    vim.api.nvim_buf_clear_namespace(buf, ns_id, new_start - 1, new_end)
    beads_component.apply_beads_highlighting(buf, new_start)
  elseif section_name == 'todos' and new_ranges.todos then
    -- Clear stale todo highlights in the replaced range, then re-apply.
    local todo_component = require('nexus.render.components.todo')
    local ns_id = vim.api.nvim_create_namespace('nexus_todo')
    local new_start = new_ranges.todos.start_line
    local new_end   = new_ranges.todos.end_line
    vim.api.nvim_buf_clear_namespace(buf, ns_id, new_start - 1, new_end)
    todo_component.apply_todo_highlighting(buf, new_start)
  end

  -- Rebuild folds with fresh ranges. A partial line replacement leaves the
  -- old section without a fold mark (its lines were destroyed) and may leave
  -- stale fold boundaries on neighbouring sections. `zE` wipes all folds so
  -- setup_section_folds can recreate them cleanly against the new layout.
  -- Same atomic, window-scoped fold rebuild as the full render (see the long
  -- comment in M.render_git_status). apply_fold_states establishes the all-open
  -- baseline with zR internally, so no separate initialize pass is needed.
  local folding = require('nexus.ui.folding')
  local function resolve_nexus_win()
    local cur = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(cur) and vim.api.nvim_win_get_buf(cur) == buf then
      return cur
    end
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(w) == buf then return w end
    end
    return (vim.fn.win_findbuf(buf) or {})[1]
  end
  local nexus_win = resolve_nexus_win()
  local ranges_hash = folding.compute_ranges_hash(new_ranges)
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  if nexus_win and vim.api.nvim_win_is_valid(nexus_win) then
    vim.api.nvim_win_call(nexus_win, function()
      pcall(function() vim.cmd('normal! zE') end)
      folding.setup_section_folds(buf, new_ranges)
      folding.apply_fold_states(buf, new_ranges, ranges_hash)
      folding.update_section_arrows(buf, new_ranges)
    end)
  end
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  -- Same rationale as in M.render: a partial re-render may shift content
  -- under a stationary cursor without firing CursorMoved.
  require('nexus.cursor_guard').snap_to_legal(buf)
end


return M