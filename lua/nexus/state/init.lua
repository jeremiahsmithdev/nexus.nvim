local M = {}

-- State store
local state = {
  git = {},
  ui = {},
  cache = {}
}

-- Observer pattern - subscribers to state changes
local observers = {
  git = {},
  ui = {},
  cache = {}
}

-- State change event types
M.EVENTS = {
  GIT_STATUS_UPDATED = 'git_status_updated',
  GIT_COMMITS_UPDATED = 'git_commits_updated',
  UI_SECTION_RANGES_UPDATED = 'ui_section_ranges_updated',
  UI_CONFIG_UPDATED = 'ui_config_updated',
  CACHE_INVALIDATED = 'cache_invalidated',
  CACHE_UPDATED = 'cache_updated'
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
  
  local old_value = state[domain][key]
  state[domain][key] = value
  
  -- Notify observers if value changed
  if old_value ~= value then
    M.notify(domain, key, value, old_value)
  end
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

-- Subscribe to state changes
function M.subscribe(domain, callback)
  if not observers[domain] then
    observers[domain] = {}
  end
  
  table.insert(observers[domain], callback)
  
  -- Return unsubscribe function
  return function()
    for i, obs in ipairs(observers[domain]) do
      if obs == callback then
        table.remove(observers[domain], i)
        break
      end
    end
  end
end

-- Notify observers of state changes
function M.notify(domain, key, new_value, old_value)
  if not observers[domain] then
    return
  end
  
  local event = {
    domain = domain,
    key = key,
    new_value = new_value,
    old_value = old_value,
    timestamp = os.time()
  }
  
  for _, callback in ipairs(observers[domain]) do
    pcall(callback, event)
  end
end

-- Clear all state
function M.clear(domain)
  if domain then
    state[domain] = {}
    M.notify(domain, '_cleared', {}, nil)
  else
    state = { git = {}, ui = {}, cache = {} }
    for d, _ in pairs(observers) do
      M.notify(d, '_cleared', {}, nil)
    end
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
    }
  }
end

-- Initialize on module load
M.init()

return M