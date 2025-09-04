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
  -- Get commits with decorations (branch/tag info)
  local count = config.recent_commits_count or 3
  local handle = io.popen('git log --oneline --decorate -' .. count .. ' 2>/dev/null')
  if not handle then
    return {}
  end
  
  local result = handle:read('*a')
  handle:close()
  
  if result == '' then
    return {}
  end
  
  local commits = {}
  for line in result:gmatch('[^\r\n]+') do
    local hash, rest = line:match('([a-f0-9]+) (.+)')
    if hash and rest then
      -- Check if this has decoration (branch/tag info)
      local decoration, message = rest:match('%(([^)]+)%) (.+)')
      if not decoration then
        message = rest
        decoration = nil
      end
      
      -- Check review status if enabled
      local review_status = "unreviewed"
      if config.show_commit_review then
        review_status = M.get_commit_review_status(hash)
      end
      
      table.insert(commits, {
        hash = hash,
        message = message,
        decoration = decoration,
        review_status = review_status,
        is_reviewed = review_status == "reviewed" -- For backward compatibility
      })
    end
  end
  
  return commits
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