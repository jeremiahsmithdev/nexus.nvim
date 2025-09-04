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
      local is_reviewed = false
      if config.show_commit_review then
        is_reviewed = M.is_commit_reviewed(hash)
      end
      
      table.insert(commits, {
        hash = hash,
        message = message,
        decoration = decoration,
        is_reviewed = is_reviewed
      })
    end
  end
  
  return commits
end

function M.is_commit_reviewed(hash)
  -- Check if commit has a review note containing "Reviewed"
  local handle = io.popen('git notes show ' .. hash .. ' 2>/dev/null')
  if not handle then
    return false
  end
  
  local notes = handle:read('*a')
  handle:close()
  
  -- Check if notes contain "Reviewed" (case-insensitive)
  return notes:lower():match('reviewed') ~= nil
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