-- Mock framework for Nexus.nvim tests
-- Provides mocks for external dependencies and system calls

local M = {}

-- Store original functions for restoration
M._original = {}

-- Mock state storage
M._state = {
  git_status = {},
  git_commits = {},
  git_repo = true,
  tmux_env = false,
  tmux_panes = {},
  filesystem = {},
  system_commands = {},
  mock_shell_error = 0
}

-- Mock helpers
local function create_mock_function(name, default_return)
  return function(...)
    local args = {...}
    if M._state.system_commands[name] then
      if type(M._state.system_commands[name]) == 'function' then
        return M._state.system_commands[name](unpack(args))
      else
        return M._state.system_commands[name]
      end
    end
    return default_return
  end
end

-- Git mocking functions
function M.mock_git_repo(is_repo)
  M._state.git_repo = is_repo
  
  -- Mock vim.fn.system for git commands
  if not M._original.vim_fn_system then
    M._original.vim_fn_system = vim.fn.system
  end
  
  -- Mock io.popen for git commands (used by parse_git_status)
  if not M._original.io_popen then
    M._original.io_popen = io.popen
  end
  
  -- Mock vim.v for shell_error
  if not M._original.vim_v then
    M._original.vim_v = vim.v
    vim.v = setmetatable({}, {
      __index = function(t, k)
        if k == 'shell_error' then
          return M._state.mock_shell_error or 0
        end
        return M._original.vim_v[k]
      end,
      __newindex = function(t, k, v)
        if k == 'shell_error' then
          M._state.mock_shell_error = v
        else
          M._original.vim_v[k] = v
        end
      end
    })
  end
  
  -- Mock io.popen to return git status output
  io.popen = function(cmd)
    if cmd:match('git status %-%-porcelain=v1') then
      local status_lines = {}
      for _, file in ipairs(M._state.git_status) do
        table.insert(status_lines, file.status .. ' ' .. file.file)
      end
      local output = table.concat(status_lines, '\n')
      if #status_lines > 0 then
        output = output .. '\n'
      end
      
      return {
        read = function(format)
          if format == '*a' then
            return output
          end
          return output
        end,
        close = function() end
      }
    elseif cmd:match('git diff %-%-numstat') then
      -- Check for specific mocks first
      for pattern, mock_response in pairs(M._state.system_commands) do
        if cmd:match(pattern) then
          local response = mock_response
          if type(response) == 'function' then
            response = response(cmd)
          end
          return {
            read = function(format)
              return response
            end,
            close = function() end
          }
        end
      end
      
      -- Default mock
      return {
        read = function(format)
          return "5\t2\ttest.lua\n"
        end,
        close = function() end
      }
    end
    
    -- Fall back to original for other commands
    if M._original.io_popen then
      return M._original.io_popen(cmd)
    end
    return nil
  end
  
  vim.fn.system = function(cmd)
    -- First check if there's a specific mock for this command
    for pattern, mock_response in pairs(M._state.system_commands) do
      if cmd:match(pattern) then
        -- Don't override shell_error here - let the mock function set it
        if type(mock_response) == 'function' then
          return mock_response(cmd)
        else
          M._state.mock_shell_error = 0  -- Only set to 0 for static responses
          return mock_response
        end
      end
    end
    
    -- Fall back to default git command mocks
    if cmd:match('git rev%-parse %-%-is%-inside%-work%-tree') then
      if M._state.git_repo then
        M._state.mock_shell_error = 0
        return 'true\n'
      else
        M._state.mock_shell_error = 1
        return 'fatal: not a git repository\n'
      end
    elseif cmd:match('git rev%-parse %-%-show%-toplevel') then
      if M._state.git_repo then
        M._state.mock_shell_error = 0
        return '/mock/repo/path\n'
      else
        M._state.mock_shell_error = 1
        return 'fatal: not a git repository\n'
      end
    elseif cmd:match('git status %-%-porcelain=v1') then
      M._state.mock_shell_error = 0
      local status_lines = {}
      for _, file in ipairs(M._state.git_status) do
        table.insert(status_lines, file.status .. ' ' .. file.file)
      end
      return table.concat(status_lines, '\n') .. '\n'
    elseif cmd:match('git log %-%-oneline') then
      M._state.mock_shell_error = 0
      local commit_lines = {}
      for _, commit in ipairs(M._state.git_commits) do
        local line = commit.hash
        if commit.decoration then
          line = line .. ' (' .. commit.decoration .. ')'
        end
        line = line .. ' ' .. commit.message
        table.insert(commit_lines, line)
      end
      return table.concat(commit_lines, '\n') .. '\n'
    elseif cmd:match('git diff %-%-numstat') then
      M._state.mock_shell_error = 0
      return "5\t2\ttest.lua\n"  -- Default mock diff stats
    elseif cmd:match('tmux display%-message %-p') then
      M._state.mock_shell_error = 0
      -- Mock tmux display-message commands
      if cmd:match('#{window_id}') then
        return M._state.tmux_env and (M._state.tmux_panes.window_id or '@1') .. '\n' or 'NOT_IN_TMUX\n'
      elseif cmd:match('#{pane_id}') then
        return M._state.tmux_env and (M._state.tmux_panes.pane_id or '%1') .. '\n' or 'NOT_IN_TMUX\n'
      else
        return M._state.tmux_env and 'mock_tmux_output\n' or 'NOT_IN_TMUX\n'
      end
    end
    
    -- Call original for other commands (with error handling)
    if M._original.vim_fn_system then
      return M._original.vim_fn_system(cmd)
    else
      -- Fallback for commands we don't mock
      M._state.mock_shell_error = 0
      return ""
    end
  end
end

function M.set_git_status(files)
  M._state.git_status = files
end

function M.set_git_commits(commits)
  M._state.git_commits = commits
end

-- Tmux mocking functions
function M.mock_tmux_env(enabled, pane_info)
  M._state.tmux_env = enabled
  M._state.tmux_panes = pane_info or {}
  
  -- Mock vim.env.TMUX
  if enabled then
    vim.env.TMUX = '/tmp/tmux-501/default,12345,0'
  else
    vim.env.TMUX = nil
  end
  
  -- Mock tmux commands
  vim.fn.system = function(cmd)
    if cmd:match("tmux display%-message %-p") then
      M._state.mock_shell_error = 0
      if cmd:match("#{pane_id}") then
        return M._state.tmux_panes.id or '%0\n'
      elseif cmd:match("#{pane_width}") then
        return tostring(M._state.tmux_panes.width or 80) .. '\n'
      elseif cmd:match("#{pane_height}") then
        return tostring(M._state.tmux_panes.height or 24) .. '\n'
      elseif cmd:match("#{window_id}") then
        return M._state.tmux_panes.window_id or '@1\n'
      end
    elseif cmd:match("tmux list%-panes") then
      M._state.mock_shell_error = 0
      return "0 claude\n1 bash\n"  -- Mock pane list
    elseif cmd:match("tmux send%-keys") then
      M._state.mock_shell_error = 0
      return ""  -- Mock successful command sending
    end
    
    -- Fallback to original or mock system
    if M._original.vim_fn_system then
      return M._original.vim_fn_system(cmd)
    else
      return ""
    end
  end
end

-- File system mocking
function M.mock_filesystem(files)
  M._state.filesystem = files
  
  if not M._original.vim_fn_filereadable then
    M._original.vim_fn_filereadable = vim.fn.filereadable
  end
  
  if not M._original.vim_fn_isdirectory then
    M._original.vim_fn_isdirectory = vim.fn.isdirectory
  end
  
  vim.fn.filereadable = function(path)
    if M._state.filesystem[path] ~= nil then
      return M._state.filesystem[path].readable and 1 or 0
    end
    return M._original.vim_fn_filereadable(path)
  end
  
  vim.fn.isdirectory = function(path)
    if M._state.filesystem[path] ~= nil then
      return M._state.filesystem[path].directory and 1 or 0
    end
    return M._original.vim_fn_isdirectory(path)
  end
end

-- Buffer API mocking
function M.mock_buffer_api()
  M._mock_buffers = {}
  M._mock_buffer_counter = 1
  
  if not M._original.nvim_create_buf then
    M._original.nvim_create_buf = vim.api.nvim_create_buf
  end
  
  vim.api.nvim_create_buf = function(listed, scratch)
    local buf_id = M._mock_buffer_counter
    M._mock_buffer_counter = M._mock_buffer_counter + 1
    
    M._mock_buffers[buf_id] = {
      listed = listed,
      scratch = scratch,
      lines = {},
      options = {},
      name = '',
      valid = true
    }
    
    return buf_id
  end
  
  if not M._original.nvim_buf_set_lines then
    M._original.nvim_buf_set_lines = vim.api.nvim_buf_set_lines
  end
  
  vim.api.nvim_buf_set_lines = function(buf, start, end_, strict, lines)
    if M._mock_buffers[buf] then
      M._mock_buffers[buf].lines = lines
      return true
    end
    return M._original.nvim_buf_set_lines(buf, start, end_, strict, lines)
  end
  
  if not M._original.nvim_buf_get_lines then
    M._original.nvim_buf_get_lines = vim.api.nvim_buf_get_lines
  end
  
  vim.api.nvim_buf_get_lines = function(buf, start, end_, strict)
    if M._mock_buffers[buf] then
      return M._mock_buffers[buf].lines or {}
    end
    return M._original.nvim_buf_get_lines(buf, start, end_, strict)
  end
  
  if not M._original.nvim_buf_is_valid then
    M._original.nvim_buf_is_valid = vim.api.nvim_buf_is_valid
  end
  
  vim.api.nvim_buf_is_valid = function(buf)
    if M._mock_buffers[buf] then
      return M._mock_buffers[buf].valid
    end
    return M._original.nvim_buf_is_valid(buf)
  end
end

-- Custom system command mocking
function M.mock_system_command(command_pattern, return_value_or_function)
  M._state.system_commands[command_pattern] = return_value_or_function
end

-- Logger mocking (silent during tests)
function M.mock_logger()
  local logger = require('nexus.logger')
  
  -- Store originals
  M._original.logger_info = logger.info
  M._original.logger_debug = logger.debug
  M._original.logger_warn = logger.warn
  M._original.logger_error = logger.error
  
  -- Replace with no-ops for quiet testing
  logger.info = function() end
  logger.debug = function() end
  logger.warn = function() end
  logger.error = function() end
end

-- Window/UI mocking
function M.mock_ui()
  -- Mock window functions
  if not M._original.vim_fn_winwidth then
    M._original.vim_fn_winwidth = vim.fn.winwidth
  end
  
  vim.fn.winwidth = function(nr)
    return 80  -- Standard test width
  end
  
  if not M._original.nvim_get_current_win then
    M._original.nvim_get_current_win = vim.api.nvim_get_current_win
  end
  
  vim.api.nvim_get_current_win = function()
    return 1  -- Mock window ID
  end
end

-- Configuration mocking
function M.mock_config(config_overrides)
  local config = require('nexus.config')
  
  if not M._original.config_get then
    M._original.config_get = config.get
  end
  
  config.get = function()
    local default_config = {
      open_on_startup = true,
      show_dashboard_buttons = true,
      show_keyboard_shortcuts = true,
      show_recent_commits = true,
      show_git_status = true,
      recent_commits_count = 3,
      logo_selection = "nexus",
      logo_color = "String"
    }
    
    if config_overrides then
      return vim.tbl_deep_extend('force', default_config, config_overrides)
    end
    
    return default_config
  end
end

-- Restore all mocks
function M.restore_all()
  -- Restore vim.fn functions
  if M._original.vim_fn_system then
    vim.fn.system = M._original.vim_fn_system
  end
  
  -- Restore io.popen
  if M._original.io_popen then
    io.popen = M._original.io_popen
  end
  
  -- Restore vim.v
  if M._original.vim_v then
    vim.v = M._original.vim_v
  end
  
  if M._original.vim_fn_filereadable then
    vim.fn.filereadable = M._original.vim_fn_filereadable
  end
  
  if M._original.vim_fn_isdirectory then
    vim.fn.isdirectory = M._original.vim_fn_isdirectory
  end
  
  if M._original.vim_fn_winwidth then
    vim.fn.winwidth = M._original.vim_fn_winwidth
  end
  
  -- Restore API functions
  if M._original.nvim_create_buf then
    vim.api.nvim_create_buf = M._original.nvim_create_buf
  end
  
  if M._original.nvim_buf_set_lines then
    vim.api.nvim_buf_set_lines = M._original.nvim_buf_set_lines
  end
  
  if M._original.nvim_buf_get_lines then
    vim.api.nvim_buf_get_lines = M._original.nvim_buf_get_lines
  end
  
  if M._original.nvim_buf_is_valid then
    vim.api.nvim_buf_is_valid = M._original.nvim_buf_is_valid
  end
  
  if M._original.nvim_get_current_win then
    vim.api.nvim_get_current_win = M._original.nvim_get_current_win
  end
  
  -- Restore logger
  if M._original.logger_info then
    local logger = require('nexus.logger')
    logger.info = M._original.logger_info
    logger.debug = M._original.logger_debug
    logger.warn = M._original.logger_warn
    logger.error = M._original.logger_error
  end
  
  -- Restore config
  if M._original.config_get then
    local config = require('nexus.config')
    config.get = M._original.config_get
  end
  
  -- Reset environment
  vim.env.TMUX = nil
  
  -- Clear state
  M._state = {
    git_status = {},
    git_commits = {},
    git_repo = true,
    tmux_env = false,
    tmux_panes = {},
    filesystem = {},
    system_commands = {}
  }
  M._mock_buffers = {}
  M._original = {}
end

-- Convenience function for test setup
function M.setup_test_environment(options)
  options = options or {}
  
  -- Always mock logger for quiet tests
  M.mock_logger()
  
  -- Mock UI components
  M.mock_ui()
  
  -- Mock buffer API
  M.mock_buffer_api()
  
  -- Set up git environment
  M.mock_git_repo(options.git_repo ~= false)
  if options.git_status then
    M.set_git_status(options.git_status)
  end
  if options.git_commits then
    M.set_git_commits(options.git_commits)
  end
  
  -- Set up tmux environment
  if options.tmux then
    M.mock_tmux_env(true, options.tmux)
  else
    M.mock_tmux_env(false)
  end
  
  -- Set up filesystem
  if options.filesystem then
    M.mock_filesystem(options.filesystem)
  end
  
  -- Mock configuration
  if options.config then
    M.mock_config(options.config)
  end
end

-- Cleanup function to restore all original functions
function M.cleanup()
  -- Restore vim.fn functions
  if M._original.vim_fn_system then
    vim.fn.system = M._original.vim_fn_system
    M._original.vim_fn_system = nil
  end
  
  if M._original.vim_fn_systemlist then
    vim.fn.systemlist = M._original.vim_fn_systemlist
    M._original.vim_fn_systemlist = nil
  end
  
  -- Restore vim.v
  if M._original.vim_v then
    vim.v = M._original.vim_v
    M._original.vim_v = nil
  end
  
  -- Restore buffer API functions
  if M._original.nvim_create_buf then
    vim.api.nvim_create_buf = M._original.nvim_create_buf
    M._original.nvim_create_buf = nil
  end
  
  if M._original.nvim_buf_set_lines then
    vim.api.nvim_buf_set_lines = M._original.nvim_buf_set_lines
    M._original.nvim_buf_set_lines = nil
  end
  
  if M._original.nvim_buf_get_lines then
    vim.api.nvim_buf_get_lines = M._original.nvim_buf_get_lines
    M._original.nvim_buf_get_lines = nil
  end
  
  if M._original.nvim_buf_is_valid then
    vim.api.nvim_buf_is_valid = M._original.nvim_buf_is_valid
    M._original.nvim_buf_is_valid = nil
  end
  
  -- Clear state
  M._state = {
    git_status = {},
    git_commits = {},
    git_repo = true,
    tmux_env = false,
    tmux_panes = {},
    filesystem = {},
    system_commands = {},
    mock_shell_error = 0
  }
  
  M._mock_buffers = {}
end

return M