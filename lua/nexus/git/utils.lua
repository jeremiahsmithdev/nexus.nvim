local M = {}

local git_root_mod = require('nexus.git.root')

function M.is_git_repo()
  return git_root_mod.get() ~= nil
end

function M.get_git_root()
  return git_root_mod.get()
end

return M