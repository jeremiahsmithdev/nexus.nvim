-- Unit tests for nexus.config module

local mocks = require('tests.helpers.mocks')

describe('nexus.config', function()
  local config
  
  before_each(function()
    -- Reset module cache to get fresh instance
    package.loaded['nexus.config'] = nil
    package.loaded['nexus.logger'] = nil
    
    mocks.setup_test_environment()
    config = require('nexus.config')
  end)
  
  after_each(function()
    mocks.restore_all()
  end)
  
  describe('default configuration', function()
    it('should have correct default values', function()
      local default_config = config.get()
      
      assert.is_true(default_config.open_on_startup)
      assert.is_false(default_config.keep_open_after_startup)
      assert.is_false(default_config.show_claude_conversations)
      assert.is_true(default_config.show_dashboard_buttons)
      assert.is_true(default_config.show_keyboard_shortcuts)
      assert.is_true(default_config.show_recent_commits)
      assert.is_true(default_config.show_git_status)
      assert.equals(3, default_config.recent_commits_count)
      assert.equals("nexus", default_config.logo_selection)
      assert.equals("String", default_config.logo_color)
    end)
    
    it('should have correct section order', function()
      local default_config = config.get()
      local expected_order = {
        "dashboard_buttons",
        "keyboard_shortcuts", 
        "recent_commits",
        "git_status",
        "claude_conversations"
      }
      
      assert.are.same(expected_order, default_config.section_order)
    end)
  end)
  
  describe('configuration validation', function()
    it('should validate git_status_count as number', function()
      config.setup({ git_status_count = "invalid" })
      local result = config.get()
      
      assert.is_nil(result.git_status_count)
    end)
    
    it('should validate git_status_count minimum value', function()
      config.setup({ git_status_count = 0 })
      local result = config.get()
      
      assert.is_nil(result.git_status_count)
    end)
    
    it('should round git_status_count to integer', function()
      config.setup({ git_status_count = 5.7 })
      local result = config.get()
      
      assert.equals(5, result.git_status_count)
    end)
    
    it('should validate section_order as table', function()
      config.setup({ section_order = "invalid" })
      local result = config.get()
      
      -- Should fall back to default
      assert.are.same({
        "dashboard_buttons",
        "keyboard_shortcuts",
        "recent_commits", 
        "git_status",
        "claude_conversations"
      }, result.section_order)
    end)
    
    it('should filter invalid sections from section_order', function()
      config.setup({ 
        section_order = {
          "dashboard_buttons",
          "invalid_section",
          "git_status",
          123,  -- invalid type
          "recent_commits"
        }
      })
      local result = config.get()
      
      assert.are.same({
        "dashboard_buttons",
        "git_status", 
        "recent_commits"
      }, result.section_order)
    end)
    
    it('should validate logo_selection values', function()
      config.setup({ logo_selection = "invalid_logo" })
      local result = config.get()
      
      assert.equals("nexus", result.logo_selection)
    end)
    
    it('should accept valid logo_selection values', function()
      config.setup({ logo_selection = "image" })
      local result = config.get()
      
      assert.equals("image", result.logo_selection)
    end)
    
    it('should validate logo_color as string', function()
      config.setup({ logo_color = 123 })
      local result = config.get()
      
      assert.equals("String", result.logo_color)
    end)
    
    it('should not accept empty logo_color', function()
      config.setup({ logo_color = "" })
      local result = config.get()
      
      assert.equals("String", result.logo_color)
    end)
    
    it('should validate boolean options', function()
      config.setup({ 
        open_on_startup = "true",  -- invalid type
        keep_open_after_startup = 1  -- invalid type
      })
      local result = config.get()
      
      assert.is_true(result.open_on_startup)  -- should default to true
      assert.is_false(result.keep_open_after_startup)  -- should default to false
    end)
  end)
  
  describe('backward compatibility', function()
    it('should convert use_image_logo = true to logo_selection = "image"', function()
      config.setup({ use_image_logo = true })
      local result = config.get()
      
      assert.equals("image", result.logo_selection)
      assert.is_nil(result.use_image_logo)
    end)
    
    it('should convert use_image_logo = false to logo_selection = "neovim"', function()
      config.setup({ use_image_logo = false })
      local result = config.get()
      
      assert.equals("neovim", result.logo_selection)
      assert.is_nil(result.use_image_logo)
    end)
    
    it('should convert use_image_logo string to logo_selection', function()
      config.setup({ use_image_logo = "nexus" })
      local result = config.get()
      
      assert.equals("nexus", result.logo_selection)
      assert.is_nil(result.use_image_logo)
    end)
    
    it('should handle invalid use_image_logo values', function()
      config.setup({ use_image_logo = "invalid_value" })
      local result = config.get()
      
      assert.equals("nexus", result.logo_selection)
      assert.is_nil(result.use_image_logo)
    end)
  end)
  
  describe('user configuration merging', function()
    it('should merge user config with defaults', function()
      config.setup({
        show_dashboard_buttons = false,
        recent_commits_count = 5,
        custom_option = "test"
      })
      local result = config.get()
      
      assert.is_false(result.show_dashboard_buttons)  -- overridden
      assert.equals(5, result.recent_commits_count)  -- overridden
      assert.is_true(result.show_git_status)  -- default preserved
      assert.equals("test", result.custom_option)  -- custom option added
    end)
    
    it('should handle deep merging of nested options', function()
      config.setup({
        section_order = {"git_status", "recent_commits"}
      })
      local result = config.get()
      
      assert.are.same({"git_status", "recent_commits"}, result.section_order)
      assert.is_true(result.show_dashboard_buttons)  -- other options preserved
    end)
  end)
end)