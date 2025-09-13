local M = {}

local dashboard = require('nexus.ui.dashboard')
local shortcuts = require('nexus.ui.shortcuts')
local git_status = require('nexus.git.status')
local folding = require('nexus.ui.folding')
local logger = require('nexus.logger')

-- Build all sections based on configuration
function M.build_sections(config, is_git_repo, files, commits)
  local sections = {}
  
  -- Project name section
  local logo = require('nexus.ui.logo')
  local project_name = logo._get_project_name()
  if project_name then
    -- Center the project name with padding
    local padding = math.floor((48 - #project_name) / 2)  -- 48 is roughly the width of the NEXUS logo
    local centered_project_name = string.rep(" ", padding) .. project_name
    sections.project_name = {centered_project_name, ""}
  end
  
  -- Dashboard buttons section
  if config.show_dashboard_buttons then
    local button_lines = dashboard.get_dashboard_buttons(config)
    if #button_lines > 0 then
      sections.dashboard_buttons = button_lines
    end
  end
  
  -- Keyboard shortcuts section
  if config.show_keyboard_shortcuts then
    local shortcut_lines = shortcuts.get_keyboard_shortcuts(config, is_git_repo)
    if #shortcut_lines > 0 then
      sections.keyboard_shortcuts = shortcut_lines
    end
  end
  
  -- Todo section
  if config.show_todos then
    local todo_component = require('nexus.render.components.todo')
    sections.todos = todo_component.build_todo_section(config)
  end
  
  -- Recent commits section
  if is_git_repo and config.show_recent_commits then
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
  if is_git_repo and config.show_git_status then
    if #files == 0 then
      local no_changes_lines = {"No changes detected"}
      sections.git_status = no_changes_lines
    else
      local git_status_lines = {"Git Status:", ""}
      
      -- Process files with optional limit
      local processed = folding.process_git_files(files, config.git_status_count)
      
      -- Render visible files
      for i, data in ipairs(processed.visible) do
        local padding = string.rep(" ", processed.max_filename_width - #data.full_name)
        local diff_stat = git_status.create_diff_stat(data.added, data.deleted, 40)
        
        local line = string.format("  %s%s%s", data.full_name, padding, diff_stat)
        table.insert(git_status_lines, line)
      end
      
      -- Add folded overflow content if files were hidden
      if #processed.hidden > 0 then
        logger.debug("GIT_STATUS", "Adding fold for hidden files", {
          total_files = #files,
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
  end
  
  -- Linear issues section
  if config.linear and config.linear.enabled then
    local linear_component = require('nexus.render.components.linear')
    sections.linear_issues = linear_component.build_linear_section(config)
  end
  
  -- Claude conversations section (placeholder for future implementation)
  if config.show_claude_conversations then
    -- This would be implemented when the feature is added
    sections.claude_conversations = {"Claude Conversations:", "", "  (Feature not yet implemented)"}
  end
  
  return sections
end

-- Setup folding for git status sections
function M.setup_folding(buf, lines, config, files)
  folding.setup_git_status_folding(buf, lines, config, files)
end

return M