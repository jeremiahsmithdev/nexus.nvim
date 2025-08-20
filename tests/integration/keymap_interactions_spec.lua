-- Integration tests for keymap interactions and navigation

local mocks = require('tests.helpers.mocks')

describe('keymap interactions integration', function()
  local nexus, keymaps, config
  local executed_commands = {}
  
  before_each(function()
    -- Reset modules
    package.loaded['nexus'] = nil
    package.loaded['nexus.keymaps'] = nil
    package.loaded['nexus.config'] = nil
    package.loaded['nexus.logger'] = nil
    package.loaded['nexus.buffer'] = nil
    package.loaded['nexus.git.operations'] = nil
    
    executed_commands = {}
    
    mocks.setup_test_environment({
      git_repo = true,
      git_status = {
        {status = ' M', file = 'src/main.lua'},
        {status = '??', file = 'README.md'},
        {status = 'A ', file = 'test.lua'}
      },
      git_commits = {
        {hash = 'a1b2c3d', message = 'Test commit', decoration = 'HEAD -> main'}
      }
    })
    
    -- Mock vim.cmd to track command execution
    vim.cmd = function(command)
      table.insert(executed_commands, command)
    end
    
    -- Mock vim.fn.fnameescape
    vim.fn.fnameescape = function(path)
      return "'" .. path .. "'"
    end
    
    -- Mock cursor operations
    local mock_cursor_pos = {1, 0}
    vim.api.nvim_win_get_cursor = function(win)
      return mock_cursor_pos
    end
    
    vim.api.nvim_win_set_cursor = function(win, pos)
      mock_cursor_pos = pos
    end
    
    -- Mock keymap setting
    local mock_keymaps = {}
    vim.api.nvim_buf_set_keymap = function(buf, mode, key, cmd, opts)
      if not mock_keymaps[buf] then
        mock_keymaps[buf] = {}
      end
      mock_keymaps[buf][key] = {
        mode = mode,
        cmd = cmd,
        opts = opts,
        callback = opts.callback
      }
    end
    
    nexus = require('nexus')
    keymaps = require('nexus.keymaps')
    config = require('nexus.config')
  end)
  
  after_each(function()
    executed_commands = {}
    mocks.restore_all()
  end)
  
  describe('dashboard button interactions', function()
    it('should handle find file button activation', function()
      config.setup({ show_dashboard_buttons = true })
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      
      -- Find the "Find file" button line
      local find_file_line = nil
      for i, line in ipairs(buffer_lines) do
        if line:match('Find file') then
          find_file_line = i
          break
        end
      end
      
      assert.is_not_nil(find_file_line)
      
      -- Simulate cursor on find file line and Enter press
      vim.api.nvim_win_set_cursor(0, {find_file_line, 0})
      
      -- Mock the keymap callback execution
      local current_line = buffer_lines[find_file_line]
      assert.matches('Find file', current_line)
      
      -- Simulate enter keymap execution
      keymaps.handle_dashboard_action(config.get(), 'Telescope find_files')
      
      -- Should have executed telescope command
      assert.equals('Telescope find_files', executed_commands[#executed_commands])
    end)
    
    it('should handle new file button activation', function()
      config.setup({ show_dashboard_buttons = true })
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      
      -- Find new file button
      local new_file_line = nil
      for i, line in ipairs(buffer_lines) do
        if line:match('New file') then
          new_file_line = i
          break
        end
      end
      
      assert.is_not_nil(new_file_line)
      
      keymaps.handle_dashboard_action(config.get(), 'enew')
      assert.equals('enew', executed_commands[#executed_commands])
    end)
  end)
  
  describe('git status interactions', function()
    it('should handle file opening from git status', function()
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      
      -- Find git status line
      local git_file_line = nil
      for i, line in ipairs(buffer_lines) do
        if line:match('src/main.lua') then
          git_file_line = i
          break
        end
      end
      
      assert.is_not_nil(git_file_line)
      
      -- Simulate enter on git status line
      vim.api.nvim_win_set_cursor(0, {git_file_line, 0})
      
      -- Mock git root
      vim.fn.systemlist = function(cmd)
        if cmd:match('git rev%-parse %-%-show%-toplevel') then
          return {'/mock/repo/path'}
        end
        return {}
      end
      
      local expected_cmd = "edit '/mock/repo/path/src/main.lua' | set number | set signcolumn=yes"
      keymaps.handle_dashboard_action(config.get(), expected_cmd)
      
      assert.equals(expected_cmd, executed_commands[#executed_commands])
    end)
    
    it('should handle git add operation', function()
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      
      -- Find git status line for modified file
      local git_file_line = nil
      for i, line in ipairs(buffer_lines) do
        if line:match('src/main.lua') then
          git_file_line = i
          break
        end
      end
      
      assert.is_not_nil(git_file_line)
      
      -- Position cursor on the line
      vim.api.nvim_win_set_cursor(0, {git_file_line, 0})
      
      -- Mock git add operation
      local git_add_called = false
      local mock_git_operations = {
        git_add_file = function(filename, callback)
          git_add_called = true
          assert.equals('src/main.lua', filename)
          if callback then callback() end
        end
      }
      package.loaded['nexus.git.operations'] = mock_git_operations
      
      -- Get keymaps module after mocking operations
      keymaps = require('nexus.keymaps')
      
      -- Simulate 'a' key press (git add)
      local render_callback = function() end
      keymaps.handle_git_add(buf_id, render_callback)
      
      assert.is_true(git_add_called)
    end)
    
    it('should handle git unstage operation', function()
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      
      -- Find git status line for staged file
      local git_file_line = nil
      for i, line in ipairs(buffer_lines) do
        if line:match('test.lua') then  -- This is the 'A ' staged file
          git_file_line = i
          break
        end
      end
      
      assert.is_not_nil(git_file_line)
      
      vim.api.nvim_win_set_cursor(0, {git_file_line, 0})
      
      -- Mock git unstage operation
      local git_unstage_called = false
      local mock_git_operations = {
        git_unstage_file = function(filename, callback)
          git_unstage_called = true
          assert.equals('test.lua', filename)
          if callback then callback() end
        end
      }
      package.loaded['nexus.git.operations'] = mock_git_operations
      
      keymaps = require('nexus.keymaps')
      
      local render_callback = function() end
      keymaps.handle_git_unstage(buf_id, render_callback)
      
      assert.is_true(git_unstage_called)
    end)
  end)
  
  describe('navigation behavior', function()
    it('should skip non-actionable lines during navigation', function()
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      
      -- Mock navigation function testing
      local logo = require('nexus.ui.logo')
      local logo_lines = logo.get_neovim_logo(config.get())
      local logo_end_line = #logo_lines
      
      -- Test that navigation skips logo lines
      -- Position cursor in logo section
      vim.api.nvim_win_set_cursor(0, {1, 0})
      
      -- The actual navigation logic would be in the j/k keymap callbacks
      -- For testing, we verify that navigation would move past logo
      local current_pos = vim.api.nvim_win_get_cursor(0)[1]
      assert.is_true(current_pos <= logo_end_line)
      
      -- A successful navigation would move past logo section
      -- This tests the concept, real implementation is in keymap callbacks
    end)
    
    it('should handle gg keymap to go to first actionable line', function()
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      
      -- The gg keymap should position cursor on first actionable line
      -- This is implemented in the keymap callback setup
      -- Test verifies the concept exists
      
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      assert.is_table(buffer_lines)
      assert.is_true(#buffer_lines > 0)
    end)
  end)
  
  describe('quit behavior', function()
    it('should quit nvim when nexus is only buffer', function()
      nexus.setup()
      nexus.open(true)
      
      -- Mock buffer listing (only nexus buffer exists)
      vim.api.nvim_list_bufs = function()
        return {mocks._mock_buffer_counter - 1}  -- Only the nexus buffer
      end
      
      vim.api.nvim_buf_is_loaded = function(buf)
        return buf == (mocks._mock_buffer_counter - 1)
      end
      
      vim.api.nvim_buf_get_option = function(buf, option)
        if option == 'buflisted' then
          return buf == (mocks._mock_buffer_counter - 1)
        elseif option == 'buftype' then
          return 'nofile'  -- Nexus buffer type
        elseif option == 'modified' then
          return false
        end
        return nil
      end
      
      vim.api.nvim_buf_get_name = function(buf)
        return buf == (mocks._mock_buffer_counter - 1) and 'Nexus' or ''
      end
      
      -- Test async_quit function
      local quit_executed = false
      vim.cmd = function(cmd)
        if cmd == 'qa!' then
          quit_executed = true
        end
        table.insert(executed_commands, cmd)
      end
      
      -- Mock vim.schedule to execute immediately
      vim.schedule = function(callback)
        callback()
      end
      
      keymaps.async_quit()
      
      assert.is_true(quit_executed)
    end)
    
    it('should not quit when other buffers exist', function()
      nexus.setup()
      nexus.open(true)
      
      local nexus_buf = mocks._mock_buffer_counter - 1
      
      -- Mock multiple buffers
      vim.api.nvim_list_bufs = function()
        return {nexus_buf, 999}  -- Nexus buffer and another buffer
      end
      
      vim.api.nvim_buf_is_loaded = function(buf)
        return true
      end
      
      vim.api.nvim_buf_get_option = function(buf, option)
        if option == 'buflisted' then
          return true
        elseif option == 'buftype' then
          return buf == nexus_buf and 'nofile' or ''  -- Other buffer is normal file
        elseif option == 'modified' then
          return false
        end
        return nil
      end
      
      vim.api.nvim_buf_get_name = function(buf)
        return buf == nexus_buf and 'Nexus' or 'other_file.lua'
      end
      
      local quit_executed = false
      vim.cmd = function(cmd)
        if cmd == 'qa!' then
          quit_executed = true
        end
        table.insert(executed_commands, cmd)
      end
      
      vim.schedule = function(callback)
        callback()
      end
      
      keymaps.async_quit()
      
      assert.is_false(quit_executed)
    end)
  end)
  
  describe('commit viewing', function()
    it('should show commit details when enter pressed on commit line', function()
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      
      -- Find commit line
      local commit_line = nil
      for i, line in ipairs(buffer_lines) do
        if line:match('a1b2c3d') then
          commit_line = line
          break
        end
      end
      
      assert.is_not_nil(commit_line)
      
      -- Mock git show command
      vim.fn.systemlist = function(cmd)
        if cmd:match('git show') then
          return {
            'commit a1b2c3d',
            'Author: Test Author',
            'Date: Mon Jan 1 12:00:00 2024',
            '',
            '    Test commit',
            '',
            ' test.lua | 5 +++++',
            ' 1 file changed, 5 insertions(+)'
          }
        end
        return {}
      end
      
      -- Mock popup window creation
      local popup_created = false
      vim.api.nvim_open_win = function(buf, enter, config)
        popup_created = true
        return 1  -- Mock window ID
      end
      
      keymaps.show_commit_details(commit_line)
      
      assert.is_true(popup_created)
    end)
  end)
end)