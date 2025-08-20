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
      
      table.insert(commits, {
        hash = hash,
        message = message,
        decoration = decoration
      })
    end
  end
  
  return commits
end

return M