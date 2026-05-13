local M = {}

local dashboard = require('nexus.ui.dashboard')
local shortcuts = require('nexus.ui.shortcuts')
local git_status = require('nexus.git.status')
local folding = require('nexus.ui.folding')
local logger = require('nexus.logger')

-- Build all sections based on configuration
function M.build_sections(config, is_git_repo, files, commits)
  local sections = {}
  local config_module = require('nexus.config')

  -- Project name section (always enabled)
  local logo = require('nexus.ui.logo')
  local project_name = logo._get_project_name()
  if project_name then
    -- Center the project name with padding
    local padding = math.floor((48 - #project_name) / 2)  -- 48 is roughly the width of the NEXUS logo
    -- Optimized: Use table concatenation for padding
    local centered_project_name = table.concat({string.rep(" ", padding), project_name})
    sections.project_name = {centered_project_name, ""}
  end

  -- Dashboard buttons section
  if config_module.is_section_enabled("dashboard_buttons") then
    local button_lines = dashboard.get_dashboard_buttons(config)
    if #button_lines > 0 then
      sections.dashboard_buttons = button_lines
    end
  end

  -- Keyboard shortcuts section
  if config_module.is_section_enabled("keyboard_shortcuts") then
    local shortcut_lines = shortcuts.get_keyboard_shortcuts(config, is_git_repo)
    if #shortcut_lines > 0 then
      sections.keyboard_shortcuts = shortcut_lines
    end
  end

  -- Todo section
  if config_module.is_section_enabled("todos") then
    local todo_component = require('nexus.render.components.todo')
    sections.todos = todo_component.build_todo_section(config)
  end
  
  -- Recent commits section
  if is_git_repo and config_module.is_section_enabled("recent_commits") then
    -- Use passed commits from batch operation, or fallback to state
    local commits_to_use = commits
    if not commits_to_use or #commits_to_use == 0 then
      local git_state = require('nexus.state.git')
      commits_to_use = git_state.get_git_commits()
    end

    if commits_to_use and #commits_to_use > 0 then
      local commits_lines = {"Recent Commits:", ""}
      for i, commit in ipairs(commits_to_use) do
        local line
        local review_icon = ""

        -- Add review status indicator if enabled
        if config.show_commit_review and commit.review_status then
          if commit.review_status == "reviewed" then
            review_icon = "✓ "
          elseif commit.review_status == "needs_attention" then
            review_icon = "⚠ "
          else -- unreviewed
            review_icon = "☐ "
          end
        end

        if commit.decoration then
          line = string.format("  %s%s (%s) %s", review_icon, commit.hash, commit.decoration, commit.message)
        else
          line = string.format("  %s%s %s", review_icon, commit.hash, commit.message)
        end
        table.insert(commits_lines, line)
      end
      sections.recent_commits = commits_lines
    end
  end
  
  -- Git status section
  if is_git_repo and config_module.is_section_enabled("git_status") then
    if #files == 0 then
      local no_changes_lines = {"No changes detected"}
      sections.git_status = no_changes_lines
    else
      local git_status_lines = {"Git Status:", ""}

      -- Separate untracked files if collapse_untracked is enabled
      local tracked_files = files
      local untracked_count = 0
      if config.collapse_untracked then
        tracked_files = {}
        for _, f in ipairs(files) do
          if f.status == "??" then
            untracked_count = untracked_count + 1
          else
            table.insert(tracked_files, f)
          end
        end
        -- If all files are untracked, show only the summary
        if #tracked_files == 0 and untracked_count > 0 then
          table.insert(git_status_lines, string.format("  +%d untracked files", untracked_count))
          sections.git_status = git_status_lines
          goto git_status_done
        end
      end

      -- Process tracked files with optional limit
      local processed = folding.process_git_files(tracked_files, config.git_status_count)

      -- Render visible files (optimized for performance)
      -- Pre-allocate the git_status_lines table to avoid repeated reallocations
      local visible_count = #processed.visible
      for i = 1, visible_count do
        git_status_lines[i + 2] = nil  -- Clear any existing entry
      end

      for i, data in ipairs(processed.visible) do
        local padding = string.rep(" ", processed.max_filename_width - #data.full_name)
        local diff_stat = git_status.create_diff_stat(data.added, data.deleted, 40)

        -- Optimized: Use table pre-allocation and direct assignment instead of table.insert
        git_status_lines[i + 2] = string.format("  %s%s%s", data.full_name, padding, diff_stat)
      end

      -- Add untracked summary line if collapse is on and there are untracked files
      if config.collapse_untracked and untracked_count > 0 then
        table.insert(git_status_lines, string.format("  +%d untracked files", untracked_count))
      end

      -- Add folded overflow content if files were hidden
      if #processed.hidden > 0 then
        logger.debug("GIT_STATUS", "Adding fold for hidden files", {
          total_files = #tracked_files,
          visible_count = #processed.visible,
          hidden_count = #processed.hidden
        })

        -- Add the hidden files directly (they will be folded with custom fold text)
        for i, data in ipairs(processed.hidden) do
          local padding = string.rep(" ", processed.max_filename_width - #data.full_name)
          local diff_stat = git_status.create_diff_stat(data.added, data.deleted, 40)
          local line = string.format("  %s%s%s", data.full_name, padding, diff_stat)
          table.insert(git_status_lines, line)
        end
      end

      sections.git_status = git_status_lines
    end
    ::git_status_done::
  end
  
  -- Linear issues section
  if config_module.is_section_enabled("linear_issues") and config.linear and config.linear.enabled then
    local linear_component = require('nexus.render.components.linear')
    sections.linear_issues = linear_component.build_linear_section(config)
  end

  -- Huly issues section (DORMANT: only rendered when explicitly enabled)
  if config_module.is_section_enabled("huly_issues") and config.huly and config.huly.enabled then
    local huly_component = require('nexus.render.components.huly')
    sections.huly_issues = huly_component.build_huly_section(config)
  end

  -- Beads issues section (local git-backed issue tracker)
  if config_module.is_section_enabled("beads_issues") then
    local beads_component = require('nexus.render.components.beads')
    sections.beads_issues = beads_component.build_beads_section(config)
  end

  -- Claude conversations section (async-loaded; shows cached data or a loading placeholder)
  if config_module.is_section_enabled("claude_conversations") then
    local claude = require('nexus.claude')
    local conversations = claude.get_cached()
    if conversations == nil then
      -- Scan not yet complete; refresh_async will trigger a re-render when ready
      sections.claude_conversations = {"Claude Conversations:", "", "  Loading conversations..."}
    elseif #conversations == 0 then
      sections.claude_conversations = {"Claude Conversations:", "", "  No conversations found"}
    else
      local lines = {"Claude Conversations:", ""}
      local max_show = (config.claude_conversations_count or 5)
      for i, conv in ipairs(conversations) do
        if i > max_show then break end
        local summary = conv.content or 'No summary'
        -- Truncate long summaries so lines stay readable
        if #summary > 55 then summary = summary:sub(1, 52) .. '...' end
        local line = string.format(" %d. [%s msgs] %s (%s)", i, conv.messages, summary, conv.modified)
        table.insert(lines, line)
      end
      sections.claude_conversations = lines
    end
  end
  
  return sections
end

-- Setup folding for git status sections
function M.setup_folding(buf, lines, config, files)
  -- When collapse_untracked is on, pass only tracked files to folding
  -- so overflow fold calculations match the rendered output
  local folding_files = files
  if config.collapse_untracked then
    folding_files = {}
    for _, f in ipairs(files) do
      if f.status ~= "??" then
        table.insert(folding_files, f)
      end
    end
  end
  folding.setup_git_status_folding(buf, lines, config, folding_files)
end

return M