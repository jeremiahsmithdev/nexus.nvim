local M = {}

function M.get_current_branch()
  local handle = io.popen('git branch --show-current 2>/dev/null')
  if not handle then
    return nil
  end
  local result = handle:read('*a')
  handle:close()
  return result:gsub('%s+$', '') -- trim whitespace
end

function M.get_git_log(config)
  -- Get commits with decorations and notes in a single subprocess.
  -- --notes appends note lines (indented 4 spaces) after each commit, so we
  -- collect them inline without extra per-commit 'git notes show' calls.
  local count = config.recent_commits_count
  if not count or count < 1 then
    count = 3
  end
  local handle = io.popen('git log --oneline --decorate -' .. count .. ' --notes 2>/dev/null')
  if not handle then
    return {}
  end

  local result = handle:read('*a')
  handle:close()

  if result == '' then
    return {}
  end

  local commits = {}
  local current_commit = nil
  local current_notes = {}

  local function finalize_commit()
    if not current_commit then return end
    local review_status = "unreviewed"
    if config.show_commit_review and #current_notes > 0 then
      review_status = M.parse_review_status_from_notes(table.concat(current_notes, '\n'))
    end
    current_commit.review_status = review_status
    current_commit.is_reviewed = review_status == "reviewed"
    table.insert(commits, current_commit)
    current_commit = nil
    current_notes = {}
  end

  for line in result:gmatch('[^\r\n]+') do
    if line:match('^    ') then
      -- Notes line: indented 4 spaces by git log --notes
      if current_commit then
        table.insert(current_notes, line:sub(5))
      end
    elseif line:match('^[a-f0-9]') then
      -- Commit header line
      finalize_commit()
      local hash, rest = line:match('([a-f0-9]+) (.+)')
      if hash and rest then
        local decoration, message = rest:match('%(([^)]+)%) (.+)')
        if not decoration then
          message = rest
          decoration = nil
        end
        current_commit = { hash = hash, message = message, decoration = decoration }
      end
    end
    -- Empty separator lines (between notes and next commit) are skipped implicitly
  end
  finalize_commit()

  return commits
end

-- Parse review status from notes text (shared logic for both sync and async paths).
function M.parse_review_status_from_notes(notes_text)
  local lower = notes_text:lower()
  if lower:match('needs attention') then
    return "needs_attention"
  elseif lower:match('reviewed') then
    return "reviewed"
  else
    return "unreviewed"
  end
end

function M.get_commit_review_status(hash)
  -- Check if commit has review notes and determine status
  local handle = io.popen('git notes show ' .. hash .. ' 2>/dev/null')
  if not handle then
    return "unreviewed"
  end
  
  local notes = handle:read('*a')
  handle:close()
  
  if notes == '' then
    return "unreviewed"
  end
  
  local notes_lower = notes:lower()
  if notes_lower:match('needs attention') then
    return "needs_attention"
  elseif notes_lower:match('reviewed') then
    return "reviewed"
  else
    return "unreviewed"
  end
end

-- Legacy function for backward compatibility
function M.is_commit_reviewed(hash)
  return M.get_commit_review_status(hash) == "reviewed"
end

function M.mark_commit_reviewed(hash)
  -- Add review note to commit
  local username = os.getenv('USER') or os.getenv('USERNAME') or 'user'
  local review_message = string.format('Reviewed by %s on %s', username, os.date())
  
  local handle = io.popen(string.format('git notes add -m "%s" %s -f 2>/dev/null', review_message, hash))
  if not handle then
    return false
  end
  
  local result = handle:read('*a')
  local success = handle:close()
  
  return success
end

function M.mark_commit_needs_attention(hash)
  -- Add needs attention note to commit
  local username = os.getenv('USER') or os.getenv('USERNAME') or 'user'
  local attention_message = string.format('Needs attention - flagged by %s on %s', username, os.date())
  
  local handle = io.popen(string.format('git notes add -m "%s" %s -f 2>/dev/null', attention_message, hash))
  if not handle then
    return false
  end
  
  local result = handle:read('*a')
  local success = handle:close()
  
  return success
end

function M.mark_commit_unreviewed(hash)
  -- Remove review note from commit
  local handle = io.popen(string.format('git notes remove %s 2>/dev/null', hash))
  if not handle then
    return false
  end
  
  local result = handle:read('*a')
  local success = handle:close()
  
  return success
end

return M