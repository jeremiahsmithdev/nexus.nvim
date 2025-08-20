# Module Organization

This guide covers the standard patterns for organizing Lua modules in Neovim plugins, based on established practices from high-quality plugins in the ecosystem.

## Standard Directory Structure

### Basic Plugin Structure
```
lua/
└── plugin-name/
    ├── init.lua              # Main entry point with setup()
    ├── config/
    │   ├── init.lua          # Core configuration
    │   ├── highlights.lua    # Highlight definitions
    │   └── defaults.lua      # Default options
    ├── core/                 # Core functionality
    │   ├── engine.lua        # Main processing logic
    │   ├── state.lua         # State management
    │   └── cache.lua         # Caching mechanisms
    ├── util/
    │   ├── init.lua          # Common utilities
    │   └── helpers.lua       # Helper functions
    ├── api.lua               # Public API
    ├── types.lua             # Type definitions
    └── health.lua            # Health check implementation
```

### Feature-Based Organization
For larger plugins, organize by feature modules:

```lua
-- snacks.nvim pattern
lua/snacks/
├── init.lua
├── animate/
│   ├── init.lua
│   └── easing.lua
├── picker/
│   ├── init.lua
│   ├── actions.lua
│   ├── config/
│   │   ├── init.lua
│   │   └── sources.lua
│   └── core/
│       ├── matcher.lua
│       └── finder.lua
└── terminal.lua          # Simple single-file features
```

## Module Initialization Patterns

### Main Entry Point (`init.lua`)

```lua
---@class PluginName
---@field config PluginConfig
local M = {}

-- Version and compatibility checks
if vim.fn.has("nvim-0.9.0") == 0 then
  vim.api.nvim_err_writeln("Plugin requires Neovim >= 0.9.0")
  return
end

-- Prevent double loading
if vim.g.loaded_plugin_name then
  return M
end
vim.g.loaded_plugin_name = true

---@type PluginConfig
M.config = {}

---@param opts? PluginConfig
function M.setup(opts)
  -- Merge user options with defaults
  M.config = vim.tbl_deep_extend("force", require("plugin-name.config").defaults, opts or {})
  
  -- Initialize core components
  require("plugin-name.core").init(M.config)
  
  -- Setup autocmds and user commands
  require("plugin-name.config").setup_autocmds()
  require("plugin-name.config").setup_commands()
end

-- Lazy-load API
return setmetatable(M, {
  __index = function(_, k)
    return require("plugin-name.api")[k]
  end,
})
```

### Configuration Module (`config/init.lua`)

```lua
---@class PluginConfig
---@field enabled boolean
---@field feature_option string
---@field nested_config NestedConfig

---@class NestedConfig
---@field sub_option boolean
---@field values string[]

local M = {}

---@type PluginConfig
M.defaults = {
  enabled = true,
  feature_option = "default",
  nested_config = {
    sub_option = false,
    values = {},
  },
}

-- Autocmd group for the plugin
M.augroup = vim.api.nvim_create_augroup("PluginName", { clear = true })

---Setup autocmds for the plugin
function M.setup_autocmds()
  vim.api.nvim_create_autocmd("BufEnter", {
    group = M.augroup,
    callback = function()
      -- Implementation
    end,
  })
end

---Setup user commands
function M.setup_commands()
  vim.api.nvim_create_user_command("PluginCommand", function(args)
    require("plugin-name.api").command_handler(args)
  end, {
    desc = "Plugin command description",
    nargs = "*",
    complete = "customlist,v:lua.require'plugin-name.completion'.complete",
  })
end

return M
```

### Core Module (`core/init.lua`)

```lua
---@class PluginCore
local M = {}

-- Internal state
---@type boolean
M._initialized = false

---@type table<string, any>
M._cache = {}

-- Namespace for highlights and marks
M.ns = vim.api.nvim_create_namespace("plugin-name")

---Initialize the core plugin functionality
---@param config PluginConfig
function M.init(config)
  if M._initialized then
    return
  end
  
  -- Store config reference
  M.config = config
  
  -- Initialize subsystems
  require("plugin-name.core.state").init(config)
  require("plugin-name.core.cache").init(config)
  
  M._initialized = true
end

---Get the current state
---@return table
function M.get_state()
  return require("plugin-name.core.state").get()
end

---Clean up resources
function M.cleanup()
  M._cache = {}
  vim.api.nvim_buf_clear_namespace(0, M.ns, 0, -1)
end

return M
```

## Modular Loading Strategies

### Lazy Module Loading

```lua
-- Deferred loading pattern
local Config = nil
local function get_config()
  if not Config then
    Config = require("plugin-name.config")
  end
  return Config
end

-- Conditional loading
local function load_optional_feature()
  local ok, feature = pcall(require, "plugin-name.optional-feature")
  if ok then
    return feature
  end
  return nil
end
```

### Dynamic Module Registration

```lua
-- snacks.nvim pattern for dynamic loading
local M = {}

-- Global registration
_G.PluginName = M

setmetatable(M, {
  __index = function(t, k)
    -- Auto-require modules
    local module = require("plugin-name." .. k)
    rawset(t, k, module)
    return module
  end,
})

return M
```

### Feature Toggle Pattern

```lua
-- Feature-based loading with toggles
local M = {}

local features = {
  "feature1",
  "feature2", 
  "feature3",
}

---@param config PluginConfig
function M.load_features(config)
  for _, feature in ipairs(features) do
    if config.features[feature] then
      local ok, module = pcall(require, "plugin-name.features." .. feature)
      if ok then
        module.setup(config.features[feature])
      else
        vim.notify("Failed to load feature: " .. feature, vim.log.levels.WARN)
      end
    end
  end
end

return M
```

## File Naming Conventions

### Module Files
- **init.lua**: Main module entry point
- **config.lua** or **config/init.lua**: Configuration handling
- **types.lua**: Type definitions and annotations
- **util.lua** or **util/init.lua**: Utility functions
- **health.lua**: Health check implementation

### Feature Files
- Use descriptive names: `terminal.lua`, `dashboard.lua`
- For complex features, use directories: `picker/`, `explorer/`
- Group related functionality: `lsp/hover.lua`, `lsp/signature.lua`

### Internal Modules
- Prefix with underscore for private modules: `_internal.lua`
- Use descriptive names for core components: `engine.lua`, `state.lua`

## Module Dependencies

### Dependency Management

```lua
-- Check for required dependencies
local function check_dependencies()
  local required = {
    "plenary.nvim",
    "nvim-web-devicons",
  }
  
  for _, dep in ipairs(required) do
    if not pcall(require, dep) then
      error("Missing required dependency: " .. dep)
    end
  end
end

-- Optional dependency integration
local function setup_optional_integrations()
  -- Telescope integration
  if pcall(require, "telescope") then
    require("telescope").load_extension("plugin-name")
  end
  
  -- LSP integration
  if vim.lsp then
    require("plugin-name.integrations.lsp").setup()
  end
end
```

### Circular Dependency Prevention

```lua
-- Use factory pattern to prevent circular dependencies
local M = {}

local _core = nil
local function get_core()
  if not _core then
    _core = require("plugin-name.core")
  end
  return _core
end

function M.some_function()
  return get_core().process()
end

return M
```

## Best Practices

### 1. Single Responsibility
Each module should have a single, well-defined responsibility:
- Configuration handling
- Core business logic
- UI rendering
- State management

### 2. Clear Interfaces
Define clear public APIs and hide implementation details:

```lua
-- Public API
local M = {}

-- Private functions (local)
local function internal_helper()
  -- Implementation
end

-- Public functions
function M.public_function()
  return internal_helper()
end

return M
```

### 3. Consistent Error Handling
Implement consistent error handling across modules:

```lua
local M = {}

---@param msg string
---@param level? integer
local function notify_error(msg, level)
  vim.notify("[PluginName] " .. msg, level or vim.log.levels.ERROR)
end

function M.safe_operation()
  local ok, result = pcall(function()
    -- Risky operation
  end)
  
  if not ok then
    notify_error("Operation failed: " .. result)
    return nil
  end
  
  return result
end

return M
```

### 4. Documentation
Document module purpose and key functions:

```lua
---@class PluginModule: Module description and purpose
---@field config PluginConfig Configuration reference
---@field state table Internal state
local M = {}

---Initialize the module with configuration
---@param config PluginConfig Plugin configuration
---@return boolean success Whether initialization succeeded
function M.init(config)
  -- Implementation
end

return M
```

This modular organization approach ensures maintainable, scalable, and consistent plugin architecture that follows established community patterns.