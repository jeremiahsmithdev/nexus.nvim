-- Minimal init file for testing
-- This sets up the minimal environment needed to test Nexus.nvim

-- Add current directory to runtimepath for testing
vim.opt.rtp:prepend(vim.fn.expand('%:p:h:h'))

-- Add plenary for test framework
local plenary_path = vim.fn.stdpath('data') .. '/lazy/plenary.nvim'
if vim.fn.isdirectory(plenary_path) == 0 then
  -- Try common plugin manager paths
  local paths = {
    vim.fn.stdpath('data') .. '/site/pack/packer/start/plenary.nvim',
    vim.fn.expand('~/.local/share/nvim/site/pack/packer/start/plenary.nvim'),
    vim.fn.expand('~/.config/nvim/pack/plugins/start/plenary.nvim'),
  }
  
  for _, path in ipairs(paths) do
    if vim.fn.isdirectory(path) == 1 then
      plenary_path = path
      break
    end
  end
end

if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.rtp:prepend(plenary_path)
else
  error('plenary.nvim not found. Please install it first: git clone https://github.com/nvim-lua/plenary.nvim.git ' .. vim.fn.stdpath('data') .. '/lazy/plenary.nvim')
end

-- Disable swap files and other settings that might interfere with testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.undofile = false

-- Set shorter timeouts for faster tests
vim.opt.updatetime = 10
vim.opt.timeoutlen = 100

-- Mock some common globals that might be expected
vim.g.mapleader = ' '
vim.g.maplocalleader = ','