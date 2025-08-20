-- Unit tests for nexus.logger module

local mocks = require('tests.helpers.mocks')

describe('nexus.logger', function()
  local logger
  local original_io_open
  local mock_file_operations = {}
  
  before_each(function()
    -- Reset module cache
    package.loaded['nexus.logger'] = nil
    
    -- Set up specific mocks we need WITHOUT mocking the logger itself
    -- (since we're testing the logger)
    mocks.mock_tmux_env(false)  -- Not in tmux for most tests
    
    -- Mock file operations
    original_io_open = io.open
    io.open = function(path, mode)
      if not mock_file_operations[path] then
        mock_file_operations[path] = {
          content = "",
          writes = {}
        }
      end
      
      -- Handle "w" mode (write/overwrite) vs "a" mode (append)
      if mode == "w" then
        mock_file_operations[path] = {
          content = "",
          writes = {}
        }
      end
      
      return {
        write = function(self, data)
          if mode == "w" or not mock_file_operations[path] then
            mock_file_operations[path].content = data
          else
            mock_file_operations[path].content = mock_file_operations[path].content .. data
          end
          table.insert(mock_file_operations[path].writes, data)
          return self
        end,
        close = function() end
      }
    end
    
    logger = require('nexus.logger')
  end)
  
  after_each(function()
    io.open = original_io_open
    mock_file_operations = {}
    -- Only restore vim.fn.system and vim.env that we mocked for tmux
    if mocks._original.vim_fn_system then
      vim.fn.system = mocks._original.vim_fn_system
    end
    if mocks._original.vim_v then
      vim.v = mocks._original.vim_v
    end
    vim.env.TMUX = nil
  end)
  
  describe('logging levels', function()
    it('should log info messages', function()
      logger.info("TEST", "Test info message")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("INFO", log_content)
      assert.matches("TEST", log_content)
      assert.matches("Test info message", log_content)
    end)
    
    it('should log debug messages', function()
      logger.debug("TEST", "Test debug message")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("DEBUG", log_content)
      assert.matches("TEST", log_content)
      assert.matches("Test debug message", log_content)
    end)
    
    it('should log warning messages', function()
      logger.warn("TEST", "Test warning message")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("WARN", log_content)
      assert.matches("TEST", log_content)
      assert.matches("Test warning message", log_content)
    end)
    
    it('should log error messages', function()
      logger.error("TEST", "Test error message")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("ERROR", log_content)
      assert.matches("TEST", log_content)
      assert.matches("Test error message", log_content)
    end)
  end)
  
  describe('log format', function()
    it('should include timestamp in log entries', function()
      logger.info("TEST", "Test message")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      -- Should match pattern: [YYYY-MM-DD HH:MM:SS]
      assert.matches("%[%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d%]", log_content)
    end)
    
    it('should include PID in log entries', function()
      logger.info("TEST", "Test message")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("%[PID:%d+%]", log_content)
    end)
    
    it('should include tmux context when not in tmux', function()
      logger.info("TEST", "Test message")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("NOT_IN_TMUX", log_content)
    end)
    
    it('should include extra data when provided', function()
      logger.info("TEST", "Test message", {key = "value", number = 42})
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("key.*value", log_content)
      assert.matches("number.*42", log_content)
    end)
  end)
  
  describe('tmux context', function()
    it('should include tmux window and pane info when available', function()
      -- Reset and setup with tmux environment
      package.loaded['nexus.logger'] = nil
      
      -- Temporarily disable the logger before setting up tmux mock
      if mocks._original.vim_fn_system then
        vim.fn.system = mocks._original.vim_fn_system
      end
      if mocks._original.vim_v then
        vim.v = mocks._original.vim_v
      end
      
      -- Set up tmux environment (this will mock vim.fn.system and vim.v)
      mocks.mock_tmux_env(true, {
        pane_id = '%0', 
        window_id = '@1'
      })
      
      -- Re-setup io.open mock after tmux setup
      mock_file_operations = {}
      io.open = function(path, mode)
        if not mock_file_operations[path] then
          mock_file_operations[path] = {
            content = "",
            writes = {}
          }
        end
        
        -- Handle "w" mode (write/overwrite) vs "a" mode (append)
        if mode == "w" then
          mock_file_operations[path] = {
            content = "",
            writes = {}
          }
        end
        
        return {
          write = function(self, data)
            if mode == "w" or not mock_file_operations[path] then
              mock_file_operations[path].content = data
            else
              mock_file_operations[path].content = mock_file_operations[path].content .. data
            end
            table.insert(mock_file_operations[path].writes, data)
            return self
          end,
          close = function() end
        }
      end
      
      logger = require('nexus.logger')
      logger.info("TEST", "Test message")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("W:@1", log_content)
      assert.matches("P:%%0", log_content)
    end)
  end)
  
  describe('specialized logging functions', function()
    it('should log navigation away events', function()
      logger.nav_away(123, "win1", "pane1", "win2", "pane2")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("NAVIGATION", log_content)
      assert.matches("Navigate AWAY", log_content)
      assert.matches("buffer 123", log_content)
    end)
    
    it('should log navigation back events', function()
      logger.nav_back(123, "win1", "pane1", "win2", "pane2")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("NAVIGATION", log_content)
      assert.matches("Navigate BACK", log_content)
      assert.matches("buffer 123", log_content)
    end)
    
    it('should log buffer creation events', function()
      logger.buf_created(123, "window", "pane")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("BUFFER", log_content)
      assert.matches("Buffer 123 created", log_content)
      assert.matches("window|pane", log_content)
    end)
    
    it('should log image render attempts', function()
      logger.image_render_attempt(123, true, false, true)
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("IMAGE", log_content)
      assert.matches("Render attempt", log_content)
      assert.matches("buffer 123", log_content)
      assert.matches("should_show=true", log_content)
      assert.matches("has_image=false", log_content)
      assert.matches("config=true", log_content)
    end)
  end)
  
  describe('log management', function()
    it('should clear log file', function()
      logger.info("TEST", "First message")
      
      -- Verify first message was logged
      local log_content_before = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("First message", log_content_before)
      
      -- Clear the log and add a new message
      logger.clear_log()
      logger.info("SYSTEM", "Log file cleared")
      
      -- Check that file content was reset and contains new message
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("Log file cleared", log_content)
      -- But not the first message
      assert.not_matches("First message", log_content)
    end)
    
    it('should return correct log file path', function()
      assert.equals("/tmp/nexus-debug.log", logger.get_log_file())
    end)
    
    it('should initialize logger on init()', function()
      logger.init()
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("SYSTEM", log_content)
      assert.matches("Nexus logger initialized", log_content)
    end)
  end)
  
  describe('console output configuration', function()
    it('should allow enabling console output', function()
      -- This is more of a functional test - just ensure no errors
      logger.set_console_output(true)
      logger.info("TEST", "Console message")
      
      -- Should still write to file
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("Console message", log_content)
    end)
    
    it('should allow disabling console output', function()
      logger.set_console_output(false)
      logger.info("TEST", "File only message")
      
      local log_content = mock_file_operations["/tmp/nexus-debug.log"].content
      assert.matches("File only message", log_content)
    end)
  end)
end)