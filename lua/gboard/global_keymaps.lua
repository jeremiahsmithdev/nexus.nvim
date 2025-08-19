local M = {}

-- Set up global keymaps for the dashboard shortcuts
function M.setup()
  -- Find file (SPC f)
  vim.keymap.set('n', '<leader>f', function()
    if pcall(require, 'telescope') then
      vim.cmd('Telescope find_files')
    else
      vim.cmd('edit')
    end
  end, { desc = 'Find file' })
  
  -- Recently opened files (SPC r) 
  vim.keymap.set('n', '<leader>r', function()
    if pcall(require, 'telescope') then
      vim.cmd('Telescope oldfiles')
    else
      vim.cmd('browse oldfiles')
    end
  end, { desc = 'Recently opened files' })
  
  -- Find word (SPC w)
  vim.keymap.set('n', '<leader>w', function()
    if pcall(require, 'telescope') then
      vim.cmd('Telescope live_grep')
    else
      vim.ui.input({ prompt = 'Search for: ' }, function(input)
        if input then
          vim.cmd('grep ' .. input)
        end
      end)
    end
  end, { desc = 'Find word' })
  
  -- New file (SPC n)
  vim.keymap.set('n', '<leader>n', function()
    vim.cmd('enew')
  end, { desc = 'New file' })
  
  -- Bookmarks (SPC b)
  vim.keymap.set('n', '<leader>b', function()
    if pcall(require, 'telescope') then
      vim.cmd('Telescope marks')
    else
      vim.cmd('marks')
    end
  end, { desc = 'Bookmarks' })
  
  -- Restore session (SPC s)
  vim.keymap.set('n', '<leader>s', function()
    if vim.fn.filereadable('Session.vim') == 1 then
      vim.cmd('source Session.vim')
    else
      print('No session file found')
    end
  end, { desc = 'Restore session' })
end

return M