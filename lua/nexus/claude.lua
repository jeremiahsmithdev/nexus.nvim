local M = {}

local git_commits = require('nexus.git.commits')

function M.get_claude_conversations(config)
  local git_root = require('nexus.git.root').get()
  if not git_root then
    return {}
  end
  
  local current_branch = git_commits.get_current_branch()
  if not current_branch or current_branch == '' then
    return {}
  end
  
  
  -- Find matching project folder in ~/.claude/projects
  local claude_projects = vim.fn.expand('~/.claude/projects')
  
  -- Claude encodes paths with dashes instead of slashes
  local encoded_path = string.gsub(git_root, '/', '-')
  
  local project_path = claude_projects .. '/' .. encoded_path
  
  if vim.fn.isdirectory(project_path) == 0 then
    -- Fallback: use current working directory
    local cwd = vim.fn.getcwd()
    local encoded_cwd = string.gsub(cwd, '/', '-')
    project_path = claude_projects .. '/' .. encoded_cwd
    
    if vim.fn.isdirectory(project_path) == 0 then
      return {}
    end
  end
  
  -- Get conversation files
  local conv_files = vim.fn.globpath(project_path, '*.jsonl', false, true)
  local conversations = {}
  
  for _, file in ipairs(conv_files) do
    local f = io.open(file, 'r')
    if f then
      local first_line = f:read('*l')
      f:close()
      
      if first_line then
        local ok, data = pcall(vim.json.decode, first_line)
        if ok and data.cwd == git_root and data.gitBranch == current_branch then
          -- Extract a better summary - skip system messages and get first meaningful content
          local content = "No summary"
          if data.message and data.message.content then
            -- Skip messages that start with "Caveat:" or contain command metadata
            local msg_content = data.message.content
            if not msg_content:match("^Caveat:") and not msg_content:match("<command%-name>") then
              content = msg_content
            end
          end
          -- Count total messages in file
          local msg_count = 0
          for line in io.lines(file) do
            if line:match('"type":"user"') or line:match('"type":"assistant"') then
              msg_count = msg_count + 1
            end
          end
          
          -- Get file stats and calculate relative time
          local stat = vim.loop.fs_stat(file)
          local now = os.time()
          local modified_diff = now - stat.mtime.sec
          local created_diff = now - stat.birthtime.sec
          
          local function time_ago(seconds)
            local days = math.floor(seconds / 86400)
            if days > 0 then
              return days .. ' day' .. (days == 1 and '' or 's') .. ' ago'
            else
              local hours = math.floor(seconds / 3600)
              if hours > 0 then
                return hours .. ' hour' .. (hours == 1 and '' or 's') .. ' ago'
              else
                return 'today'
              end
            end
          end
          
          table.insert(conversations, {
            content = data.message and data.message.content or 'No summary',
            modified = time_ago(modified_diff),
            created = time_ago(created_diff),
            messages = msg_count,
            timestamp = data.timestamp or '',
            session_id = data.sessionId
          })
        end
      end
    end
  end
  
  -- Sort by timestamp (most recent first)
  table.sort(conversations, function(a, b)
    return a.timestamp > b.timestamp
  end)
  
  return conversations
end

return M