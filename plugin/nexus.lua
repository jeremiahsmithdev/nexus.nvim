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
    if not config.open_on_startup or vim.fn.argc() ~= 0 then return end

    -- Synchronous git check. Must finish before Vim paints the default intro
    -- screen, otherwise the intro flashes before Nexus takes over. The cost is
    -- ~10-30ms of startup blocking, which is invisible; the flash is very visible.
    local result = vim.fn.system('git rev-parse --is-inside-work-tree 2>/dev/null')
    if vim.v.shell_error == 0 and result:match('true') then
      require('nexus').open(false)  -- Pass false to indicate auto-open
    end
  end,
  desc = 'Open Nexus on startup if configured and no files specified and in git repo'
})