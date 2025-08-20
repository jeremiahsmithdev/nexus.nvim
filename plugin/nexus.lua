if vim.g.loaded_nexus then
  return
end
vim.g.loaded_nexus = 1

-- Set up global keymaps for dashboard shortcuts
require('nexus.global_keymaps').setup()

vim.api.nvim_create_user_command('Nexus', function()
  require('nexus').open(true)  -- Pass true to indicate manual open
end, {
  desc = 'Open Nexus dashboard'
})

-- Auto-open Nexus on startup if no files are opened
vim.api.nvim_create_autocmd('VimEnter', {
  callback = function()
    -- Only open if no files were passed as arguments
    if vim.fn.argc() == 0 then
      -- Check if we're in a git repository
      local git_check = vim.fn.system('git rev-parse --is-inside-work-tree 2>/dev/null')
      if vim.v.shell_error == 0 and git_check:match('true') then
        require('nexus').open(false)  -- Pass false to indicate auto-open
      end
    end
  end,
  desc = 'Open Nexus on startup if no files specified and in git repo'
})