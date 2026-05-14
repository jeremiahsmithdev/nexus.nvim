local M = {}

local git_status = require('nexus.git.status')
local folding = require('nexus.ui.folding')

-- Main highlighting function - applies all highlighting types
function M.apply_highlighting(buf, lines, config, is_git_repo, files, logo_section, section_ranges)
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)
  
  -- 1. Logo highlighting - highlight entire logo section
  M.apply_logo_highlighting(buf, lines, config, logo_section)
  
  -- 2. Button highlighting - find button lines
  M.apply_button_highlighting(buf, lines, config)
  
  -- 3. Commits highlighting
  M.apply_commits_highlighting(buf, lines, config, is_git_repo, section_ranges)
  
  -- 4. Git status highlighting
  M.apply_git_status_highlighting(buf, lines, config, is_git_repo, files, section_ranges)
  
  -- 5. Linear issues highlighting
  M.apply_linear_highlighting(buf, lines, config)
  
  -- 6. Keyboard shortcuts highlighting
  M.apply_shortcuts_highlighting(buf, lines, config, section_ranges)
  
  -- 7. Todo highlighting
  M.apply_todo_highlighting(buf, lines, config)

  -- 8. Beads issues highlighting
  M.apply_beads_highlighting(buf, lines, config)
end

-- Logo highlighting
function M.apply_logo_highlighting(buf, lines, config, logo_section)
  local logo_ns = vim.api.nvim_create_namespace('nexus_logo')
  local logo_color = config.logo_color or "String"
  if logo_section then
    for i = logo_section.start_line, logo_section.end_line do
      local line_content = lines[i]
      if line_content and #line_content > 0 then -- Only highlight non-empty lines
        -- Check if this line is the project name (centered text without special characters)
        local is_project_name = false
        if line_content and not line_content:match("[%[%]{}=]") and not line_content:match("^%s*$") and line_content:match("^%s*[A-Za-z]") then
          is_project_name = true
        end
        
        if is_project_name then
          -- Check if line has "project on  branch" format
          -- Find " on " pattern (space-on-space before the git icon)
          local on_pattern_start, on_pattern_end = line_content:find(" on ")
          if on_pattern_start then
            -- Highlight project name (before " on")
            local project_start = line_content:find("%S")  -- First non-whitespace
            if project_start then
              vim.api.nvim_buf_set_extmark(buf, logo_ns, i - 1, project_start - 1, {
                end_col = on_pattern_start - 1,
                hl_group = "DiagnosticWarn",
              })
            end
            -- Highlight " on " in Comment color (dimmed)
            vim.api.nvim_buf_set_extmark(buf, logo_ns, i - 1, on_pattern_start - 1, {
              end_col = on_pattern_end,
              hl_group = "Comment",
            })
            -- Find the git icon (nerd font icon after "on ")
            local icon_start, icon_end = line_content:find("", on_pattern_end, true)
            if icon_start then
              -- Highlight git icon in String color (green)
              vim.api.nvim_buf_set_extmark(buf, logo_ns, i - 1, icon_start - 1, {
                end_col = icon_end,
                hl_group = "String",
              })
              -- Highlight branch name (after icon) in Function color
              vim.api.nvim_buf_set_extmark(buf, logo_ns, i - 1, icon_end, {
                end_col = #line_content,
                hl_group = "Function",
              })
            else
              -- No icon found, highlight rest as branch
              vim.api.nvim_buf_set_extmark(buf, logo_ns, i - 1, on_pattern_end, {
                end_col = #line_content,
                hl_group = "Function",
              })
            end
          else
            -- No branch info, highlight entire project name
            vim.api.nvim_buf_set_extmark(buf, logo_ns, i - 1, 0, {
              end_col = #line_content,
              hl_group = "DiagnosticWarn",
            })
          end
        else
          vim.api.nvim_buf_set_extmark(buf, logo_ns, i - 1, 0, {
            end_col = #line_content,
            hl_group = logo_color,
          })
        end
      end
    end
  end
end

-- Button highlighting
function M.apply_button_highlighting(buf, lines, config)
  local config_module = require('nexus.config')
  if not config_module.is_section_enabled("dashboard_buttons") then
    return
  end
  
  local button_ns = vim.api.nvim_create_namespace('nexus_buttons')
  for i, line in ipairs(lines) do
    if line:match('Find file') or line:match('Recently opened') or line:match('Find word') or 
       line:match('New file') or line:match('Bookmarks') or line:match('Restore session') then
      -- Highlight the entire line gray
      vim.api.nvim_buf_set_extmark(buf, button_ns, i - 1, 0, {
        end_col = #line,
        hl_group = 'Comment',
      })

      -- Find and highlight the icon green
      local icon_start, icon_end = line:find('[󰈞󰋚󰊄󰈔󰃃󰁯]')
      if icon_start then
        vim.api.nvim_buf_set_extmark(buf, button_ns, i - 1, icon_start - 1, {
          end_col = icon_end,
          hl_group = 'String',
        })
      end
    end
  end
end

-- Commits highlighting
function M.apply_commits_highlighting(buf, lines, config, is_git_repo, section_ranges)
  local config_module = require('nexus.config')
  if not is_git_repo or not config_module.is_section_enabled("recent_commits") then
    return
  end

  -- Scope the scan to the recent_commits section. Without this, the parens /
  -- hash regexes here trip on any line in the buffer that happens to contain
  -- 7+ hex chars or parenthesized text (e.g. `fix(watchers)` in another
  -- section's content), painting it with branch-decoration colors.
  local range = section_ranges and section_ranges.recent_commits
  local first_line = range and range.start_line or 1
  local last_line  = range and range.end_line   or #lines

  local commits_ns = vim.api.nvim_create_namespace('nexus_commits')
  for i = first_line, last_line do
    local line = lines[i]
    if line then
    -- Check for review status icons first
    if config.show_commit_review then
      local review_check = line:find('✓')
      local review_box = line:find('☐')
      local review_warning = line:find('⚠')
      
      if review_check then
        vim.api.nvim_buf_set_extmark(buf, commits_ns, i - 1, review_check - 1, {
          end_col = review_check,
          hl_group = 'DiagnosticOk',
        })
      elseif review_warning then
        vim.api.nvim_buf_set_extmark(buf, commits_ns, i - 1, review_warning - 1, {
          end_col = review_warning,
          hl_group = 'DiagnosticWarn',
        })
      elseif review_box then
        vim.api.nvim_buf_set_extmark(buf, commits_ns, i - 1, review_box - 1, {
          end_col = review_box,
          hl_group = 'Comment',
        })
      end
    end
    
    -- Look for commit hash pattern (7+ hex chars after spaces, accounting for review icons)
    local hash_start, hash_end = line:find('%s+[☐✓⚠]?%s*([a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+)')
    if hash_start and hash_end then
      -- Find the actual hash position within the captured group
      local actual_hash_start = line:find('[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]+', hash_start)
      if actual_hash_start then
        local actual_hash_end = actual_hash_start + 6 -- 7 char hash - 1
        vim.api.nvim_buf_set_extmark(buf, commits_ns, i - 1, actual_hash_start - 1, {
          end_col = actual_hash_end,
          hl_group = 'Number',
        })
      end

      -- Look for HEAD decoration
      local head_start, head_end = line:find('HEAD')
      if head_start then
        vim.api.nvim_buf_set_extmark(buf, commits_ns, i - 1, head_start - 1, {
          end_col = head_end,
          hl_group = 'Title',
        })
      end

      -- Branch/tag decoration: git log emits `<hash> (<refs>) <message>`, so
      -- the decoration parens sit immediately after the hash. Use a
      -- non-greedy match anchored to hash_end + 1 to avoid capturing
      -- parenthesized text later in the commit subject (e.g. conventional
      -- commit scopes like `fix(watchers)`).
      local paren_start, paren_end = line:find('%s+%b()', hash_end)
      -- Require the parens to sit immediately after the hash (at most one
      -- space). Anything further is part of the commit subject, not the
      -- git-log decoration.
      if paren_start and paren_end and paren_start - hash_end <= 2 then
        local open_paren = line:find('%(', paren_start)
        if open_paren and not line:sub(open_paren, paren_end):match('HEAD') then
          vim.api.nvim_buf_set_extmark(buf, commits_ns, i - 1, open_paren - 1, {
            end_col = paren_end,
            hl_group = 'Function',
          })
        end
      end
    end
    end
  end
end

-- Git status highlighting that works with processed data
function M.apply_git_status_highlighting(buf, lines, config, is_git_repo, files, section_ranges)
  local config_module = require('nexus.config')
  if not is_git_repo or not config_module.is_section_enabled("git_status") or not files or #files == 0 then
    return
  end

  local git_ns = vim.api.nvim_create_namespace('nexus_git_status')
  local git_status_start = nil
  local section_end = nil

  -- Prefer the authoritative range from section_ranges (covers the case where
  -- a `+N untracked files` summary line shifts the visible offset relative to
  -- display_files index). Fall back to header-string scan if not provided.
  if section_ranges and section_ranges.git_status then
    git_status_start = section_ranges.git_status.start_line
    section_end      = section_ranges.git_status.end_line
  else
    for i, line in ipairs(lines) do
      if line:match('Git Status:') then
        git_status_start = i
        break
      end
    end
  end

  if not git_status_start then
    return
  end
  
  -- Process files to understand display order
  local processed = folding.process_git_files(files, config.git_status_count)
  local display_files = {}
  
  -- Add visible files first
  for _, data in ipairs(processed.visible) do
    table.insert(display_files, data)
  end
  
  -- Add hidden files (they are in the buffer even if folded)
  for _, data in ipairs(processed.hidden) do
    table.insert(display_files, data)
  end
  
  -- Apply highlighting to displayed files in correct order
  for display_index, data in ipairs(display_files) do
    local line_num = git_status_start + 1 + display_index -- +1 for empty line after "Git Status:"
    -- Hard-cap at the git_status section's end_line. Without this, a
    -- collapse_untracked summary line (which sits in the buffer but is not
    -- part of display_files) shifts the index, and the loop's tail
    -- overshoots into Recent Commits — painting `A` from "HEAD" as a status
    -- char (red) and `-` from "->" as a deletion marker.
    if section_end and line_num > section_end then break end
    local line_content = lines[line_num]

    if line_content then
      -- Find the status characters in the line
      local status_start = line_content:find('[MADRCU?]')
      if status_start then
        -- Special case for MM (staged + unstaged): first M green, second M red
        if data.item.status == 'MM' then
          vim.api.nvim_buf_set_extmark(buf, git_ns, line_num - 1, status_start - 1, {
            end_col = status_start,
            hl_group = 'DiagnosticOk',
          })
          vim.api.nvim_buf_set_extmark(buf, git_ns, line_num - 1, status_start, {
            end_col = status_start + 1,
            hl_group = 'DiagnosticError',
          })
        else
          local color_group = git_status.get_status_color(data.item.status)
          vim.api.nvim_buf_set_extmark(buf, git_ns, line_num - 1, status_start - 1, {
            end_col = status_start + 1,
            hl_group = color_group,
          })
        end
      end

      -- Highlight diff stats: scan for contiguous runs of + and - instead of
      -- iterating per character.  Drops API calls from O(line_length) to
      -- O(runs) — typically 2-4 per file vs 50+ for a wide diff bar.
      local pos = 1
      while pos <= #line_content do
        local s, e = line_content:find('%++', pos)
        if not s then break end
        vim.api.nvim_buf_set_extmark(buf, git_ns, line_num - 1, s - 1, {
          end_col = e,
          hl_group = 'DiagnosticOk',
        })
        pos = e + 1
      end
      pos = 1
      while pos <= #line_content do
        local s, e = line_content:find('%-+', pos)
        if not s then break end
        vim.api.nvim_buf_set_extmark(buf, git_ns, line_num - 1, s - 1, {
          end_col = e,
          hl_group = 'DiagnosticError',
        })
        pos = e + 1
      end
    end
  end
end

-- Linear issues highlighting
function M.apply_linear_highlighting(buf, lines, config)
  if not config.linear or not config.linear.enabled then
    return
  end
  
  local linear_ns = vim.api.nvim_create_namespace('nexus_linear')
  local linear_component = require('nexus.render.components.linear')
  local linear_state = require('nexus.state.linear')
  
  -- Get current issues for reference
  local issues = linear_state.get_issues()
  if not issues then
    return
  end
  
  -- Find Linear Issues section
  local linear_section_start = nil
  for i, line in ipairs(lines) do
    if line:match('Linear Issues:') then
      linear_section_start = i
      break
    end
  end
  
  if not linear_section_start then
    return
  end
  
  -- Apply highlighting to each issue line
  for i = linear_section_start + 2, #lines do -- +2 to skip header and empty line
    local line_content = lines[i]
    if not line_content or line_content == "" then
      break -- End of section
    end
    
    local is_issue, identifier = linear_component.is_linear_issue_line(line_content)
    if is_issue and identifier then
      local issue = linear_component.get_issue_from_line(line_content, issues)
      if issue then
        -- Highlight state icon at the beginning
        local state_icon_end = line_content:find('%s', 3) or 4 -- Find first space after icons
        if state_icon_end > 3 then
          local state_color = linear_component.get_state_color(issue.state)
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, 2, {
            end_col = state_icon_end - 1,
            hl_group = state_color,
          })
        end

        -- Highlight priority icon if present (after state, before identifier)
        if issue.priority and type(issue.priority) == "number" and issue.priority >= 2 then
          local priority_start = line_content:find('[🟢🟡🟠🔴]', state_icon_end or 4)
          if priority_start then
            local priority_color = linear_component.get_priority_color(issue.priority)
            vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, priority_start - 1, {
              end_col = priority_start,
              hl_group = priority_color,
            })
          end
        end

        -- Highlight identifier [LIN-123]
        local id_start, id_end = line_content:find('%[' .. vim.pesc(identifier) .. '%]')
        if id_start then
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, id_start - 1, {
            end_col = id_end,
            hl_group = 'Number',
          })
        end

        -- Highlight assignee (@username)
        local assignee_start, assignee_end = line_content:find('@[^)]+')
        if assignee_start then
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, assignee_start - 1, {
            end_col = assignee_end,
            hl_group = 'Function',
          })
        end

        -- Highlight estimate (Np)
        local estimate_start, estimate_end = line_content:find('%(%d+p%)')
        if estimate_start then
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, estimate_start - 1, {
            end_col = estimate_end,
            hl_group = 'String',
          })
        end

        -- Highlight cycle [CycleName]
        local cycle_start, cycle_end = line_content:find('%[[^]]+%]', (id_end or 0) + 1)
        if cycle_start then
          vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, cycle_start - 1, {
            end_col = cycle_end,
            hl_group = 'Type',
          })
        end
      end
    elseif line_content:match("Loading issues") then
      -- Highlight loading message
      vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, 0, {
        end_col = #line_content,
        hl_group = 'DiagnosticInfo',
      })
    elseif line_content:match("No issues found") then
      -- Highlight no issues message
      vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, 0, {
        end_col = #line_content,
        hl_group = 'Comment',
      })
    elseif line_content:match("No API key found") or line_content:match("Invalid API key") then
      -- Highlight API key setup messages as actionable
      vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, 0, {
        end_col = #line_content,
        hl_group = 'DiagnosticWarn',
      })
      -- Highlight the action hint
      local enter_start, enter_end = line_content:find("<Enter>")
      if enter_start then
        vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, enter_start - 1, {
          end_col = enter_end,
          hl_group = 'String',
        })
      end
    elseif line_content:match("❌") then
      -- Highlight other error messages
      vim.api.nvim_buf_set_extmark(buf, linear_ns, i - 1, 0, {
        end_col = #line_content,
        hl_group = 'DiagnosticError',
      })
    end
  end
end

-- Keyboard shortcuts highlighting
function M.apply_shortcuts_highlighting(buf, lines, config, section_ranges)
  local config_module = require('nexus.config')
  if not config_module.is_section_enabled("keyboard_shortcuts") or not section_ranges or not section_ranges.keyboard_shortcuts then
    return
  end
  
  local shortcuts_ns = vim.api.nvim_create_namespace('nexus_shortcuts')
  local shortcuts_section = section_ranges.keyboard_shortcuts
  
  -- Highlight entire keyboard shortcuts section
  for i = shortcuts_section.start_line, shortcuts_section.end_line do
    local line_content = lines[i]
    if line_content and #line_content > 0 then -- Only highlight non-empty lines
      vim.api.nvim_buf_set_extmark(buf, shortcuts_ns, i - 1, 0, {
        end_col = #line_content,
        hl_group = 'Comment',
      })
    end
  end
end

-- Todo highlighting
function M.apply_todo_highlighting(buf, lines, config)
  local config_module = require('nexus.config')
  if not config_module.is_section_enabled("todos") then
    return
  end

  local todo_component = require('nexus.render.components.todo')

  -- Find Todo section
  for i, line in ipairs(lines) do
    if line:match('Todo:%s*$') then
      todo_component.apply_todo_highlighting(buf, i)
      break
    end
  end
end

-- Beads issues highlighting
function M.apply_beads_highlighting(buf, lines, config)
  local config_module = require('nexus.config')
  if not config_module.is_section_enabled("beads_issues") then
    return
  end

  local beads_component = require('nexus.render.components.beads')

  -- Find Beads Issues section
  local beads_section_start = nil
  for i, line in ipairs(lines) do
    if line:match('Beads Issues:') then
      beads_section_start = i
      break
    end
  end

  if beads_section_start then
    beads_component.apply_beads_highlighting(buf, beads_section_start)
  end
end

return M
