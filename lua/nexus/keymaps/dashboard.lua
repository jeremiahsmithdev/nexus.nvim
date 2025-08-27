---@class DashboardKeymaps
local M = {}

local logger = require('nexus.logger')

--- Handle Enter key in dashboard section
function M.handle_enter(current_line, config)
  if current_line:match("Find file") then
    M.handle_action(config, 'Telescope find_files')
  elseif current_line:match("Recently opened files") then
    M.handle_action(config, 'Telescope oldfiles')
  elseif current_line:match("Find word") then
    M.handle_action(config, 'Telescope live_grep')
  elseif current_line:match("New file") then
    M.handle_action(config, 'enew')
  elseif current_line:match("Bookmarks") then
    M.handle_action(config, 'Telescope marks')
  elseif current_line:match("Restore session") then
    if vim.fn.filereadable('Session.vim') == 1 then
      M.handle_action(config, 'source Session.vim')
    else
      logger.warn('SESSION', 'No session file found')
    end
  end
end

--- Execute dashboard action and handle window management
function M.handle_action(config, command)
  logger.info('DASHBOARD', 'Executing action', { command = command })
  
  -- Remember if this is the only buffer
  local nexus_buf = vim.api.nvim_get_current_buf()
  local buf_list = vim.api.nvim_list_bufs()
  local other_bufs = vim.tbl_filter(function(buf)
    return vim.api.nvim_buf_is_valid(buf) and 
           vim.api.nvim_buf_get_option(buf, 'buflisted') and
           buf ~= nexus_buf
  end, buf_list)
  
  local should_close_nexus = #other_bufs == 0 and not config.keep_open_after_startup
  
  -- Execute the command
  local success, err = pcall(function()
    vim.cmd(command)
  end)
  
  if not success then
    logger.error('DASHBOARD', 'Failed to execute command', { 
      command = command, 
      error = err 
    })
    vim.notify("Failed to execute: " .. command, vim.log.levels.ERROR)
    return
  end
  
  -- Close Nexus buffer if configured and it's the only buffer
  if should_close_nexus then
    -- Use vim.schedule to ensure the new buffer is fully created first
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(nexus_buf) then
        vim.api.nvim_buf_delete(nexus_buf, { force = true })
      end
    end)
  end
end

return M