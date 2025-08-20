-- Unit tests for nexus.ui.logo module

local mocks = require('tests.helpers.mocks')

describe('nexus.ui.logo', function()
  local logo
  
  before_each(function()
    -- Reset module cache
    package.loaded['nexus.ui.logo'] = nil
    package.loaded['nexus.logger'] = nil
    
    mocks.setup_test_environment()
    logo = require('nexus.ui.logo')
  end)
  
  after_each(function()
    mocks.restore_all()
  end)
  
  describe('get_neovim_logo', function()
    it('should return nexus logo by default', function()
      local config = { logo_selection = "nexus" }
      local result = logo.get_neovim_logo(config)
      
      assert.is_table(result)
      assert.is_true(#result > 0)
      
      -- Should contain NEXUS ASCII art
      local logo_text = table.concat(result, '\n')
      assert.matches('NEXUS', logo_text)
      assert.matches('Developer.*Mission.*Control', logo_text)
    end)
    
    it('should return neovim logo when specified', function()
      local config = { logo_selection = "neovim" }
      local result = logo.get_neovim_logo(config)
      
      assert.is_table(result)
      assert.is_true(#result > 0)
      
      -- Should contain neovim ASCII pattern
      local logo_text = table.concat(result, '\n')
      assert.matches('neovim', logo_text)
    end)
    
    it('should handle image logo selection', function()
      local config = { 
        logo_selection = "image",
        image_logo_height = 6
      }
      
      local result = logo.get_neovim_logo(config)
      
      assert.is_table(result)
      assert.equals(7, #result)  -- height + 1 for spacing
      
      -- Should be empty lines (placeholders for image)
      for _, line in ipairs(result) do
        assert.equals('', line)
      end
    end)
    
    it('should fall back to nexus logo for invalid selection', function()
      local config = { logo_selection = "invalid" }
      local result = logo.get_neovim_logo(config)
      
      local logo_text = table.concat(result, '\n')
      assert.matches('NEXUS', logo_text)
    end)
  end)
  
  describe('backward compatibility', function()
    it('should handle use_image_logo = true', function()
      local config = { 
        use_image_logo = true,
        image_logo_height = 4
      }
      
      local result = logo.get_neovim_logo(config)
      
      -- Should return image placeholder
      assert.equals(5, #result)  -- height + 1
      for _, line in ipairs(result) do
        assert.equals('', line)
      end
    end)
    
    it('should handle use_image_logo = false', function()
      local config = { use_image_logo = false }
      local result = logo.get_neovim_logo(config)
      
      local logo_text = table.concat(result, '\n')
      assert.matches('neovim', logo_text)
    end)
    
    it('should handle use_image_logo string values', function()
      local config = { use_image_logo = "nexus" }
      local result = logo.get_neovim_logo(config)
      
      local logo_text = table.concat(result, '\n')
      assert.matches('NEXUS', logo_text)
    end)
  end)
  
  describe('get_ascii_logo', function()
    it('should return neovim ASCII art', function()
      local result = logo.get_ascii_logo()
      
      assert.is_table(result)
      assert.is_true(#result > 0)
      
      local logo_text = table.concat(result, '\n')
      assert.matches('neovim', logo_text)
      
      -- Should have empty line at end for spacing
      assert.equals('', result[#result])
    end)
  end)
  
  describe('get_nexus_ascii_logo', function()
    it('should return NEXUS ASCII art', function()
      local result = logo.get_nexus_ascii_logo()
      
      assert.is_table(result)
      assert.is_true(#result > 0)
      
      local logo_text = table.concat(result, '\n')
      assert.matches('NEXUS', logo_text)
      assert.matches('Developer.*Mission.*Control', logo_text)
      
      -- Should have empty lines for spacing
      assert.equals('', result[#result])
    end)
    
    it('should contain proper box drawing characters', function()
      local result = logo.get_nexus_ascii_logo()
      local logo_text = table.concat(result, '\n')
      
      -- Should contain Unicode box drawing characters
      assert.matches('███', logo_text)
      assert.matches('╗', logo_text)
      assert.matches('║', logo_text)
    end)
  end)
  
  describe('get_image_logo', function()
    it('should return placeholder lines for valid image config', function()
      local config = {
        image_logo_height = 8,
        image_logo_path = '/valid/path/logo.png'
      }
      
      -- Mock file as readable
      mocks.mock_filesystem({
        ['/valid/path/logo.png'] = { readable = true }
      })
      
      local result = logo.get_image_logo(config)
      
      assert.is_table(result)
      assert.equals(9, #result)  -- height + 1 for spacing
      
      for _, line in ipairs(result) do
        assert.equals('', line)
      end
    end)
    
    it('should fall back to ASCII when image.nvim not available', function()
      -- Mock missing image.nvim
      package.loaded['image'] = nil
      
      local config = { 
        image_logo_height = 6,
        image_logo_path = '/valid/path/logo.png'
      }
      
      local result = logo.get_image_logo(config)
      
      -- Should fall back to ASCII logo
      local logo_text = table.concat(result, '\n')
      assert.matches('neovim', logo_text)
    end)
    
    it('should fall back to ASCII when image file not found', function()
      local config = {
        image_logo_path = '/nonexistent/path/logo.png'
      }
      
      mocks.mock_filesystem({
        ['/nonexistent/path/logo.png'] = { readable = false }
      })
      
      local result = logo.get_image_logo(config)
      
      -- Should fall back to ASCII logo
      local logo_text = table.concat(result, '\n')
      assert.matches('neovim', logo_text)
    end)
    
    it('should use default image path when not specified', function()
      local config = { image_logo_height = 4 }
      
      -- The function will try to determine plugin path and use assets/neovim.png
      -- Since we can't easily mock the debug.getinfo call, we expect fallback
      local result = logo.get_image_logo(config)
      
      -- Should either return placeholder or fallback to ASCII
      assert.is_table(result)
      assert.is_true(#result > 0)
    end)
  end)
  
  describe('tmux integration', function()
    it('should get tmux pane info when in tmux', function()
      mocks.setup_test_environment({
        tmux = {
          id = '%0',
          width = 100,
          height = 30
        }
      })
      
      -- Test internal function via should_show_image_in_current_pane
      local result = logo.should_show_image_in_current_pane()
      
      assert.is_boolean(result)
    end)
    
    it('should allow image when not in tmux', function()
      mocks.setup_test_environment({ tmux = false })
      
      local result = logo.should_show_image_in_current_pane()
      
      assert.is_true(result)
    end)
  end)
  
  describe('image rendering', function()
    it('should not render when logo_selection is not image', function()
      local config = { logo_selection = "nexus" }
      local buf = 1
      
      local result = logo.render_image_logo(buf, config, 0, 0)
      
      assert.is_false(result)
    end)
    
    it('should not render when image.nvim not available', function()
      package.loaded['image'] = nil
      
      local config = { logo_selection = "image" }
      local buf = 1
      
      local result = logo.render_image_logo(buf, config, 0, 0)
      
      assert.is_false(result)
    end)
    
    it('should handle buffer with insufficient lines', function()
      -- Mock image.nvim available
      package.loaded['image'] = {
        from_file = function() return nil end
      }
      
      local config = { logo_selection = "image" }
      local buf = 1
      
      vim.api.nvim_buf_line_count = function() return 1 end
      
      local result = logo.render_image_logo(buf, config, 0, 0)
      
      assert.is_false(result)
    end)
  end)
  
  describe('image management', function()
    it('should clean up image when requested', function()
      -- Set up mock current image state
      logo._current_image = {
        clear = function() end
      }
      logo._current_buffer = 1
      logo._current_tmux_pane = '%0'
      
      logo.cleanup_image()
      
      assert.is_nil(logo._current_image)
      assert.is_nil(logo._current_buffer)
      assert.is_nil(logo._current_tmux_pane)
    end)
    
    it('should check if has image for buffer correctly', function()
      logo._current_buffer = 1
      logo._current_image = { mock = true }
      logo._current_tmux_pane = '%0'
      
      mocks.setup_test_environment({
        tmux = { id = '%0' }
      })
      
      local result = logo.has_image_for_buffer(1)
      assert.is_true(result)
      
      local result2 = logo.has_image_for_buffer(2)
      assert.is_false(result2)
    end)
    
    it('should handle pane mismatch in has_image_for_buffer', function()
      logo._current_buffer = 1
      logo._current_image = { mock = true }
      logo._current_tmux_pane = '%0'
      
      mocks.setup_test_environment({
        tmux = { id = '%1' }  -- Different pane
      })
      
      local result = logo.has_image_for_buffer(1)
      assert.is_false(result)
    end)
  end)
  
  describe('edge cases', function()
    it('should handle nil config gracefully', function()
      local result = logo.get_neovim_logo(nil)
      
      -- Should default to nexus logo
      local logo_text = table.concat(result, '\n')
      assert.matches('NEXUS', logo_text)
    end)
    
    it('should handle empty config gracefully', function()
      local result = logo.get_neovim_logo({})
      
      -- Should default to nexus logo
      local logo_text = table.concat(result, '\n')
      assert.matches('NEXUS', logo_text)
    end)
  end)
end)