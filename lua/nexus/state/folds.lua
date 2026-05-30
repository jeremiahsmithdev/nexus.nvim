local M = {}

local logger = require('nexus.logger')

-- Cache directory for fold state
local CACHE_DIR = vim.fn.expand('~/.cache/nexus')
local STATE_FILE = CACHE_DIR .. '/fold_state.json'

-- In-memory cache
local fold_state_cache = nil

-- Ensure cache directory exists
local function ensure_cache_dir()
  if vim.fn.isdirectory(CACHE_DIR) == 0 then
    vim.fn.mkdir(CACHE_DIR, 'p')
  end
end

-- Get repository path for state key
local function get_repo_path()
  local git_state = require('nexus.state.git')
  return git_state.get_git_root() or vim.fn.getcwd()
end

-- Load fold state from disk
local function load_state_from_disk()
  ensure_cache_dir()

  if vim.fn.filereadable(STATE_FILE) == 0 then
    return {}
  end

  local success, content = pcall(vim.fn.readfile, STATE_FILE)
  if not success then
    logger.warn("FOLD_STATE", "Failed to read fold state file", { error = content })
    return {}
  end

  local json_str = table.concat(content, '\n')
  if json_str == '' then
    return {}
  end

  success, state = pcall(vim.fn.json_decode, json_str)
  if not success then
    logger.warn("FOLD_STATE", "Failed to parse fold state JSON", { error = state })
    return {}
  end

  return state or {}
end

-- Save fold state to disk
local function save_state_to_disk(state)
  ensure_cache_dir()

  local success, json_str = pcall(vim.fn.json_encode, state)
  if not success then
    logger.error("FOLD_STATE", "Failed to encode fold state to JSON", { error = json_str })
    return false
  end

  success, result = pcall(vim.fn.writefile, {json_str}, STATE_FILE)
  if not success then
    logger.error("FOLD_STATE", "Failed to write fold state file", { error = result })
    return false
  end

  return true
end

-- Get fold state for current repository
function M.get_repo_state()
  if not fold_state_cache then
    fold_state_cache = load_state_from_disk()
  end

  local repo_path = get_repo_path()
  return fold_state_cache[repo_path] or {}
end

-- Get fold state for a specific section
-- Returns true if section should be open (default is open)
function M.is_section_open(section_name)
  local repo_state = M.get_repo_state()

  -- Default to open if no state exists
  if repo_state[section_name] == nil then
    return true
  end

  return repo_state[section_name] == "open"
end

-- Set fold state for a specific section
function M.set_section_state(section_name, is_open)
  if not fold_state_cache then
    fold_state_cache = load_state_from_disk()
  end

  local repo_path = get_repo_path()

  if not fold_state_cache[repo_path] then
    fold_state_cache[repo_path] = {}
  end

  fold_state_cache[repo_path][section_name] = is_open and "open" or "closed"

  -- Save to disk
  save_state_to_disk(fold_state_cache)

  logger.debug("FOLD_STATE", "Updated section state", {
    repo = repo_path,
    section = section_name,
    state = is_open and "open" or "closed"
  })
end

-- Toggle fold state for a specific section
function M.toggle_section_state(section_name)
  local current_state = M.is_section_open(section_name)
  M.set_section_state(section_name, not current_state)
  return not current_state
end

-- Clear fold state for current repository (reset to defaults)
function M.clear_repo_state()
  if not fold_state_cache then
    fold_state_cache = load_state_from_disk()
  end

  local repo_path = get_repo_path()
  fold_state_cache[repo_path] = {}

  save_state_to_disk(fold_state_cache)

  logger.info("FOLD_STATE", "Cleared fold state for repository", { repo = repo_path })
end

-- Initialize fold state system
function M.init()
  fold_state_cache = nil -- Clear cache
  logger.debug("FOLD_STATE", "Initialized fold state system")
end

return M
