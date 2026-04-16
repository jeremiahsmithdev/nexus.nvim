local M = {}

-- State store
local state = {
  git = {},
  ui = {},
  cache = {},
  linear = {}
}

-- Get state for a specific domain
function M.get(domain, key)
  if not state[domain] then
    return nil
  end
  
  if key then
    return state[domain][key]
  end
  
  return state[domain]
end

-- Set state for a specific domain
function M.set(domain, key, value)
  if not state[domain] then
    state[domain] = {}
  end
  
  state[domain][key] = value
end

-- Update state for a domain (merge objects)
function M.update(domain, updates)
  if not state[domain] then
    state[domain] = {}
  end
  
  for key, value in pairs(updates) do
    M.set(domain, key, value)
  end
end

-- Clear all state
function M.clear(domain)
  if domain then
    state[domain] = {}
  else
    state = { git = {}, ui = {}, cache = {}, linear = {} }
  end
end

-- Get all state (for debugging)
function M.get_all()
  return vim.deepcopy(state)
end

-- State validation
function M.validate_state()
  local errors = {}
  
  -- Validate git state structure
  if state.git and state.git.files then
    if type(state.git.files) ~= "table" then
      table.insert(errors, "git.files must be a table")
    end
  end
  
  -- Validate UI state structure  
  if state.ui and state.ui.section_ranges then
    if type(state.ui.section_ranges) ~= "table" then
      table.insert(errors, "ui.section_ranges must be a table")
    end
  end
  
  return #errors == 0, errors
end

-- Initialize state with defaults
function M.init()
  state = {
    git = {
      files = {},
      commits = {},
      is_git_repo = false,
      git_root = nil
    },
    ui = {
      section_ranges = {},
      current_section = "unknown",
      config = {}
    },
    cache = {
      git_status_timestamp = 0,
      git_commits_timestamp = 0,
      ttl = {
        git_status = 30,  -- 30 seconds
        git_commits = 300 -- 5 minutes
      }
    },
    linear = {
      issues = {},
      user_info = nil,
      teams = {},
      loading = false,
      error = nil,
      last_sync = nil,
      enabled = false
    }
  }
end

-- Initialize on module load
M.init()

return M