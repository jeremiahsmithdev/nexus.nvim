local M = {}

-- Send /resume command to Claude via tmux (similar to diffusion.nvim approach)
function M.send_resume_to_claude(session_id)
  -- Check if we're in tmux
  if not vim.env.TMUX then
    print("Not in tmux environment")
    return false
  end
  
  -- Get current tmux context
  local current_session = vim.fn.system("tmux display-message -p '#S'"):gsub("\n", "")
  local current_window = vim.fn.system("tmux display-message -p '#I'"):gsub("\n", "")
  local current_pane = vim.fn.system("tmux display-message -p '#P'"):gsub("\n", "")
  
  -- Find Claude process in same window first
  local claude_pane = M.find_claude_in_window(current_session, current_window)
  if claude_pane then
    return M.send_resume_to_pane(current_session, current_window, claude_pane, session_id)
  end
  
  print("No Claude processes found in current tmux window")
  return false
end

-- Find Claude process in tmux window
function M.find_claude_in_window(session, window)
  local cmd = string.format("tmux list-panes -t %s:%s -F '#{pane_index} #{pane_current_command}' 2>/dev/null", session, window)
  local output = vim.fn.system(cmd)
  
  for line in output:gmatch("[^\r\n]+") do
    local pane_index, command = line:match("(%d+) (%S+)")
    if pane_index and command and (command:match("claude") or command:match("node")) then
      return pane_index
    end
  end
  
  return nil
end

-- Send /resume command to specific tmux pane
function M.send_resume_to_pane(session, window, pane, session_id)
  local target = session .. ":" .. window .. "." .. pane
  
  -- Clear any existing input with Ctrl-C
  local clear_cmd = string.format("tmux send-keys -t %s C-c", target)
  vim.fn.system(clear_cmd)
  vim.wait(50)
  
  -- Send /resume command with session ID
  local resume_cmd = string.format("tmux send-keys -t %s '/resume %s'", target, session_id)
  vim.fn.system(resume_cmd)
  vim.wait(100)
  
  -- Send Enter to submit command
  local enter_cmd = string.format("tmux send-keys -t %s Enter", target)
  vim.fn.system(enter_cmd)
  
  print("Sent /resume " .. session_id .. " to Claude")
  return true
end

return M