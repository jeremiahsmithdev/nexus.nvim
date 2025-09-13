local M = {}

function M.parse_git_status()
  local handle = io.popen('git status --porcelain=v1 2>/dev/null')
  if not handle then
    return {}
  end
  
  local result = handle:read('*a')
  handle:close()
  
  if result == '' then
    return {}
  end
  
  local files = {}
  for line in result:gmatch('[^\r\n]+') do
    local status = line:sub(1, 2)
    local file = line:sub(4)
    table.insert(files, {
      status = status,
      file = file
    })
  end
  
  return files
end

function M.get_diff_stats(file, status)
  local handle
  if status:sub(1, 1) == '?' then
    return 0, 0
  elseif status:sub(1, 1) ~= ' ' then
    handle = io.popen('git diff --numstat --cached HEAD -- "' .. file .. '" 2>/dev/null')
  else
    handle = io.popen('git diff --numstat HEAD -- "' .. file .. '" 2>/dev/null')
  end
  
  if not handle then
    return 0, 0
  end
  
  local result = handle:read('*a')
  handle:close()
  
  if result == '' then
    return 0, 0
  end
  
  local added, deleted = result:match('(%d+)%s+(%d+)')
  return tonumber(added) or 0, tonumber(deleted) or 0
end

function M.format_status_icon(status)
  local first, second = status:sub(1, 1), status:sub(2, 2)
  
  if first == '?' and second == '?' then
    return '??'
  elseif first == 'M' and second == 'M' then
    return 'MM'  -- Show both M's when staged AND unstaged
  elseif first == 'M' or second == 'M' then
    return 'M '
  elseif first == 'A' or second == 'A' then
    return 'A '
  elseif first == 'D' or second == 'D' then
    return 'D '
  elseif first == 'R' or second == 'R' then
    return 'R '
  elseif first == 'C' or second == 'C' then
    return 'C '
  elseif first == 'U' or second == 'U' then
    return 'U '
  else
    return first .. second
  end
end

function M.create_diff_stat(added, deleted, max_width)
  if added == 0 and deleted == 0 then
    return ""
  end
  
  local total = added + deleted
  if total == 0 then
    return ""
  end
  
  local scale = math.min(max_width, total) / total
  local add_chars = math.floor(added * scale)
  local del_chars = math.floor(deleted * scale)
  
  -- Optimized: Use table concatenation instead of string concatenation
  local bar_parts = {}
  if add_chars > 0 then
    bar_parts[#bar_parts + 1] = string.rep("+", add_chars)
  end
  if del_chars > 0 then
    bar_parts[#bar_parts + 1] = string.rep("-", del_chars)
  end
  local bar = table.concat(bar_parts)
  local count_str = ""
  if added > 0 and deleted > 0 then
    count_str = string.format("+%-3d -%d", added, deleted)
  elseif added > 0 then
    count_str = string.format("+%d", added)
  elseif deleted > 0 then
    count_str = string.format("-%d", deleted)
  end
  
  return string.format(" %-10s %s", count_str, bar)
end

function M.get_status_color(status)
  local first = status:sub(1, 1)
  if first == '?' then
    return 'DiagnosticError'  -- red for untracked
  elseif first ~= ' ' then
    return 'DiagnosticOk'     -- green for staged
  else
    return 'DiagnosticError'  -- red for unstaged
  end
end

return M
