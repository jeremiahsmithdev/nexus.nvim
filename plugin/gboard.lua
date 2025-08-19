if vim.g.loaded_gboard then
  return
end
vim.g.loaded_gboard = 1

vim.api.nvim_create_user_command('GBoard', function()
  require('gboard').open(true)  -- Pass true to indicate manual open
end, {
  desc = 'Open GBoard dashboard'
})

-- Auto-open GBoard on startup if no files are opened
vim.api.nvim_create_autocmd('VimEnter', {
  callback = function()
    -- Only open if no files were passed as arguments
    if vim.fn.argc() == 0 then
      -- Check if we're in a git repository
      local git_check = vim.fn.system('git rev-parse --is-inside-work-tree 2>/dev/null')
      if vim.v.shell_error == 0 and git_check:match('true') then
        require('gboard').open(false)  -- Pass false to indicate auto-open
      end
    end
  end,
  desc = 'Open GBoard on startup if no files specified and in git repo'
})