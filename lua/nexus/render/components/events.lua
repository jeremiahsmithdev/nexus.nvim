local M = {}

local shortcuts = require('nexus.ui.shortcuts')
local highlighting = require('nexus.render.components.highlighting')

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

        -- Re-apply highlighting to the updated line. apply_shortcuts_highlighting
        -- only touches lines inside the keyboard_shortcuts range and indexes them
        -- by ABSOLUTE line number, so we fetch just that range (typically 2 lines)
        -- rather than marshalling the entire buffer to Lua on every cursor move.
        local sr = section_ranges and section_ranges.keyboard_shortcuts
        local lines
        if sr then
          local segment = vim.api.nvim_buf_get_lines(buf, sr.start_line - 1, sr.end_line, false)
          lines = {}
          for offset, content in ipairs(segment) do
            lines[sr.start_line + offset - 1] = content
          end
        else
          lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        end
        highlighting.apply_shortcuts_highlighting(buf, lines, config, section_ranges)
      end
    end,
  })
  
  -- Initial update of contextual shortcuts
  shortcuts.update_contextual_shortcuts(buf, config, is_git_repo, section_ranges)
end

return M