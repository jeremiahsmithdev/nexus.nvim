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
    -- screen, otherwise the intro flashes before Nexus takes over. We keep the
    -- timing synchronous but answer the "in a git repo?" question with a
    -- subprocess-free fs_stat walk (sub-millisecond) instead of spawning a
    -- `git rev-parse` process (~10-30ms) on the critical pre-paint path.
    if require('nexus.git.root').is_repo() then
      require('nexus').open(false)  -- Pass false to indicate auto-open
    end
  end,
  desc = 'Open Nexus on startup if configured and no files specified and in git repo'
})