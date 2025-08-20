# Configuration Systems

This guide covers the patterns for implementing robust and user-friendly configuration systems in Neovim Lua plugins, including option handling, validation, and dynamic configuration updates.

## Configuration Architecture

### Configuration Class Definition

```lua
---@class PluginConfig
---@field enabled? boolean Enable the plugin (default: true)
---@field log_level? "debug"|"info"|"warn"|"error" Logging level (default: "info")
---@field features? FeatureConfig Feature-specific configuration
---@field ui? UiConfig UI configuration options
---@field integrations? IntegrationConfig Third-party integrations

---@class FeatureConfig
---@field feature1? FeatureOneConfig
---@field feature2? FeatureTwoConfig

---@class UiConfig
---@field theme? "auto"|"light"|"dark" UI theme (default: "auto")
---@field icons? table<string, string> Custom icon overrides
---@field highlights? table<string, vim.api.keyset.highlight> Custom highlights

---@class IntegrationConfig
---@field telescope? boolean Enable Telescope integration (default: true)
---@field lsp? LspConfig LSP integration configuration
```

### Default Configuration Pattern

```lua
local M = {}

---@type PluginConfig
M.defaults = {
  enabled = true,
  log_level = "info",
  features = {
    feature1 = {
      enabled = true,
      option = "default_value",
    },
    feature2 = {
      enabled = false,
      timeout = 5000,
    },
  },
  ui = {
    theme = "auto",
    icons = {
      error = "",
      warn = "",
      info = "",
      hint = "",
    },
    highlights = {},
  },
  integrations = {
    telescope = true,
    lsp = {
      enabled = true,
      hover = true,
      signature = true,
    },
  },
}

---@type PluginConfig
M.options = {}

return M
```

## Configuration Setup Patterns

### Basic Setup with Validation

```lua
---Setup the plugin with user configuration
---@param user_opts? PluginConfig User configuration
function M.setup(user_opts)
  -- 1. Initialize with defaults
  M.options = vim.deepcopy(M.defaults)
  
  -- 2. Merge user options
  if user_opts then
    M.options = M.merge_config(M.options, user_opts)
  end
  
  -- 3. Validate configuration
  local valid, error_msg = M.validate_config(M.options)
  if not valid then
    M.error("Invalid configuration: " .. error_msg)
    return false
  end
  
  -- 4. Post-process configuration
  M.options = M.normalize_config(M.options)
  
  -- 5. Initialize plugin with validated config
  M.init(M.options)
  
  return true
end
```

### Advanced Configuration Merging

```lua
---Intelligently merge user configuration with defaults
---@param defaults PluginConfig Default configuration
---@param user_opts PluginConfig User configuration
---@return PluginConfig merged Merged configuration
function M.merge_config(defaults, user_opts)
  local function merge_strategy(key, default_val, user_val)
    -- Special handling for specific keys
    if key == "icons" then
      -- Merge icon tables completely
      return vim.tbl_extend("force", default_val or {}, user_val or {})
    elseif key == "highlights" then
      -- Merge highlight tables
      return vim.tbl_extend("force", default_val or {}, user_val or {})
    elseif type(default_val) == "table" and type(user_val) == "table" then
      -- Deep merge for nested tables
      return M.merge_config(default_val, user_val)
    else
      -- Use user value if provided, otherwise default
      return user_val ~= nil and user_val or default_val
    end
  end
  
  local merged = {}
  
  -- Process all keys from defaults
  for key, default_val in pairs(defaults) do
    merged[key] = merge_strategy(key, default_val, user_opts[key])
  end
  
  -- Add any additional user keys
  for key, user_val in pairs(user_opts) do
    if merged[key] == nil then
      merged[key] = user_val
    end
  end
  
  return merged
end
```

## Configuration Validation

### Comprehensive Validation

```lua
---Validate plugin configuration
---@param config PluginConfig Configuration to validate
---@return boolean valid True if configuration is valid
---@return string? error Error message if invalid
function M.validate_config(config)
  local validators = {
    enabled = function(val)
      return type(val) == "boolean", "must be boolean"
    end,
    
    log_level = function(val)
      local levels = { "debug", "info", "warn", "error" }
      return vim.tbl_contains(levels, val), "must be one of: " .. table.concat(levels, ", ")
    end,
    
    features = function(val)
      if type(val) ~= "table" then
        return false, "must be a table"
      end
      
      -- Validate nested feature configs
      for feature_name, feature_config in pairs(val) do
        local valid, err = M.validate_feature_config(feature_name, feature_config)
        if not valid then
          return false, string.format("features.%s: %s", feature_name, err)
        end
      end
      
      return true
    end,
    
    ui = function(val)
      if type(val) ~= "table" then
        return false, "must be a table"
      end
      
      if val.theme and not vim.tbl_contains({"auto", "light", "dark"}, val.theme) then
        return false, "ui.theme must be 'auto', 'light', or 'dark'"
      end
      
      return true
    end,
  }
  
  -- Validate each configured option
  for key, value in pairs(config) do
    local validator = validators[key]
    if validator then
      local valid, error_msg = validator(value)
      if not valid then
        return false, string.format("%s: %s", key, error_msg)
      end
    end
  end
  
  return true
end

---Validate feature-specific configuration
---@param feature_name string Name of the feature
---@param feature_config table Feature configuration
---@return boolean valid
---@return string? error
function M.validate_feature_config(feature_name, feature_config)
  local feature_validators = {
    feature1 = function(config)
      if config.option and type(config.option) ~= "string" then
        return false, "option must be a string"
      end
      return true
    end,
    
    feature2 = function(config)
      if config.timeout and (type(config.timeout) ~= "number" or config.timeout <= 0) then
        return false, "timeout must be a positive number"
      end
      return true
    end,
  }
  
  local validator = feature_validators[feature_name]
  if validator then
    return validator(feature_config)
  end
  
  return true -- No specific validation for unknown features
end
```

### Type-Safe Configuration

```lua
---@class ConfigValidator
local Validator = {}

---Create a new validator instance
---@param schema table Validation schema
---@return ConfigValidator
function Validator.new(schema)
  return setmetatable({ schema = schema }, { __index = Validator })
end

---Validate value against schema
---@param value any Value to validate
---@param path? string Current validation path
---@return boolean valid
---@return string? error
function Validator:validate(value, path)
  path = path or "config"
  return self:validate_schema(value, self.schema, path)
end

---@private
function Validator:validate_schema(value, schema, path)
  if schema.type then
    if type(value) ~= schema.type then
      return false, string.format("%s: expected %s, got %s", path, schema.type, type(value))
    end
  end
  
  if schema.enum then
    if not vim.tbl_contains(schema.enum, value) then
      return false, string.format("%s: must be one of %s", path, vim.inspect(schema.enum))
    end
  end
  
  if schema.min and value < schema.min then
    return false, string.format("%s: must be >= %s", path, schema.min)
  end
  
  if schema.max and value > schema.max then
    return false, string.format("%s: must be <= %s", path, schema.max)
  end
  
  if schema.properties and type(value) == "table" then
    for key, prop_schema in pairs(schema.properties) do
      if value[key] ~= nil then
        local valid, err = self:validate_schema(value[key], prop_schema, path .. "." .. key)
        if not valid then
          return false, err
        end
      elseif prop_schema.required then
        return false, string.format("%s.%s: required field missing", path, key)
      end
    end
  end
  
  if schema.custom_validator then
    return schema.custom_validator(value, path)
  end
  
  return true
end

-- Usage example
local config_schema = {
  type = "table",
  properties = {
    enabled = { type = "boolean" },
    log_level = { type = "string", enum = { "debug", "info", "warn", "error" } },
    timeout = { type = "number", min = 0, max = 60000 },
    features = {
      type = "table",
      custom_validator = function(value, path)
        -- Custom validation logic
        return true
      end,
    },
  },
}

local validator = Validator.new(config_schema)
local valid, error = validator:validate(user_config)
```

## Dynamic Configuration

### Configuration Updates

```lua
---Update configuration at runtime
---@param updates table Configuration updates to apply
---@return boolean success True if update was successful
function M.update_config(updates)
  local old_config = vim.deepcopy(M.options)
  
  -- Apply updates
  local new_config = M.merge_config(M.options, updates)
  
  -- Validate new configuration
  local valid, error_msg = M.validate_config(new_config)
  if not valid then
    M.error("Configuration update failed: " .. error_msg)
    return false
  end
  
  -- Calculate what changed
  local changes = M.diff_config(old_config, new_config)
  
  -- Apply configuration
  M.options = new_config
  
  -- Notify about changes
  M.apply_config_changes(changes)
  
  return true
end

---Calculate differences between configurations
---@param old_config PluginConfig
---@param new_config PluginConfig
---@return table changes
function M.diff_config(old_config, new_config)
  local changes = {}
  
  local function diff_recursive(old, new, path)
    for key, value in pairs(new) do
      local current_path = path and (path .. "." .. key) or key
      
      if old[key] ~= value then
        if type(value) == "table" and type(old[key]) == "table" then
          diff_recursive(old[key], value, current_path)
        else
          changes[current_path] = { old = old[key], new = value }
        end
      end
    end
  end
  
  diff_recursive(old_config, new_config)
  return changes
end

---Apply configuration changes
---@param changes table Configuration changes
function M.apply_config_changes(changes)
  for path, change in pairs(changes) do
    local handler = M.change_handlers[path]
    if handler then
      handler(change.new, change.old)
    end
  end
end
```

### Change Handlers

```lua
---Configuration change handlers
M.change_handlers = {
  ["log_level"] = function(new_level, old_level)
    M.log.set_level(new_level)
    M.info(string.format("Log level changed from %s to %s", old_level, new_level))
  end,
  
  ["ui.theme"] = function(new_theme, old_theme)
    M.ui.set_theme(new_theme)
    M.info(string.format("Theme changed from %s to %s", old_theme, new_theme))
  end,
  
  ["features.feature1.enabled"] = function(enabled, was_enabled)
    if enabled and not was_enabled then
      M.features.feature1.enable()
    elseif not enabled and was_enabled then
      M.features.feature1.disable()
    end
  end,
}
```

## Environment-Based Configuration

### Environment Detection

```lua
---Detect current environment and adjust configuration
---@param config PluginConfig
---@return PluginConfig adjusted_config
function M.adjust_for_environment(config)
  local env_config = vim.deepcopy(config)
  
  -- Adjust for GUI vs terminal
  if vim.g.neovide or vim.g.fvim then
    env_config.ui.use_gui_features = true
  end
  
  -- Adjust for colorscheme
  local colorscheme = vim.g.colors_name or "default"
  if colorscheme:match("light") then
    env_config.ui.theme = "light"
  elseif colorscheme:match("dark") then
    env_config.ui.theme = "dark"
  end
  
  -- Adjust for terminal capabilities
  if vim.env.TERM_PROGRAM == "tmux" then
    env_config.ui.use_tmux_integration = true
  end
  
  -- Performance adjustments for large files
  local file_size = vim.fn.getfsize(vim.fn.expand("%"))
  if file_size > 1000000 then -- 1MB
    env_config.performance.disable_heavy_features = true
  end
  
  return env_config
end
```

### Multi-Environment Configuration

```lua
---Configuration profiles for different environments
M.profiles = {
  minimal = {
    features = {
      feature1 = { enabled = false },
      feature2 = { enabled = false },
    },
    ui = {
      icons = false,
      animations = false,
    },
  },
  
  development = {
    log_level = "debug",
    features = {
      feature1 = { enabled = true, debug = true },
      feature2 = { enabled = true, verbose = true },
    },
  },
  
  performance = {
    features = {
      feature1 = { cache_enabled = true },
      feature2 = { lazy_loading = true },
    },
    ui = {
      animations = false,
      debounce_ms = 100,
    },
  },
}

---Apply configuration profile
---@param profile_name string Name of the profile to apply
function M.apply_profile(profile_name)
  local profile = M.profiles[profile_name]
  if not profile then
    M.error("Unknown configuration profile: " .. profile_name)
    return false
  end
  
  local current_config = M.options
  local profile_config = M.merge_config(current_config, profile)
  
  return M.update_config(profile_config)
end
```

## Configuration Persistence

### Save and Load Configuration

```lua
---Save current configuration to file
---@param filepath? string Optional file path (defaults to plugin config)
function M.save_config(filepath)
  filepath = filepath or M.get_config_path()
  
  local config_data = {
    version = M.version,
    config = M.options,
    timestamp = os.time(),
  }
  
  local ok, err = pcall(function()
    local file = io.open(filepath, "w")
    if not file then
      error("Failed to open file for writing: " .. filepath)
    end
    
    file:write(vim.fn.json_encode(config_data))
    file:close()
  end)
  
  if not ok then
    M.error("Failed to save configuration: " .. err)
    return false
  end
  
  M.info("Configuration saved to " .. filepath)
  return true
end

---Load configuration from file
---@param filepath? string Optional file path
---@return PluginConfig? config Loaded configuration or nil
function M.load_config(filepath)
  filepath = filepath or M.get_config_path()
  
  if not vim.fn.filereadable(filepath) then
    return nil
  end
  
  local ok, result = pcall(function()
    local file = io.open(filepath, "r")
    if not file then
      error("Failed to open file for reading: " .. filepath)
    end
    
    local content = file:read("*all")
    file:close()
    
    return vim.fn.json_decode(content)
  end)
  
  if not ok then
    M.warn("Failed to load configuration: " .. result)
    return nil
  end
  
  -- Validate version compatibility
  if result.version and not M.is_version_compatible(result.version) then
    M.warn("Configuration version mismatch, using defaults")
    return nil
  end
  
  return result.config
end

---Get configuration file path
---@return string path
function M.get_config_path()
  local config_dir = vim.fn.stdpath("config")
  return config_dir .. "/plugin-name-config.json"
end
```

## Best Practices

### 1. Configuration Design Principles
- **Sensible defaults**: Plugin should work well without any configuration
- **Progressive disclosure**: Simple options first, advanced options nested
- **Backward compatibility**: Handle configuration migrations gracefully
- **Validation**: Comprehensive validation with helpful error messages

### 2. Performance Considerations
- **Lazy loading**: Don't process configuration until needed
- **Caching**: Cache expensive configuration computations
- **Minimal impact**: Configuration updates should be fast and non-blocking

### 3. User Experience
- **Clear documentation**: Document all configuration options with examples
- **Helpful errors**: Provide specific, actionable error messages
- **Dynamic updates**: Allow configuration changes without restart when possible
- **Profiles**: Provide pre-configured setups for common use cases

### 4. Code Organization
- **Separate concerns**: Keep configuration logic separate from business logic
- **Type safety**: Use comprehensive type annotations
- **Testability**: Make configuration system easy to test in isolation

This configuration system approach ensures robust, user-friendly, and maintainable plugin configuration that follows established community patterns.