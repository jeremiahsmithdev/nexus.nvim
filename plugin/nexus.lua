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

-- Auto-open Nexus on startup if configured and no files are opened
vim.api.nvim_create_autocmd('VimEnter', {
  callback = function()
    -- Get config to check if startup is enabled
    local config = require('nexus.config').get()
    
    -- Only open if startup is enabled and no files were passed as arguments
    if config.open_on_startup and vim.fn.argc() == 0 then
      -- Check if we're in a git repository
      local git_check = vim.fn.system('git rev-parse --is-inside-work-tree 2>/dev/null')
      if vim.v.shell_error == 0 and git_check:match('true') then
        require('nexus').open(false)  -- Pass false to indicate auto-open
      end
    end
  end,
  desc = 'Open Nexus on startup if configured and no files specified and in git repo'
})