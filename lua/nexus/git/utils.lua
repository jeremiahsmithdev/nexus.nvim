local M = {}

local git_root_mod = require('nexus.git.root')

function M.is_git_repo()
  local git_check = vim.fn.system('git rev-parse --is-inside-work-tree 2>/dev/null')
  return vim.v.shell_error == 0 and git_check:match('true')
end

function M.get_git_root()
  return git_root_mod.get()
end

return M