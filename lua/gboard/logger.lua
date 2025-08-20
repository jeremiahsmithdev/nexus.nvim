local M = {}

-- Logger configuration
local LOG_FILE = "/tmp/gboard-debug.log"
local LOG_ENABLED = true
local CONSOLE_OUTPUT = false  -- Set to true for console output during debugging

-- Get current timestamp
local function get_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

-- Get current tmux context
local function get_tmux_context()
  if not vim.env.TMUX then
    return "NOT_IN_TMUX", "NOT_IN_TMUX"
  end
  
  local window = vim.fn.system("tmux display-message -p '#{window_id}'"):gsub('\n', '')
  local pane = vim.fn.system("tmux display-message -p '#{pane_id}'"):gsub('\n', '')
  return window, pane
end

-- Core logging function
local function log(level, category, message, extra_data)
  if not LOG_ENABLED then
    return
  end
  
  local window, pane = get_tmux_context()
  local timestamp = get_timestamp()
  local pid = vim.fn.getpid()
  
  local log_entry = string.format(
    "[%s] [PID:%s] [%s] [%s] [W:%s|P:%s] %s",
    timestamp, pid, level, category, window, pane, message
  )
  
  if extra_data then
    log_entry = log_entry .. " | " .. vim.inspect(extra_data)
  end
  
  -- Write to file
  local file = io.open(LOG_FILE, "a")
  if file then
    file:write(log_entry .. "\n")
    file:close()
  end
  
  -- Optionally print to console for immediate feedback (disabled by default for performance)
  if CONSOLE_OUTPUT then
    print("[GBOARD] " .. message)
  end
end

-- Public logging functions
function M.info(category, message, data)
  log("INFO", category, message, data)
end

function M.debug(category, message, data)
  log("DEBUG", category, message, data)
end

function M.warn(category, message, data)
  log("WARN", category, message, data)
end

function M.error(category, message, data)
  log("ERROR", category, message, data)
end

-- Navigation tracking
function M.nav_away(buf, from_window, from_pane, to_window, to_pane)
  M.info("NAVIGATION", string.format(
    "Navigate AWAY from buffer %d: %s|%s -> %s|%s", 
    buf, from_window or "?", from_pane or "?", to_window or "?", to_pane or "?"
  ))
end

function M.nav_back(buf, from_window, from_pane, to_window, to_pane)
  M.info("NAVIGATION", string.format(
    "Navigate BACK to buffer %d: %s|%s -> %s|%s", 
    buf, from_window or "?", from_pane or "?", to_window or "?", to_pane or "?"
  ))
end

function M.nav_pane(buf, from_pane, to_pane)
  M.info("NAVIGATION", string.format(
    "Navigate between panes in buffer %d: %s -> %s", 
    buf, from_pane or "?", to_pane or "?"
  ))
end

-- Image operations
function M.image_render_attempt(buf, should_show, has_image, config_enabled)
  M.info("IMAGE", string.format(
    "Render attempt for buffer %d: should_show=%s, has_image=%s, config=%s", 
    buf, tostring(should_show), tostring(has_image), tostring(config_enabled)
  ))
end

function M.image_render_success(buf, pane)
  M.info("IMAGE", string.format("Render SUCCESS for buffer %d in pane %s", buf, pane or "?"))
end

function M.image_render_failure(buf, reason)
  M.warn("IMAGE", string.format("Render FAILED for buffer %d: %s", buf, reason))
end

function M.image_cleanup(buf, reason)
  M.info("IMAGE", string.format("Cleanup image for buffer %d: %s", buf or "?", reason))
end

-- Buffer events
function M.buf_created(buf, window, pane)
  M.info("BUFFER", string.format("Buffer %d created in %s|%s", buf, window or "?", pane or "?"))
end

function M.buf_enter(buf)
  M.info("BUFFER", string.format("BufEnter event for buffer %d", buf))
end

function M.buf_leave(buf)
  M.info("BUFFER", string.format("BufLeave event for buffer %d", buf))
end

function M.focus_lost(buf)
  M.info("BUFFER", string.format("FocusLost event for buffer %d", buf))
end

function M.focus_gained(buf)
  M.info("BUFFER", string.format("FocusGained event for buffer %d", buf))
end

-- Pane state tracking
function M.pane_check(current_pane, stored_pane, result)
  M.debug("PANE", string.format(
    "Pane check: current=%s, stored=%s, match=%s", 
    current_pane or "nil", stored_pane or "nil", tostring(result)
  ))
end

-- Clear log file
function M.clear_log()
  local file = io.open(LOG_FILE, "w")
  if file then
    file:write("")
    file:close()
  end
  M.info("SYSTEM", "Log file cleared")
end

-- Get log file path
function M.get_log_file()
  return LOG_FILE
end

-- Enable/disable console output
function M.set_console_output(enabled)
  CONSOLE_OUTPUT = enabled
end

-- Initialize logger
function M.init()
  M.clear_log()
  M.info("SYSTEM", "GBoard logger initialized")
end

return M