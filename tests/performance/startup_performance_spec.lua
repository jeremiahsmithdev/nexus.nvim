-- Performance tests for Nexus.nvim startup and operations

local mocks = require('tests.helpers.mocks')

describe('nexus performance', function()
  local function measure_time(func)
    local start_time = vim.loop.hrtime()
    func()
    local end_time = vim.loop.hrtime()
    return (end_time - start_time) / 1000000  -- Convert to milliseconds
  end
  
  before_each(function()
    -- Reset modules
    for module_name, _ in pairs(package.loaded) do
      if module_name:match('^nexus') then
        package.loaded[module_name] = nil
      end
    end
    
    mocks.setup_test_environment({
      git_repo = true,
      git_status = {},
      git_commits = {}
    })
  end)
  
  after_each(function()
    mocks.restore_all()
  end)
  
  describe('startup performance', function()
    it('should load nexus module quickly', function()
      local load_time = measure_time(function()
        require('nexus')
      end)
      
      -- Should load within 50ms
      assert.is_true(load_time < 50, string.format('Module load took %dms, expected < 50ms', load_time))
    end)
    
    it('should setup configuration quickly', function()
      local nexus = require('nexus')
      
      local setup_time = measure_time(function()
        nexus.setup({
          show_dashboard_buttons = true,
          show_keyboard_shortcuts = true,
          show_recent_commits = true,
          show_git_status = true
        })
      end)
      
      -- Configuration setup should be fast
      assert.is_true(setup_time < 25, string.format('Setup took %dms, expected < 25ms', setup_time))
    end)
    
    it('should open dashboard quickly with minimal git data', function()
      local nexus = require('nexus')
      nexus.setup()
      
      local open_time = measure_time(function()
        nexus.open(true)
      end)
      
      -- Dashboard opening should be fast for small repos
      assert.is_true(open_time < 100, string.format('Dashboard open took %dms, expected < 100ms', open_time))
    end)
  end)
  
  describe('git operations performance', function()
    it('should parse git status quickly with many files', function()
      -- Set up many git files
      local many_files = {}
      for i = 1, 1000 do
        table.insert(many_files, {
          status = i % 3 == 0 and ' M' or (i % 3 == 1 and '??' or 'A '),
          file = string.format('src/file_%04d.lua', i)
        })
      end
      
      mocks.set_git_status(many_files)
      
      local git_status = require('nexus.git.status')
      
      local parse_time = measure_time(function()
        git_status.parse_git_status()
      end)
      
      -- Should handle 1000 files within reasonable time
      assert.is_true(parse_time < 200, string.format('Git status parsing took %dms for 1000 files, expected < 200ms', parse_time))
    end)
    
    it('should render git status quickly with large file list', function()
      local many_files = {}
      for i = 1, 500 do
        table.insert(many_files, {
          status = ' M',
          file = string.format('path/to/file_%04d.lua', i)
        })
      end
      
      mocks.set_git_status(many_files)
      
      local nexus = require('nexus')
      nexus.setup()
      
      local render_time = measure_time(function()
        nexus.open(true)
      end)
      
      -- Should render 500 files within reasonable time
      assert.is_true(render_time < 300, string.format('Dashboard render took %dms for 500 files, expected < 300ms', render_time))
    end)
    
    it('should handle git commits efficiently', function()
      -- Set up many commits
      local many_commits = {}
      for i = 1, 100 do
        table.insert(many_commits, {
          hash = string.format('%07x', i),
          message = string.format('Commit message %d with some descriptive text', i),
          decoration = i == 1 and 'HEAD -> main' or nil
        })
      end
      
      mocks.set_git_commits(many_commits)
      
      local git_commits = require('nexus.git.commits')
      
      local commit_time = measure_time(function()
        git_commits.get_git_log({recent_commits_count = 50})
      end)
      
      -- Should process commits quickly even with many in history
      assert.is_true(commit_time < 100, string.format('Git log processing took %dms, expected < 100ms', commit_time))
    end)
  end)
  
  describe('rendering performance', function()
    it('should render large dashboard content quickly', function()
      -- Set up comprehensive test data
      local files = {}
      for i = 1, 200 do
        table.insert(files, {
          status = i % 2 == 0 and ' M' or '??',
          file = string.format('src/module_%03d.lua', i)
        })
      end
      
      local commits = {}
      for i = 1, 20 do
        table.insert(commits, {
          hash = string.format('commit%03d', i),
          message = 'Test commit message ' .. i,
          decoration = i == 1 and 'HEAD -> main' or nil
        })
      end
      
      mocks.set_git_status(files)
      mocks.set_git_commits(commits)
      
      local nexus = require('nexus')
      nexus.setup({
        show_dashboard_buttons = true,
        show_keyboard_shortcuts = true,
        show_recent_commits = true,
        show_git_status = true
      })
      
      local full_render_time = measure_time(function()
        nexus.open(true)
      end)
      
      -- Should render comprehensive dashboard within reasonable time
      assert.is_true(full_render_time < 400, string.format('Full dashboard render took %dms, expected < 400ms', full_render_time))
    end)
    
    it('should refresh dashboard efficiently', function()
      local nexus = require('nexus')
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      
      local refresh_time = measure_time(function()
        nexus.refresh_buffer(buf_id)
      end)
      
      -- Refresh should be very fast
      assert.is_true(refresh_time < 50, string.format('Dashboard refresh took %dms, expected < 50ms', refresh_time))
    end)
    
    it('should handle syntax highlighting efficiently', function()
      local files = {}
      for i = 1, 100 do
        table.insert(files, {
          status = ' M',
          file = string.format('file_%03d.lua', i)
        })
      end
      
      mocks.set_git_status(files)
      
      local render = require('nexus.render')
      local config = require('nexus.config')
      
      config.setup()
      
      local buf = 1
      mocks._mock_buffers[buf] = {lines = {}, options = {}}
      
      -- Mock highlighting functions to measure their call count
      local highlight_calls = 0
      vim.api.nvim_buf_add_highlight = function(buffer, ns, hl_group, line, col_start, col_end)
        highlight_calls = highlight_calls + 1
      end
      
      local highlight_time = measure_time(function()
        render.render_git_status(buf, config.get())
      end)
      
      -- Should handle highlighting for many files efficiently
      assert.is_true(highlight_time < 150, string.format('Syntax highlighting took %dms for 100 files, expected < 150ms', highlight_time))
      
      -- Should have created highlights
      assert.is_true(highlight_calls > 0)
    end)
  end)
  
  describe('memory efficiency', function()
    it('should not leak memory on repeated opens', function()
      local nexus = require('nexus')
      nexus.setup()
      
      -- Open and close multiple times
      for i = 1, 10 do
        nexus.open(true)
        
        -- Simulate buffer cleanup
        local buf_id = mocks._mock_buffer_counter - 1
        mocks._mock_buffers[buf_id] = nil
      end
      
      -- This test mainly ensures no crashes occur with repeated operations
      -- In real scenarios, memory profiling tools would be needed
      assert.is_true(true)  -- Test that we didn't crash
    end)
    
    it('should handle large string operations efficiently', function()
      -- Test diff stat creation with large numbers
      local git_status = require('nexus.git.status')
      
      local large_stat_time = measure_time(function()
        for i = 1, 1000 do
          git_status.create_diff_stat(i * 10, i * 5, 40)
        end
      end)
      
      -- Should handle many diff stat calculations quickly
      assert.is_true(large_stat_time < 100, string.format('1000 diff stat calculations took %dms, expected < 100ms', large_stat_time))
    end)
  end)
  
  describe('configuration performance', function()
    it('should validate complex configurations quickly', function()
      local config = require('nexus.config')
      
      local complex_config = {
        show_dashboard_buttons = true,
        show_keyboard_shortcuts = true,
        show_recent_commits = true,
        show_git_status = true,
        recent_commits_count = 10,
        git_status_count = 25,
        section_order = {
          "dashboard_buttons",
          "keyboard_shortcuts",
          "recent_commits",
          "git_status",
          "claude_conversations"
        },
        logo_selection = "nexus",
        logo_color = "String",
        -- Add many custom options
        custom_option1 = "value1",
        custom_option2 = "value2",
        custom_option3 = {nested = "value"},
        custom_option4 = true,
        custom_option5 = 42
      }
      
      local validation_time = measure_time(function()
        config.setup(complex_config)
      end)
      
      -- Configuration validation should be fast
      assert.is_true(validation_time < 25, string.format('Config validation took %dms, expected < 25ms', validation_time))
    end)
  end)
  
  describe('performance regression tests', function()
    it('should maintain performance with typical usage', function()
      -- Simulate typical small to medium repository
      local typical_files = {}
      for i = 1, 25 do
        table.insert(typical_files, {
          status = i % 4 == 0 and ' M' or (i % 4 == 1 and '??' or 'A '),
          file = string.format('src/component_%d.lua', i)
        })
      end
      
      local typical_commits = {}
      for i = 1, 5 do
        table.insert(typical_commits, {
          hash = string.format('abc%04x', i),
          message = 'Feature update ' .. i,
          decoration = i == 1 and 'HEAD -> main' or nil
        })
      end
      
      mocks.set_git_status(typical_files)
      mocks.set_git_commits(typical_commits)
      
      local nexus = require('nexus')
      
      local total_time = measure_time(function()
        nexus.setup()
        nexus.open(true)
        
        -- Simulate some typical operations
        local buf_id = mocks._mock_buffer_counter - 1
        nexus.refresh_buffer(buf_id)
      end)
      
      -- Total typical workflow should be very fast
      assert.is_true(total_time < 150, string.format('Typical workflow took %dms, expected < 150ms', total_time))
    end)
  end)
end)