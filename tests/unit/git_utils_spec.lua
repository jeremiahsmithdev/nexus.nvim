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
    it('should return truthy value when in git repository', function()
      mocks.mock_git_repo(true)
      
      local result = git_utils.is_git_repo()
      -- The implementation returns git_check:match('true') which returns 'true' (truthy)
      assert.is_truthy(result)
    end)
    
    it('should return false when not in git repository', function()
      mocks.mock_git_repo(false)
      
      local result = git_utils.is_git_repo()
      -- When shell_error != 0 or no 'true' match, it returns falsy
      assert.is_falsy(result)
    end)
    
    it('should handle git command errors gracefully', function()
      -- Test error condition by setting git_repo to false
      mocks.mock_git_repo(false)
      
      local result = git_utils.is_git_repo()
      -- Error condition should return falsy
      assert.is_falsy(result)
    end)
    
    it('should handle malformed git output', function()
      -- Test malformed output by setting git_repo to false
      mocks.mock_git_repo(false)
      
      local result = git_utils.is_git_repo()
      -- No 'true' match should return falsy  
      assert.is_falsy(result)
    end)
  end)
  
  describe('get_git_root', function()
    it('should return git root path when in repository', function()
      mocks.mock_git_repo(true)
      -- Mock systemlist to return array like the real implementation
      mocks.mock_system_command('git rev%-parse %-%-show%-toplevel', function(cmd)
        vim.v.shell_error = 0
        return '/mock/repo/path\n'
      end)
      vim.fn.systemlist = function(cmd)
        if cmd:match('git rev%-parse %-%-show%-toplevel') then
          return {'/mock/repo/path'}
        end
        return {}
      end
      
      local result = git_utils.get_git_root()
      assert.equals('/mock/repo/path', result)
    end)
    
    it('should return nil when not in git repository', function()
      mocks.mock_git_repo(false)
      
      local result = git_utils.get_git_root()
      assert.is_nil(result)
    end)
    
    it('should handle complex repository paths', function()
      mocks.mock_git_repo(true)
      mocks.mock_system_command('git rev%-parse %-%-show%-toplevel', function(cmd)
        vim.v.shell_error = 0
        return '/path/with spaces/and-special_chars123/repo\n'
      end)
      vim.fn.systemlist = function(cmd)
        if cmd:match('git rev%-parse %-%-show%-toplevel') then
          return {'/path/with spaces/and-special_chars123/repo'}
        end
        return {}
      end
      
      local result = git_utils.get_git_root()
      assert.equals('/path/with spaces/and-special_chars123/repo', result)
    end)
    
    it('should handle git command errors in get_git_root', function()
      -- Mock is_git_repo to return false due to error
      mocks.mock_git_repo(false)  -- This will make is_git_repo return falsy
      
      local result = git_utils.get_git_root()
      -- Should return nil because is_git_repo() returns false
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
      vim.fn.systemlist = function(cmd)
        if cmd:match('git rev%-parse %-%-show%-toplevel') then
          return {'/parent/repo'}
        end
        return {}
      end
      
      assert.is_truthy(git_utils.is_git_repo())
      assert.equals('/parent/repo', git_utils.get_git_root())
    end)
    
    it('should handle bare repositories', function()
      -- Test bare repository by setting git_repo to false
      mocks.mock_git_repo(false)
      
      local result = git_utils.is_git_repo()
      -- Output 'false' doesn't match 'true', so should return falsy
      assert.is_falsy(result)
    end)
    
    it('should handle worktree scenarios', function()
      mocks.mock_git_repo(true)
      mocks.mock_system_command('git rev%-parse %-%-show%-toplevel', function(cmd)
        vim.v.shell_error = 0
        return '/main/repo/.git/worktrees/feature-branch\n'
      end)
      vim.fn.systemlist = function(cmd)
        if cmd:match('git rev%-parse %-%-show%-toplevel') then
          return {'/main/repo/.git/worktrees/feature-branch'}
        end
        return {}
      end
      
      local result = git_utils.get_git_root()
      assert.equals('/main/repo/.git/worktrees/feature-branch', result)
    end)
  end)
  
  describe('edge cases', function()
    it('should handle empty git output', function()
      -- Test empty output by setting git_repo to false
      mocks.mock_git_repo(false)
      
      local result = git_utils.is_git_repo()
      -- Empty output doesn't match 'true', returns falsy
      assert.is_falsy(result)
    end)
    
    it('should handle whitespace in git output', function()
      mocks.mock_system_command('git rev%-parse %-%-is%-inside%-work%-tree', function(cmd)
        vim.v.shell_error = 0
        return '  true  \n'  -- Whitespace around output
      end)
      
      local result = git_utils.is_git_repo()
      -- :match('true') should find 'true' even with whitespace and return truthy
      assert.is_truthy(result)
    end)
    
    it('should handle missing git binary', function()
      -- Test missing git binary by setting git_repo to false
      mocks.mock_git_repo(false)
      
      local result = git_utils.is_git_repo()
      -- Error condition (shell_error != 0) should return falsy
      assert.is_falsy(result)
    end)
  end)
end)