local M = {}

local shortcuts = require('nexus.ui.shortcuts')

-- Set up dynamic shortcut updating on cursor movement
function M.setup_dynamic_shortcuts(buf, config, is_git_repo, section_ranges)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  
  -- Clear any existing autocommands for this buffer
  vim.api.nvim_clear_autocmds({
    group = vim.api.nvim_create_augroup("nexus_dynamic_shortcuts_" .. buf, { clear = true }),
    buffer = buf,
  })
  
  -- Set up autocommand to update shortcuts on cursor movement
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = vim.api.nvim_create_augroup("nexus_dynamic_shortcuts_" .. buf, { clear = false }),
    buffer = buf,
    callback = function()
      -- Only update if we're still in the correct buffer
      if vim.api.nvim_get_current_buf() == buf then
        shortcuts.update_contextual_shortcuts(buf, config, is_git_repo, section_ranges)
        
        -- Re-apply highlighting to the updated line
        local highlighting = require('nexus.render.components.highlighting')
        highlighting.apply_shortcuts_highlighting(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false), config, section_ranges)
      end
    end,
  })
  
  -- Initial update of contextual shortcuts
  shortcuts.update_contextual_shortcuts(buf, config, is_git_repo, section_ranges)
end

return M