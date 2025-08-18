local M = {}

-- Default configuration
local default_config = {
  show_claude_conversations = false, -- Disabled by default
  show_dashboard_buttons = true,     -- Show dashboard-style buttons
  show_recent_commits = true,        -- Show git commits section
  recent_commits_count = 3,          -- Number of recent commits to show
  show_git_status = true             -- Show git status section
}

local config = vim.deepcopy(default_config)

-- Setup function to allow user configuration
function M.setup(user_config)
  config = vim.tbl_deep_extend('force', default_config, user_config or {})
end

-- Send /resume command to Claude via tmux (similar to diffusion.nvim approach)
function send_resume_to_claude(session_id)
  -- Check if we're in tmux
  if not vim.env.TMUX then
    print("Not in tmux environment")
    return false
  end
  
  -- Get current tmux context
  local current_session = vim.fn.system("tmux display-message -p '#S'"):gsub("\n", "")
  local current_window = vim.fn.system("tmux display-message -p '#I'"):gsub("\n", "")
  local current_pane = vim.fn.system("tmux display-message -p '#P'"):gsub("\n", "")
  
  -- Find Claude process in same window first
  local claude_pane = find_claude_in_window(current_session, current_window)
  if claude_pane then
    return send_resume_to_pane(current_session, current_window, claude_pane, session_id)
  end
  
  print("No Claude processes found in current tmux window")
  return false
end

-- Find Claude process in tmux window
function find_claude_in_window(session, window)
  local cmd = string.format("tmux list-panes -t %s:%s -F '#{pane_index} #{pane_current_command}' 2>/dev/null", session, window)
  local output = vim.fn.system(cmd)
  
  for line in output:gmatch("[^\r\n]+") do
    local pane_index, command = line:match("(%d+) (%S+)")
    if pane_index and command and (command:match("claude") or command:match("node")) then
      return pane_index
    end
  end
  
  return nil
end

-- Send /resume command to specific tmux pane
function send_resume_to_pane(session, window, pane, session_id)
  local target = session .. ":" .. window .. "." .. pane
  
  -- Clear any existing input with Ctrl-C
  local clear_cmd = string.format("tmux send-keys -t %s C-c", target)
  vim.fn.system(clear_cmd)
  vim.wait(50)
  
  -- Send /resume command with session ID
  local resume_cmd = string.format("tmux send-keys -t %s '/resume %s'", target, session_id)
  vim.fn.system(resume_cmd)
  vim.wait(100)
  
  -- Send Enter to submit command
  local enter_cmd = string.format("tmux send-keys -t %s Enter", target)
  vim.fn.system(enter_cmd)
  
  print("Sent /resume " .. session_id .. " to Claude")
  return true
end

local function create_gboard_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'filetype', 'gboard')
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  return buf
end

local function get_neovim_logo()
  return {
    [[                                  __]],
    [[     ___     ___    ___   __  __ /\_\    ___ ___]],
    [[    / _ `\  / __`\ / __`\/\ \/\ \\/\ \  / __` __`\]],
    [[   /\ \/\ \/\  __//\ \_\ \ \ \_/ |\ \ \/\ \/\ \/\ \]],
    [[   \ \_\ \_\ \____\ \____/\ \___/  \ \_\ \_\ \_\ \_\]],
    [[    \/_/\/_/\/____/\/___/  \/__/    \/_/\/_/\/_/\/_/]],
    ""
  }
end

local function longest_line(lines)
  local longest = 0
  for _, line in ipairs(lines) do
    longest = math.max(longest, #line)
  end
  return longest
end

local function center_lines(lines, width)
  -- Use alpha-nvim's centering approach
  local longest = longest_line(lines)
  local left = math.floor((width - longest) / 2)
  left = math.max(0, left)
  local padding = string.rep(" ", left)
  
  local centered = {}
  for _, line in ipairs(lines) do
    table.insert(centered, padding .. line)
  end
  return centered
end

local function get_dashboard_buttons()
  if not config.show_dashboard_buttons then
    return {}
  end
  
  return {
    "",
    "    󰈞  Find file                   SPC f f",
    "    󰈢  Recently opened files       SPC f h", 
    "    󰈬  Find word                   SPC f g",
    "    󰈙  New file                    SPC f n",
    "    󰏓  Bookmarks                   SPC b m",
    "    󰗊  Restore session             SPC s s",
    ""
  }
end

local function get_current_branch()
  local handle = io.popen('git branch --show-current 2>/dev/null')
  if not handle then
    return nil
  end
  local result = handle:read('*a')
  handle:close()
  return result:gsub('%s+$', '') -- trim whitespace
end

local function get_git_log()
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

local function get_claude_conversations()
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')[1]
  if not git_root then
    return {}
  end
  
  local current_branch = get_current_branch()
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

local function parse_git_status()
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

local function get_diff_stats(file, status)
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

local function format_status_icon(status)
  local first, second = status:sub(1, 1), status:sub(2, 2)
  
  if first == '?' and second == '?' then
    return '??'
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

local function create_diff_stat(added, deleted, max_width)
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
  
  local bar = string.rep("+", add_chars) .. string.rep("-", del_chars)
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

local function get_status_color(status)
  local first = status:sub(1, 1)
  if first == '?' then
    return 'DiagnosticError'  -- red for untracked
  elseif first ~= ' ' then
    return 'DiagnosticOk'     -- green for staged
  else
    return 'DiagnosticError'  -- red for unstaged
  end
end

local function render_git_status(buf)
  local files = parse_git_status()
  
  -- Get the actual display width (tmux pane width if in tmux, otherwise vim width)
  local width = vim.fn.winwidth(0) -- default to vim width
  
  if vim.env.TMUX then
    local pane_width = vim.fn.system("tmux display-message -p '#{pane_width}'"):gsub('\n', '')
    local tmux_width = tonumber(pane_width)
    if tmux_width then
      width = tmux_width
    end
  end
  
  -- Start with centered Neovim logo
  local logo_lines = get_neovim_logo()
  local lines = center_lines(logo_lines, width)
  
  -- Add dashboard buttons if enabled
  local button_lines = get_dashboard_buttons()
  if #button_lines > 0 then
    local centered_buttons = center_lines(button_lines, width)
    for _, line in ipairs(centered_buttons) do
      table.insert(lines, line)
    end
  end
  
  -- Add recent commits section
  if config.show_claude_conversations then
    -- Claude conversations disabled for now
    local conversations = get_claude_conversations()
    if #conversations > 0 then
      table.insert(lines, "Recent Claude Conversations:")
      table.insert(lines, "")
      
      -- Add column headers
      table.insert(lines, "    Modified     Created      Messages  Summary")
      
      local max_conversations = config.recent_commits_count or 3
      for i = 1, math.min(max_conversations, #conversations) do
        local conv = conversations[i]
        local summary = conv.content:sub(1, 50) -- Truncate long summaries
        if #conv.content > 50 then
          summary = summary .. "..."
        end
        
        local line = string.format(" %d. %-12s %-12s %8d  %s", 
          i, conv.modified, conv.created, conv.messages, summary)
        table.insert(lines, line)
      end
      table.insert(lines, "")
    end
  elseif config.show_recent_commits then
    -- Show recent git commits
    local commits = get_git_log()
    if #commits > 0 then
      table.insert(lines, "Recent Commits:")
      table.insert(lines, "")
      
      for i, commit in ipairs(commits) do
        local line
        if commit.decoration then
          line = string.format("  %s (%s) %s", commit.hash, commit.decoration, commit.message)
        else
          line = string.format("  %s %s", commit.hash, commit.message)
        end
        table.insert(lines, line)
      end
      table.insert(lines, "")
    end
  end
  
  if config.show_git_status then
    if #files == 0 then
      table.insert(lines, "No changes detected")
      table.insert(lines, "")
    else
      table.insert(lines, "Git Status:")
      table.insert(lines, "")
      
      -- Calculate max filename width for alignment
      local max_filename_width = 0
      local file_data = {}
      for i, item in ipairs(files) do
        local added, deleted = get_diff_stats(item.file, item.status)
        local status_icon = format_status_icon(item.status)
        local full_name = status_icon .. " " .. item.file
        max_filename_width = math.max(max_filename_width, #full_name)
        table.insert(file_data, {
          item = item,
          added = added,
          deleted = deleted,
          status_icon = status_icon,
          full_name = full_name
        })
      end
      
      for i, data in ipairs(file_data) do
        local padding = string.rep(" ", max_filename_width - #data.full_name)
        local diff_stat = create_diff_stat(data.added, data.deleted, 40)
        
        local line = string.format("  %s%s%s", data.full_name, padding, diff_stat)
        table.insert(lines, line)
      end
    end
  end
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  
  -- Add syntax highlighting with isolated sections
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)
  
  local line_offset = 0
  
  -- 1. Neovim logo section
  local logo_ns = vim.api.nvim_create_namespace('gboard_logo')
  local logo_lines = get_neovim_logo()
  for i = 1, #logo_lines do
    if i <= 6 then -- Only highlight the actual logo lines, not the empty line
      vim.api.nvim_buf_add_highlight(buf, logo_ns, 'Type', line_offset + i - 1, 0, -1)
    end
  end
  line_offset = line_offset + #logo_lines
  
  -- 2. Dashboard buttons section - ALL GRAY
  if config.show_dashboard_buttons then
    local button_ns = vim.api.nvim_create_namespace('gboard_buttons')
    local button_lines = get_dashboard_buttons()
    local button_start_line = #logo_lines  -- Start right after logo (0-indexed)
    
    for i, button_line in ipairs(button_lines) do
      if button_line ~= "" then -- Skip empty lines
        local line_num = button_start_line + i - 1
        
        -- Make entire line gray
        vim.api.nvim_buf_add_highlight(buf, button_ns, 'Comment', line_num, 0, -1)
      end
    end
    line_offset = line_offset + #button_lines
  end
  
  -- 3. Commits section
  if not config.show_claude_conversations then
    local commits_ns = vim.api.nvim_create_namespace('gboard_commits')
    local commits_start_line = nil
    for i, line in ipairs(lines) do
      if line == "Recent Commits:" then
        commits_start_line = i + 1 -- +1 for empty line after "Recent Commits:"
        break
      end
    end
    
    if commits_start_line then
      local commits = get_git_log()
      for i, commit in ipairs(commits) do
        local line_num = commits_start_line + i - 1
        local line_content = lines[line_num + 1]
        
        if line_content then
          -- Highlight commit hash in yellow
          local hash_end = line_content:find(' ', 3) -- Find space after hash
          if hash_end then
            vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Number', line_num, 2, hash_end - 1)
          end
          
          -- Highlight decoration (HEAD, branches) in different colors
          if commit.decoration then
            local decoration_start = line_content:find('(', 1, true)
            local decoration_end = line_content:find(')', 1, true)
            if decoration_start and decoration_end then
              -- Highlight the parentheses in default color, content inside in cyan
              vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Special', line_num, decoration_start - 1, decoration_start)
              vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Special', line_num, decoration_end - 1, decoration_end)
              
              -- Highlight HEAD in bold/bright
              local decoration_content = commit.decoration
              if decoration_content:match('HEAD') then
                local head_start = line_content:find('HEAD', decoration_start)
                if head_start then
                  vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Title', line_num, head_start - 1, head_start + 3)
                end
              end
              
              -- Highlight branch names in cyan
              local branch_parts = vim.split(decoration_content, ', ')
              for _, part in ipairs(branch_parts) do
                if not part:match('HEAD') and not part:match('tag:') then
                  local branch_start = line_content:find(part, decoration_start, true)
                  if branch_start then
                    vim.api.nvim_buf_add_highlight(buf, commits_ns, 'Function', line_num, branch_start - 1, branch_start + #part - 1)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  
  -- 4. Git Status section
  local git_ns = vim.api.nvim_create_namespace('gboard_git_status')
  local git_status_line = nil
  for i, line in ipairs(lines) do
    if line == "Git Status:" then
      git_status_line = i
      break
    end
  end
  
  if git_status_line then
    for i, item in ipairs(files) do
      local line_num = git_status_line + 1 + i - 1 -- +1 for empty line after "Git Status:"
      local line_content = lines[line_num + 1]
      
      -- Highlight status (beginning of line)
      local status_end = 5  -- "  XX "
      local color_group = get_status_color(item.status)
      vim.api.nvim_buf_add_highlight(buf, git_ns, color_group, line_num, 0, status_end)
      
      -- Highlight + and - chars (and their numbers)
      for i = 1, #line_content do
        local char = line_content:sub(i, i)
        if char == '+' then
          vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticOk', line_num, i - 1, i)
        elseif char == '-' then
          vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticError', line_num, i - 1, i)
        elseif char:match('%d') then
          -- Color numbers based on preceding + or -
          local j = i - 1
          while j > 0 and line_content:sub(j, j):match('%d') do
            j = j - 1
          end
          if j > 0 then
            local sign = line_content:sub(j, j)
            if sign == '+' then
              vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticOk', line_num, i - 1, i)
            elseif sign == '-' then
              vim.api.nvim_buf_add_highlight(buf, git_ns, 'DiagnosticError', line_num, i - 1, i)
            end
          end
        end
      end
    end
  end
  
  
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  
  return files
end

local function setup_keymaps(buf, files)
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    noremap = true,
    silent = true,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local line_num = cursor[1]
      
      -- Get all lines in the buffer
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local current_line = lines[line_num]
      
      -- Check if it's a dashboard button line
      if config.show_dashboard_buttons and current_line and current_line:match("Find file") then
        vim.cmd('Telescope find_files')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Recently opened files") then
        vim.cmd('Telescope oldfiles')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Find word") then
        vim.cmd('Telescope live_grep')
      elseif config.show_dashboard_buttons and current_line and current_line:match("New file") then
        vim.cmd('enew')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Bookmarks") then
        vim.cmd('Telescope marks')
      elseif config.show_dashboard_buttons and current_line and current_line:match("Restore session") then
        -- Basic session restore - could be enhanced with session manager
        if vim.fn.filereadable('Session.vim') == 1 then
          vim.cmd('source Session.vim')
        else
          print('No session file found')
        end
      -- Check if it's a git status line
      elseif current_line and current_line:match("^  [MADRCU?][MADRCU?]? ") then
        -- This is a git status line - extract filename and open file
        local filename = current_line:match("^  [MADRCU?][MADRCU?]? (.-)%s+%+") or 
                        current_line:match("^  [MADRCU?][MADRCU?]? (.-)%s+%-") or
                        current_line:match("^  [MADRCU?][MADRCU?]? (.+)$")
        if filename then
          filename = filename:gsub("%s+$", "")
        end
        
        if filename then
          filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
          
          local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
          if git_root then
            local full_path = git_root .. '/' .. filename
            vim.cmd('edit ' .. vim.fn.fnameescape(full_path))
            vim.cmd('set number')
            vim.cmd('set signcolumn=yes')
          else
            vim.cmd('edit ' .. vim.fn.fnameescape(filename))
            vim.cmd('set number')
            vim.cmd('set signcolumn=yes')
          end
        end
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Count non-empty, listed buffers
      local listed_bufs = 0
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_option(b, 'buflisted') then
          local name = vim.api.nvim_buf_get_name(b)
          if name ~= '' or vim.api.nvim_buf_get_option(b, 'modified') then
            listed_bufs = listed_bufs + 1
          end
        end
      end
      
      if listed_bufs <= 1 then
        vim.cmd('qa!')
      else
        vim.cmd('q')
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Count non-empty, listed buffers
      local listed_bufs = 0
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_option(b, 'buflisted') then
          local name = vim.api.nvim_buf_get_name(b)
          if name ~= '' or vim.api.nvim_buf_get_option(b, 'modified') then
            listed_bufs = listed_bufs + 1
          end
        end
      end
      
      if listed_bufs <= 1 then
        vim.cmd('qa!')
      else
        vim.cmd('q')
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'r', '', {
    noremap = true,
    silent = true,
    callback = function()
      render_git_status(buf)
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'a', '', {
    noremap = true,
    silent = true,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local line_num = cursor[1]
      
      -- Get all lines in the buffer
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local current_line = lines[line_num]
      
      -- Check if it's a git status line
      if current_line and current_line:match("^  [MADRCU?][MADRCU?]? ") then
        local filename = current_line:match("^  [MADRCU?][MADRCU?]? (.-)%s+%+") or 
                        current_line:match("^  [MADRCU?][MADRCU?]? (.-)%s+%-") or
                        current_line:match("^  [MADRCU?][MADRCU?]? (.+)$")
        if filename then
          filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
          
          -- Git add the file
          local result = vim.fn.system('git add "' .. filename .. '"')
          if vim.v.shell_error == 0 then
            print('Added: ' .. filename)
            render_git_status(buf) -- Refresh the display
          else
            print('Failed to add: ' .. filename .. ' - ' .. result)
          end
        end
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'u', '', {
    noremap = true,
    silent = true,
    callback = function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local line_num = cursor[1]
      
      -- Get all lines in the buffer
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local current_line = lines[line_num]
      
      -- Check if it's a git status line
      if current_line and current_line:match("^  [MADRCU?][MADRCU?]? ") then
        local filename = current_line:match("^  [MADRCU?][MADRCU?]? (.-)%s+%+") or 
                        current_line:match("^  [MADRCU?][MADRCU?]? (.-)%s+%-") or
                        current_line:match("^  [MADRCU?][MADRCU?]? (.+)$")
        if filename then
          filename = filename:gsub("^%s+", ""):gsub("%s+$", "")
          
          -- Git unstage the file
          local result = vim.fn.system('git reset HEAD "' .. filename .. '"')
          if vim.v.shell_error == 0 then
            print('Unstaged: ' .. filename)
            render_git_status(buf) -- Refresh the display
          else
            print('Failed to unstage: ' .. filename .. ' - ' .. result)
          end
        end
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'c', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Create floating window for commit message
      local width = 60
      local height = 15
      local bufnr = vim.api.nvim_create_buf(false, true)
      
      -- Calculate position to center the window
      local win_width = vim.api.nvim_get_option('columns')
      local win_height = vim.api.nvim_get_option('lines')
      local row = math.ceil((win_height - height) / 2 - 1)
      local col = math.ceil((win_width - width) / 2)
      
      local opts = {
        style = "minimal",
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        border = "rounded",
        title = " Git Commit ",
        title_pos = "center"
      }
      
      local win = vim.api.nvim_open_win(bufnr, true, opts)
      
      -- Set buffer options
      vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
      vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
      vim.api.nvim_buf_set_option(bufnr, 'filetype', 'gitcommit')
      
      -- Disable completions
      vim.api.nvim_buf_set_option(bufnr, 'omnifunc', '')
      vim.api.nvim_buf_set_option(bufnr, 'completefunc', '')
      
      -- Create empty lines in buffer to have lines for extmarks
      local empty_lines = {}
      for i = 1, height do
        table.insert(empty_lines, "")
      end
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, empty_lines)
      
      -- Add shortcuts as virtual text at the bottom, centered
      local ns_id = vim.api.nvim_create_namespace('gboard_commit')
      local help_text = "<Enter>/<C-s>: commit  <C-c>: cancel"
      local padding = math.floor((width - #help_text) / 2)
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, height - 1, 0, {
        virt_text = {{string.rep(" ", padding) .. help_text, "Comment"}},
        virt_text_pos = "overlay"
      })
      
      -- Position cursor at the beginning
      vim.api.nvim_win_set_cursor(win, {1, 0})
      
      -- Function to handle commit
      local function do_commit()
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local commit_msg = ""
        
        -- Get commit message (everything before comment lines)
        for _, line in ipairs(lines) do
          if not line:match("^#") and line ~= "" then
            commit_msg = commit_msg .. line .. "\n"
          end
        end
        
        commit_msg = commit_msg:gsub("^%s*", ""):gsub("%s*$", "") -- trim
        
        if commit_msg ~= "" then
          local result = vim.fn.system('git commit -m "' .. commit_msg .. '"')
          vim.api.nvim_win_close(win, true)
          
          -- Ensure we're in normal mode when returning to GBoard
          vim.cmd('stopinsert')
          
          if vim.v.shell_error == 0 then
            print('Committed: ' .. commit_msg:sub(1, 50) .. (commit_msg:len() > 50 and "..." or ""))
            render_git_status(buf) -- Refresh the display
          else
            print('Commit failed: ' .. result)
          end
        else
          print('No commit message provided')
        end
      end
      
      -- Set up keymaps for the commit window
      vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-c>', '<cmd>q<CR>', { noremap = true, silent = true })
      vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-c>', '<Esc><cmd>q<CR>', { noremap = true, silent = true })
      vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', '<cmd>q<CR>', { noremap = true, silent = true })
      
      vim.api.nvim_buf_set_keymap(bufnr, 'n', '<Esc>', '', {
        noremap = true,
        silent = true,
        callback = function()
          -- Check if buffer has any text content
          local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          local has_content = false
          for _, line in ipairs(lines) do
            if line:match("%S") then -- Check for non-whitespace
              has_content = true
              break
            end
          end
          
          if not has_content then
            vim.cmd('q')
          end
        end
      })
      
      vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', '', {
        noremap = true,
        silent = true,
        callback = do_commit
      })
      
      vim.api.nvim_buf_set_keymap(bufnr, 'n', '<C-s>', '', {
        noremap = true,
        silent = true,
        callback = do_commit
      })
      
      vim.api.nvim_buf_set_keymap(bufnr, 'i', '<C-s>', '<Esc>', {
        noremap = true,
        silent = true,
        callback = do_commit
      })
      
      vim.cmd('startinsert')
    end
  })
end

function M.open()
  -- If this is startup (only empty buffer exists), replace it
  local current_buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(current_buf)
  local buf_lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
  local is_empty_startup = buf_name == '' and #buf_lines == 1 and buf_lines[1] == ''
  
  local buf = create_gboard_buffer()
  vim.api.nvim_buf_set_name(buf, 'GBoard')
  
  if is_empty_startup then
    -- Replace the empty startup buffer
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_delete(current_buf, { force = true })
  else
    -- Open in new tab
    vim.cmd('tabnew')
    vim.api.nvim_win_set_buf(0, buf)
  end
  
  vim.api.nvim_win_set_option(0, 'number', false)
  vim.api.nvim_win_set_option(0, 'relativenumber', false)
  vim.api.nvim_win_set_option(0, 'signcolumn', 'no')
  vim.api.nvim_win_set_option(0, 'wrap', false)
  vim.api.nvim_win_set_option(0, 'cursorline', true)
  
  -- NOW the buffer is in the window, so we can get the correct window width
  local files = render_git_status(buf)
  setup_keymaps(buf, files)
  
  -- Position cursor after logo and buttons, before commits/git status
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local logo_lines = get_neovim_logo()
  local button_lines = get_dashboard_buttons()
  local cursor_line = math.min(#logo_lines + #button_lines + 3, #lines)
  if cursor_line > 0 and cursor_line <= #lines then
    vim.api.nvim_win_set_cursor(0, {cursor_line, 0})
  end
end

return M