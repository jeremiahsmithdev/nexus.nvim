local M = {}

local dashboard = require('nexus.ui.dashboard')
local shortcuts = require('nexus.ui.shortcuts')
local git_commits = require('nexus.git.commits')
local git_status = require('nexus.git.status')
local folding = require('nexus.ui.folding')
local logger = require('nexus.logger')

-- Build all sections based on configuration
function M.build_sections(config, is_git_repo, files)
  local sections = {}
  
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
  
  -- Recent commits section
  if is_git_repo and config.show_recent_commits then
    local commits = git_commits.get_git_log(config)
    if #commits > 0 then
      local commits_lines = {"Recent Commits:", ""}
      for i, commit in ipairs(commits) do
        local line
        if commit.decoration then
          line = string.format("  %s (%s) %s", commit.hash, commit.decoration, commit.message)
        else
          line = string.format("  %s %s", commit.hash, commit.message)
        end
        table.insert(commits_lines, line)
      end
      table.insert(commits_lines, "")
      sections.recent_commits = commits_lines
    end
  end
  
  -- Git status section
  if is_git_repo and config.show_git_status then
    if #files == 0 then
      local no_changes_lines = {"No changes detected", ""}
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
  
  -- Claude conversations section (placeholder for future implementation)
  if config.show_claude_conversations then
    -- This would be implemented when the feature is added
    sections.claude_conversations = {"Claude Conversations:", "", "  (Feature not yet implemented)", ""}
  end
  
  return sections
end

return M