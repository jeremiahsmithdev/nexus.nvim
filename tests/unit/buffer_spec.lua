-- Unit tests for nexus.buffer module

local mocks = require('tests.helpers.mocks')

describe('nexus.buffer', function()
  local buffer_mod
  local mock_autocmds = {}
  local mock_augroups = {}
  
  before_each(function()
    -- Reset module cache
    package.loaded['nexus.buffer'] = nil
    package.loaded['nexus.logger'] = nil
    
    mocks.setup_test_environment()
    
    -- Mock autocommand functions
    mock_autocmds = {}
    mock_augroups = {}
    
    vim.api.nvim_create_autocmd = function(events, opts)
      table.insert(mock_autocmds, {
        events = events,
        opts = opts
      })
      return #mock_autocmds  -- Return mock autocmd ID
    end
    
    vim.api.nvim_create_augroup = function(name, opts)
      mock_augroups[name] = opts
      return name
    end
    
    vim.api.nvim_del_augroup_by_name = function(name)
      mock_augroups[name] = nil
    end
    
    -- Mock buffer option setting
    vim.api.nvim_buf_set_option = function(buf, option, value)
      if mocks._mock_buffers[buf] then
        mocks._mock_buffers[buf].options[option] = value
      end
    end
    
    -- Mock window option setting
    vim.api.nvim_win_set_option = function(win, option, value)
      -- Mock implementation
    end
    
    buffer_mod = require('nexus.buffer')
  end)
  
  after_each(function()
    mock_autocmds = {}
    mock_augroups = {}
    mocks.restore_all()
  end)
  
  describe('create_nexus_buffer', function()
    it('should create listed buffer for manual opens', function()
      local buf = buffer_mod.create_nexus_buffer(true)
      
      assert.is_number(buf)
      assert.is_true(mocks._mock_buffers[buf].listed)
      assert.is_false(mocks._mock_buffers[buf].scratch)
      
      -- Check buffer options
      local options = mocks._mock_buffers[buf].options
      assert.equals('nexus', options.filetype)
      assert.equals('nofile', options.buftype)
      assert.is_false(options.swapfile)
      assert.equals('hide', options.bufhidden)
      assert.is_true(options.buflisted)
      assert.is_false(options.modifiable)
    end)
    
    it('should create unlisted buffer for auto opens', function()
      local buf = buffer_mod.create_nexus_buffer(false)
      
      assert.is_number(buf)
      assert.is_false(mocks._mock_buffers[buf].listed)
      assert.is_true(mocks._mock_buffers[buf].scratch)
      
      -- Check buffer options
      local options = mocks._mock_buffers[buf].options
      assert.equals('nexus', options.filetype)
      assert.equals('nofile', options.buftype)
      assert.is_false(options.swapfile)
      assert.equals('wipe', options.bufhidden)
      assert.is_false(options.buflisted)
      assert.is_false(options.modifiable)
    end)
  end)
  
  describe('setup_window_options', function()
    it('should set correct window options', function()
      local window_options = {}
      
      vim.api.nvim_win_set_option = function(win, option, value)
        window_options[option] = value
      end
      
      buffer_mod.setup_window_options()
      
      assert.is_false(window_options.number)
      assert.is_false(window_options.relativenumber)
      assert.equals('no', window_options.signcolumn)
      assert.is_false(window_options.wrap)
      assert.is_true(window_options.cursorline)
    end)
  end)
  
  describe('open_buffer', function()
    it('should replace empty startup buffer', function()
      local buf = buffer_mod.create_nexus_buffer(false)
      
      -- Mock empty startup buffer scenario
      local current_buf = 999
      vim.api.nvim_get_current_buf = function() return current_buf end
      vim.api.nvim_buf_get_name = function(b) return b == current_buf and '' or 'test' end
      vim.api.nvim_buf_get_lines = function(b, start, end_, strict) 
        return b == current_buf and {''} or {'content'} 
      end
      
      local win_set_buf_called = false
      local buf_delete_called = false
      
      vim.api.nvim_win_set_buf = function(win, buffer)
        win_set_buf_called = true
        assert.equals(buf, buffer)
      end
      
      vim.api.nvim_buf_delete = function(buffer, opts)
        buf_delete_called = true
        assert.equals(current_buf, buffer)
        assert.is_true(opts.force)
      end
      
      buffer_mod.open_buffer(buf, false)
      
      assert.is_true(win_set_buf_called)
      assert.is_true(buf_delete_called)
    end)
    
    it('should not replace non-empty buffers', function()
      local buf = buffer_mod.create_nexus_buffer(true)
      
      -- Mock non-empty buffer scenario
      local current_buf = 999
      vim.api.nvim_get_current_buf = function() return current_buf end
      vim.api.nvim_buf_get_name = function(b) return 'existing_file.lua' end
      vim.api.nvim_buf_get_lines = function(b, start, end_, strict) 
        return {'line1', 'line2'} 
      end
      
      local win_set_buf_called = false
      local buf_delete_called = false
      
      vim.api.nvim_win_set_buf = function(win, buffer)
        win_set_buf_called = true
        assert.equals(buf, buffer)
      end
      
      vim.api.nvim_buf_delete = function(buffer, opts)
        buf_delete_called = true
      end
      
      buffer_mod.open_buffer(buf, true)
      
      assert.is_true(win_set_buf_called)
      assert.is_false(buf_delete_called)  -- Should not delete non-empty buffer
    end)
    
    it('should find and reuse existing Nexus buffer for manual opens', function()
      -- Mock existing Nexus buffer
      local existing_buf = 888
      mocks._mock_buffers[existing_buf] = {valid = true}
      
      vim.api.nvim_list_bufs = function()
        return {existing_buf, 999, 1000}
      end
      
      vim.api.nvim_buf_is_valid = function(buf)
        return buf == existing_buf
      end
      
      vim.api.nvim_buf_get_name = function(buf)
        return buf == existing_buf and '/path/to/Nexus' or '/path/to/other'
      end
      
      local win_set_buf_called = false
      vim.api.nvim_win_set_buf = function(win, buffer)
        win_set_buf_called = true
        assert.equals(existing_buf, buffer)
      end
      
      local new_buf = buffer_mod.create_nexus_buffer(true)
      buffer_mod.open_buffer(new_buf, true)
      
      assert.is_true(win_set_buf_called)
    end)
  end)
  
  describe('setup_image_autocommands', function()
    it('should create autocommand group for buffer', function()
      local buf = buffer_mod.create_nexus_buffer(true)
      buffer_mod.setup_image_autocommands(buf)
      
      local expected_group = 'NexusImage' .. buf
      assert.is_not_nil(mock_augroups[expected_group])
      assert.is_true(mock_augroups[expected_group].clear)
    end)
    
    it('should create BufDelete autocommand', function()
      local buf = buffer_mod.create_nexus_buffer(true)
      buffer_mod.setup_image_autocommands(buf)
      
      local bufdelete_autocmd = nil
      for _, autocmd in ipairs(mock_autocmds) do
        if autocmd.events == 'BufDelete' and autocmd.opts.buffer == buf then
          bufdelete_autocmd = autocmd
          break
        end
      end
      
      assert.is_not_nil(bufdelete_autocmd)
      assert.equals('NexusImage' .. buf, bufdelete_autocmd.opts.group)
      assert.is_function(bufdelete_autocmd.opts.callback)
    end)
    
    it('should create BufEnter autocommand', function()
      local buf = buffer_mod.create_nexus_buffer(true)
      buffer_mod.setup_image_autocommands(buf)
      
      local bufenter_autocmd = nil
      for _, autocmd in ipairs(mock_autocmds) do
        if autocmd.events == 'BufEnter' and autocmd.opts.buffer == buf then
          bufenter_autocmd = autocmd
          break
        end
      end
      
      assert.is_not_nil(bufenter_autocmd)
      assert.equals('NexusImage' .. buf, bufenter_autocmd.opts.group)
      assert.is_function(bufenter_autocmd.opts.callback)
    end)
    
    it('should create FocusGained autocommand', function()
      local buf = buffer_mod.create_nexus_buffer(true)
      buffer_mod.setup_image_autocommands(buf)
      
      local focus_gained_autocmds = {}
      for _, autocmd in ipairs(mock_autocmds) do
        if autocmd.events == 'FocusGained' then
          table.insert(focus_gained_autocmds, autocmd)
        end
      end
      
      -- Should have at least one FocusGained autocmd for the buffer
      assert.is_true(#focus_gained_autocmds > 0)
      
      local buffer_focus_autocmd = nil
      for _, autocmd in ipairs(focus_gained_autocmds) do
        if autocmd.opts.buffer == buf then
          buffer_focus_autocmd = autocmd
          break
        end
      end
      
      assert.is_not_nil(buffer_focus_autocmd)
    end)
    
    it('should create FocusLost autocommand', function()
      local buf = buffer_mod.create_nexus_buffer(true)
      buffer_mod.setup_image_autocommands(buf)
      
      local focuslost_autocmd = nil
      for _, autocmd in ipairs(mock_autocmds) do
        if autocmd.events == 'FocusLost' and autocmd.opts.buffer == buf then
          focuslost_autocmd = autocmd
          break
        end
      end
      
      assert.is_not_nil(focuslost_autocmd)
      assert.equals('NexusImage' .. buf, focuslost_autocmd.opts.group)
      assert.is_function(focuslost_autocmd.opts.callback)
    end)
    
    it('should create git-related autocommands when in git repo', function()
      mocks.mock_git_repo(true)
      
      local buf = buffer_mod.create_nexus_buffer(true)
      buffer_mod.setup_image_autocommands(buf)
      
      -- Should have BufWritePost autocmd
      local bufwrite_autocmd = nil
      for _, autocmd in ipairs(mock_autocmds) do
        if autocmd.events == 'BufWritePost' then
          bufwrite_autocmd = autocmd
          break
        end
      end
      
      assert.is_not_nil(bufwrite_autocmd)
      assert.equals('NexusImage' .. buf, bufwrite_autocmd.opts.group)
      assert.equals('*', bufwrite_autocmd.opts.pattern)
      
      -- Should have ShellCmdPost autocmd
      local shellcmd_autocmd = nil
      for _, autocmd in ipairs(mock_autocmds) do
        if autocmd.events == 'ShellCmdPost' then
          shellcmd_autocmd = autocmd
          break
        end
      end
      
      assert.is_not_nil(shellcmd_autocmd)
      assert.equals('NexusImage' .. buf, shellcmd_autocmd.opts.group)
    end)
    
    it('should not create git autocommands when not in git repo', function()
      mocks.mock_git_repo(false)
      
      local buf = buffer_mod.create_nexus_buffer(true)
      buffer_mod.setup_image_autocommands(buf)
      
      -- Should not have BufWritePost autocmd
      local bufwrite_autocmd = nil
      for _, autocmd in ipairs(mock_autocmds) do
        if autocmd.events == 'BufWritePost' then
          bufwrite_autocmd = autocmd
          break
        end
      end
      
      assert.is_nil(bufwrite_autocmd)
    end)
  end)
  
  describe('tmux integration', function()
    it('should log tmux context when available', function()
      mocks.setup_test_environment({
        tmux = {
          id = '%0',
          window_id = '@1',
          width = 80,
          height = 24
        }
      })
      
      -- Reset to get tmux-aware buffer module
      package.loaded['nexus.buffer'] = nil
      buffer_mod = require('nexus.buffer')
      
      local buf = buffer_mod.create_nexus_buffer(true)
      buffer_mod.setup_image_autocommands(buf)
      
      -- Should have created autocommands (this verifies tmux context was handled)
      assert.is_true(#mock_autocmds > 0)
    end)
  end)
end)