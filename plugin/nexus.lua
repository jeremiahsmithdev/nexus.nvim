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

    -- Async git repo check — does not block the main thread
    vim.system({ 'git', 'rev-parse', '--is-inside-work-tree' }, { text = true }, function(obj)
      if obj.code == 0 and (obj.stdout or ''):match('true') then
        vim.schedule(function()
          require('nexus').open(false)  -- Pass false to indicate auto-open
        end)
      end
    end)
  end,
  desc = 'Open Nexus on startup if configured and no files specified and in git repo'
})