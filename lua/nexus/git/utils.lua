local M = {}

function M.is_git_repo()
  local git_check = vim.fn.system('git rev-parse --is-inside-work-tree 2>/dev/null')
  return vim.v.shell_error == 0 and git_check:match('true')
end

function M.get_git_root()
  if not M.is_git_repo() then
    return nil
  end
  
  local git_root = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')[1]
  return git_root
end

return M