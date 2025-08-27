---@class ClaudeKeymaps
local M = {}

local claude = require('nexus.claude')
local tmux = require('nexus.tmux')

--- Handle Enter key in Claude conversations section
function M.handle_enter(current_line, config)
  local conversations = claude.get_claude_conversations(config)
  local line_index = current_line:match("^ (%d+)%.")
  if line_index then
    local conv_index = tonumber(line_index)
    if conv_index and conversations[conv_index] then
      tmux.send_resume_to_claude(conversations[conv_index].session_id)
    end
  end
end

return M