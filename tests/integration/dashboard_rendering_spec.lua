-- Integration tests for full dashboard rendering workflow

local mocks = require('tests.helpers.mocks')

describe('dashboard rendering integration', function()
  local nexus, render, config
  
  before_each(function()
    -- Reset all modules
    package.loaded['nexus'] = nil
    package.loaded['nexus.render'] = nil
    package.loaded['nexus.config'] = nil
    package.loaded['nexus.logger'] = nil
    package.loaded['nexus.buffer'] = nil
    package.loaded['nexus.git.utils'] = nil
    package.loaded['nexus.git.status'] = nil
    package.loaded['nexus.ui.logo'] = nil
    
    mocks.setup_test_environment({
      git_repo = true,
      git_status = {
        {status = ' M', file = 'src/main.lua'},
        {status = '??', file = 'README.md'},
        {status = 'A ', file = 'tests/new_test.lua'}
      },
      git_commits = {
        {hash = 'a1b2c3d', message = 'Add new feature', decoration = 'HEAD -> main'},
        {hash = 'e4f5g6h', message = 'Fix bug in parser'},
        {hash = 'i7j8k9l', message = 'Initial commit'}
      }
    })
    
    nexus = require('nexus')
    render = require('nexus.render')
    config = require('nexus.config')
  end)
  
  after_each(function()
    mocks.restore_all()
  end)
  
  describe('full dashboard workflow', function()
    it('should render complete dashboard with all sections', function()
      -- Configure to show all sections
      config.setup({
        show_dashboard_buttons = true,
        show_keyboard_shortcuts = true,
        show_recent_commits = true,
        show_git_status = true,
        logo_selection = "nexus"
      })
      
      -- Create and render dashboard
      nexus.setup()
      nexus.open(true)  -- Manual open
      
      -- Verify buffer was created and has content
      assert.is_true(mocks._mock_buffer_counter > 1)  -- Should have created a buffer
      
      -- Get the created buffer
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      
      assert.is_table(buffer_lines)
      assert.is_true(#buffer_lines > 0)
      
      local content = table.concat(buffer_lines, '\n')
      
      -- Should contain NEXUS logo
      assert.matches('NEXUS', content)
      
      -- Should contain recent commits
      assert.matches('Recent Commits', content)
      assert.matches('a1b2c3d', content)
      assert.matches('Add new feature', content)
      
      -- Should contain git status
      assert.matches('Git Status', content)
      assert.matches('src/main.lua', content)
      assert.matches('README.md', content)
    end)
    
    it('should handle minimal dashboard configuration', function()
      config.setup({
        show_dashboard_buttons = false,
        show_keyboard_shortcuts = false,
        show_recent_commits = false,
        show_git_status = true,
        logo_selection = "neovim"
      })
      
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      local content = table.concat(buffer_lines, '\n')
      
      -- Should contain neovim logo (not NEXUS)
      assert.matches('neovim', content)
      assert.not_matches('NEXUS', content)
      
      -- Should not contain recent commits
      assert.not_matches('Recent Commits', content)
      
      -- Should still contain git status
      assert.matches('Git Status', content)
    end)
    
    it('should handle non-git repository scenario', function()
      mocks.setup_test_environment({
        git_repo = false
      })
      
      nexus = require('nexus')
      config = require('nexus.config')
      
      config.setup({
        show_dashboard_buttons = true,
        show_recent_commits = true,
        show_git_status = true
      })
      
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      local content = table.concat(buffer_lines, '\n')
      
      -- Should contain logo
      assert.matches('NEXUS', content)
      
      -- Should not contain git-specific sections
      assert.not_matches('Recent Commits', content)
      assert.not_matches('Git Status', content)
    end)
  end)
  
  describe('section ordering', function()
    it('should respect custom section order', function()
      config.setup({
        show_dashboard_buttons = true,
        show_keyboard_shortcuts = true,
        show_recent_commits = true,
        show_git_status = true,
        section_order = {
          "git_status",
          "recent_commits",
          "dashboard_buttons",
          "keyboard_shortcuts"
        }
      })
      
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      local content = table.concat(buffer_lines, '\n')
      
      -- Find positions of sections
      local git_status_pos = content:find('Git Status')
      local recent_commits_pos = content:find('Recent Commits')
      
      -- Git status should come before recent commits
      assert.is_not_nil(git_status_pos)
      assert.is_not_nil(recent_commits_pos)
      assert.is_true(git_status_pos < recent_commits_pos)
    end)
    
    it('should handle missing sections in custom order gracefully', function()
      config.setup({
        show_dashboard_buttons = true,
        show_git_status = true,
        section_order = {
          "git_status",
          "nonexistent_section",
          "dashboard_buttons"
        }
      })
      
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      
      -- Should not crash and should still render valid sections
      assert.is_table(buffer_lines)
      assert.is_true(#buffer_lines > 0)
      
      local content = table.concat(buffer_lines, '\n')
      assert.matches('Git Status', content)
    end)
  end)
  
  describe('buffer management integration', function()
    it('should create persistent buffer for manual opens', function()
      nexus.setup()
      nexus.open(true)  -- Manual open
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_info = mocks._mock_buffers[buf_id]
      
      assert.is_true(buffer_info.listed)
      assert.is_false(buffer_info.scratch)
      assert.equals('hide', buffer_info.options.bufhidden)
      assert.is_true(buffer_info.options.buflisted)
    end)
    
    it('should create non-persistent buffer for auto opens', function()
      nexus.setup()
      nexus.open(false)  -- Auto open
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_info = mocks._mock_buffers[buf_id]
      
      assert.is_false(buffer_info.listed)
      assert.is_true(buffer_info.scratch)
      assert.equals('wipe', buffer_info.options.bufhidden)
      assert.is_false(buffer_info.options.buflisted)
    end)
  end)
  
  describe('git status display', function()
    it('should handle large numbers of files with proper formatting', function()
      -- Set up many git files
      local many_files = {}
      for i = 1, 20 do
        table.insert(many_files, {
          status = i % 2 == 0 and ' M' or '??',
          file = string.format('file_%02d.lua', i)
        })
      end
      
      mocks.set_git_status(many_files)
      
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      local content = table.concat(buffer_lines, '\n')
      
      -- Should contain git status section
      assert.matches('Git Status', content)
      
      -- Should contain some of the files
      assert.matches('file_01.lua', content)
      assert.matches('file_02.lua', content)
    end)
    
    it('should display "No changes" when git status is empty', function()
      mocks.set_git_status({})
      
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      local content = table.concat(buffer_lines, '\n')
      
      assert.matches('No changes detected', content)
    end)
  end)
  
  describe('refresh functionality', function()
    it('should refresh existing buffer correctly', function()
      nexus.setup()
      nexus.open(true)
      
      local buf_id = mocks._mock_buffer_counter - 1
      
      -- Change git status
      mocks.set_git_status({
        {status = 'A ', file = 'new_added_file.lua'}
      })
      
      -- Refresh the buffer
      nexus.refresh_buffer(buf_id)
      
      local buffer_lines = mocks._mock_buffers[buf_id].lines
      local content = table.concat(buffer_lines, '\n')
      
      -- Should contain the new file
      assert.matches('new_added_file.lua', content)
    end)
    
    it('should handle refresh of invalid buffer gracefully', function()
      nexus.setup()
      
      -- Try to refresh non-existent buffer
      local result = nexus.refresh_buffer(999)
      
      -- Should not crash
      assert.is_nil(result)  -- Function returns nothing on invalid buffer
    end)
  end)
  
  describe('configuration changes', function()
    it('should apply configuration changes on setup', function()
      -- First setup with default config
      nexus.setup()
      nexus.open(true)
      
      local buf_id_1 = mocks._mock_buffer_counter - 1
      local content_1 = table.concat(mocks._mock_buffers[buf_id_1].lines, '\n')
      
      -- Setup with different config
      nexus.setup({
        show_dashboard_buttons = false,
        logo_selection = "neovim"
      })
      nexus.open(true)
      
      local buf_id_2 = mocks._mock_buffer_counter - 1
      local content_2 = table.concat(mocks._mock_buffers[buf_id_2].lines, '\n')
      
      -- Content should be different
      assert.not_equals(content_1, content_2)
      
      -- Second buffer should have neovim logo
      assert.matches('neovim', content_2)
      assert.not_matches('NEXUS', content_2)
    end)
  end)
end)