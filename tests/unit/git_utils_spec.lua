-- Unit tests for nexus.git.utils module

local mocks = require('tests.helpers.mocks')

describe('nexus.git.utils', function()
  local git_utils
  
  before_each(function()
    -- Reset module cache
    package.loaded['nexus.git.utils'] = nil
    package.loaded['nexus.logger'] = nil
    
    mocks.setup_test_environment()
    git_utils = require('nexus.git.utils')
  end)
  
  after_each(function()
    mocks.restore_all()
  end)
  
  describe('is_git_repo', function()
    it('should return true when in git repository', function()
      mocks.mock_git_repo(true)
      
      local result = git_utils.is_git_repo()
      assert.is_true(result)
    end)
    
    it('should return false when not in git repository', function()
      mocks.mock_git_repo(false)
      
      local result = git_utils.is_git_repo()
      assert.is_false(result)
    end)
    
    it('should handle git command errors gracefully', function()
      -- Mock git command that returns error
      mocks.mock_system_command('git rev%-parse %-%-is%-inside%-work%-tree', function(cmd)
        vim.v.shell_error = 128  -- Git error code
        return 'fatal: not a git repository\n'
      end)
      
      local result = git_utils.is_git_repo()
      assert.is_false(result)
    end)
    
    it('should handle malformed git output', function()
      mocks.mock_system_command('git rev%-parse %-%-is%-inside%-work%-tree', function(cmd)
        vim.v.shell_error = 0
        return 'malformed output\n'  -- Not 'true'
      end)
      
      local result = git_utils.is_git_repo()
      assert.is_false(result)
    end)
  end)
  
  describe('get_git_root', function()
    it('should return git root path when in repository', function()
      mocks.mock_git_repo(true)
      
      local result = git_utils.get_git_root()
      assert.equals('/mock/repo/path', result)
    end)
    
    it('should return nil when not in git repository', function()
      mocks.mock_git_repo(false)
      
      local result = git_utils.get_git_root()
      assert.is_nil(result)
    end)
    
    it('should handle complex repository paths', function()
      mocks.mock_system_command('git rev%-parse %-%-show%-toplevel', function(cmd)
        vim.v.shell_error = 0
        return '/path/with spaces/and-special_chars123/repo\n'
      end)
      
      local result = git_utils.get_git_root()
      assert.equals('/path/with spaces/and-special_chars123/repo', result)
    end)
    
    it('should handle git command errors in get_git_root', function()
      mocks.mock_git_repo(true)  -- is_git_repo returns true
      mocks.mock_system_command('git rev%-parse %-%-show%-toplevel', function(cmd)
        vim.v.shell_error = 128
        return 'fatal: unable to access repository\n'
      end)
      
      local result = git_utils.get_git_root()
      -- Should still return something if systemlist returns empty table
      -- This tests the actual behavior of vim.fn.systemlist with errors
      assert.is_nil(result)
    end)
  end)
  
  describe('integration scenarios', function()
    it('should work correctly in nested git repositories', function()
      mocks.mock_git_repo(true)
      mocks.mock_system_command('git rev%-parse %-%-show%-toplevel', function(cmd)
        vim.v.shell_error = 0
        return '/parent/repo\n'  -- Parent repo, not nested
      end)
      
      assert.is_true(git_utils.is_git_repo())
      assert.equals('/parent/repo', git_utils.get_git_root())
    end)
    
    it('should handle bare repositories', function()
      mocks.mock_system_command('git rev%-parse %-%-is%-inside%-work%-tree', function(cmd)
        vim.v.shell_error = 0
        return 'false\n'  -- Bare repository
      end)
      
      local result = git_utils.is_git_repo()
      assert.is_false(result)  -- Current implementation expects 'true'
    end)
    
    it('should handle worktree scenarios', function()
      mocks.mock_git_repo(true)
      mocks.mock_system_command('git rev%-parse %-%-show%-toplevel', function(cmd)
        vim.v.shell_error = 0
        return '/main/repo/.git/worktrees/feature-branch\n'
      end)
      
      local result = git_utils.get_git_root()
      assert.equals('/main/repo/.git/worktrees/feature-branch', result)
    end)
  end)
  
  describe('edge cases', function()
    it('should handle empty git output', function()
      mocks.mock_system_command('git rev%-parse %-%-is%-inside%-work%-tree', function(cmd)
        vim.v.shell_error = 0
        return ''  -- Empty output
      end)
      
      local result = git_utils.is_git_repo()
      assert.is_false(result)
    end)
    
    it('should handle whitespace in git output', function()
      mocks.mock_system_command('git rev%-parse %-%-is%-inside%-work%-tree', function(cmd)
        vim.v.shell_error = 0
        return '  true  \n'  -- Whitespace around output
      end)
      
      local result = git_utils.is_git_repo()
      assert.is_true(result)  -- Should still match 'true'
    end)
    
    it('should handle missing git binary', function()
      mocks.mock_system_command('git rev%-parse %-%-is%-inside%-work%-tree', function(cmd)
        vim.v.shell_error = 127  -- Command not found
        return 'git: command not found\n'
      end)
      
      local result = git_utils.is_git_repo()
      assert.is_false(result)
    end)
  end)
end)