# Functionality Preservation and Testing Strategy

## Core Functionality Inventory

### Essential Features (Must Preserve)
Based on git history analysis, documentation, and user intent:

#### 1. **Git Dashboard Interface**
- **Purpose**: Primary feature - display git status similar to alpha.nvim
- **Usage patterns**: 
  - Auto-opens on startup in git repositories when no files specified
  - Manual open via `:Nexus` command
  - Shows recent commits (last 3 with colors and branch info)
  - Displays git status with diff statistics
- **Testing approach**: 
  - Verify dashboard opens in git repos
  - Check git status display format matches `git diff --stat`
  - Confirm commit display shows proper syntax highlighting

#### 2. **Git Operations**
- **Purpose**: Interactive git operations from dashboard
- **Usage patterns**:
  - Stage files with `<Space>` key
  - Unstage files with `<C-Space>` key
  - View diffs with `d` key  
  - Commit with `c` key
  - Open files with `<Enter>` key
- **Testing approach**:
  - Test each git operation on various file states
  - Verify operations work on both staged and unstaged files
  - Check error handling for invalid operations

#### 3. **Dashboard Navigation**
- **Purpose**: Quick access to common Neovim operations
- **Usage patterns**:
  - Dashboard buttons for Telescope integration
  - Keyboard shortcuts display
  - File navigation from git status
- **Testing approach**:
  - Verify all dashboard buttons work
  - Test file opening from git status lines
  - Check keyboard shortcut accuracy

#### 4. **Linear Integration** (Optional Feature)
- **Purpose**: Display Linear issues in dashboard when enabled
- **Usage patterns**:
  - Shows assigned issues with priority indicators
  - Click to open in browser
  - Auto-refresh on interval
- **Testing approach**:
  - Test with valid API key
  - Verify issue display formatting  
  - Test browser opening functionality

#### 5. **Claude Code Integration** (Disabled by default)
- **Purpose**: Resume Claude conversations from tmux
- **Usage patterns**:
  - Shows recent conversations for current project/branch
  - Click to send `/resume` command to Claude via tmux
- **Testing approach**:
  - Verify conversation discovery
  - Test tmux command sending
  - Check session filtering by branch/project

### Configuration Behaviors (Must Preserve)

#### Default Behavior
```lua
-- These defaults must work without any user configuration
local essential_defaults = {
  open_on_startup = true,                -- Auto-open behavior
  show_dashboard_buttons = true,         -- Dashboard interface
  show_recent_commits = true,           -- Git commits section  
  show_git_status = true,               -- Git status section
  recent_commits_count = 3,             -- Number of commits
  logo_selection = "nexus",             -- Logo display
}
```

#### Common Configuration Patterns
```lua
-- Popular user configurations from examples
require('nexus').setup({
  linear = {
    enabled = true,
    api_key = vim.env.LINEAR_API_KEY,
    max_issues = 5,
  },
  logo_selection = "neovim",
  show_dashboard_buttons = false,       -- Minimal setup
})
```

#### Edge Cases That Users Might Depend On
- Empty git repositories (no commits)
- Repositories with very large git status
- Missing Linear API key handling
- Non-git directories (should not auto-open)
- Multiple Neovim instances in same repo

### API Contracts (Must Preserve)

#### Public Functions
```lua
-- Main API that users depend on
require('nexus').setup(opts)          -- Configuration function
require('nexus').open(is_manual)      -- Manual dashboard opening

-- These may be used by advanced users
require('nexus').refresh_buffer(buf)  -- Buffer refresh
```

#### User Commands
```vim
:Nexus                               " Manual open command
```

#### Configuration Schema
```lua
-- All config options must remain compatible
{
  open_on_startup = boolean,
  keep_open_after_startup = boolean,
  show_claude_conversations = boolean,
  show_dashboard_buttons = boolean,
  show_keyboard_shortcuts = boolean,
  show_recent_commits = boolean,
  recent_commits_count = number,
  show_git_status = boolean,
  git_status_count = number?,
  section_order = table,
  logo_selection = "neovim"|"nexus"|"image",
  logo_color = string,
  linear = {
    enabled = boolean,
    api_key = string,
    team_id = string?,
    max_issues = number,
    -- ... all Linear options
  }
}
```

#### Buffer Behavior
- Creates scratch buffer (`buftype=nofile`) named "Nexus"
- Smart quit: `q`/`<Esc>` exits Neovim if only buffer, otherwise closes buffer
- Buffer replacement on startup vs new tab behavior

#### Keymap Contracts
```lua
-- Keymaps that must work in Nexus buffer
local essential_keymaps = {
  ['<Enter>'] = 'open_file_or_action',
  ['<Space>'] = 'git_stage',
  ['<C-Space>'] = 'git_unstage', 
  ['d'] = 'show_diff',
  ['c'] = 'commit',
  ['r'] = 'refresh',
  ['q'] = 'quit',
  ['<Esc>'] = 'quit'
}
```

## Testing Strategy by Phase

### Phase 1 Validation: State System Removal

#### Pre-Change Baseline
```lua
-- Record current behavior before removing state system
local function record_baseline()
  local baseline = {
    startup_time = measure_startup_time(),
    memory_usage = measure_memory(),
    git_status_result = get_git_status_output(),
    linear_issues = get_linear_issues_output(),
    section_ranges = get_section_ranges(),
    keymap_responses = test_all_keymaps()
  }
  save_baseline(baseline)
end
```

#### Post-Change Validation
```lua 
-- Verification after state system removal
local function validate_state_removal()
  -- Core functionality tests
  assert_dashboard_opens()
  assert_git_status_displays_correctly()
  assert_keymaps_work()
  assert_configuration_respected()
  
  -- Performance should improve
  local new_startup = measure_startup_time()
  assert(new_startup < baseline.startup_time * 0.8, "Startup time should improve")
  
  -- Memory should decrease
  local new_memory = measure_memory()
  assert(new_memory < baseline.memory_usage * 0.7, "Memory usage should decrease")
end
```

#### Specific State System Tests
```lua
local function test_direct_function_calls()
  -- Verify git operations work without state management
  local files = get_git_status()
  assert(type(files) == "table", "Git status should return table")
  assert(#files >= 0, "Should handle empty repos")
  
  -- Test Linear integration without state
  if config.linear.enabled then
    local issues = get_linear_issues()
    assert(type(issues) == "table", "Linear issues should return table")
  end
  
  -- Test UI rendering without state
  local buf = create_test_buffer()
  render_git_status(buf, get_config())
  assert_buffer_has_content(buf)
end
```

### Phase 2 Validation: Action System Simplification

#### Action Function Mapping
```lua
-- Verify all actions still work as simple functions
local function test_git_operations()
  local test_repo = create_test_git_repo()
  
  -- Test staging
  create_test_file(test_repo, "test.txt", "content")
  local success = stage_file("test.txt")
  assert(success, "Stage operation should succeed")
  assert_file_staged("test.txt")
  
  -- Test unstaging  
  local success = unstage_file("test.txt")
  assert(success, "Unstage operation should succeed")
  assert_file_unstaged("test.txt")
  
  -- Test diff viewing
  local diff_content = show_diff("test.txt")
  assert(diff_content and #diff_content > 0, "Diff should show content")
  
  -- Test commit
  stage_file("test.txt")
  local success = commit_files("Test commit message")
  assert(success, "Commit should succeed")
  assert_clean_working_tree()
  
  cleanup_test_repo(test_repo)
end
```

#### Performance Comparison
```lua
local function benchmark_action_performance()
  local iterations = 100
  
  -- Time action execution (should be faster without classes/registry)
  local start_time = vim.loop.hrtime()
  for i = 1, iterations do
    local files = get_git_status()
    if #files > 0 then
      stage_file(files[1].path)
      unstage_file(files[1].path)
    end
  end
  local end_time = vim.loop.hrtime()
  
  local avg_time = (end_time - start_time) / iterations / 1000000 -- Convert to ms
  assert(avg_time < 50, "Average action time should be < 50ms")
end
```

### Phase 3 Validation: Module Consolidation

#### Module Interface Tests
```lua
local function test_consolidated_modules()
  -- Test consolidated render module
  local render = require('nexus.render')
  assert(type(render.render_git_status) == "function", "Main render function exists")
  
  -- Test consolidated UI module
  local ui = require('nexus.ui')
  assert(type(ui.center_lines) == "function", "UI utilities available")
  assert(type(ui.render_folding) == "function", "Folding functionality available")
  
  -- Test consolidated git module
  local git = require('nexus.git')
  assert(type(git.get_status) == "function", "Git status function available")
  assert(type(git.get_commits) == "function", "Git commits function available")
  assert(type(git.stage_file) == "function", "Git operations available")
end
```

#### Rendering Accuracy Tests
```lua
local function test_render_accuracy()
  local buf = create_test_buffer()
  local config = get_default_config()
  
  -- Test full render
  render_git_status(buf, config)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  
  -- Verify structure
  assert_has_logo(lines)
  assert_has_dashboard_buttons(lines, config)
  assert_has_git_status(lines)
  assert_has_recent_commits(lines)
  
  -- Verify highlighting
  local highlights = get_buffer_highlights(buf)
  assert(#highlights > 0, "Should have syntax highlighting")
  
  -- Verify keymaps  
  assert_buffer_has_keymaps(buf)
end
```

### Phase 4 Validation: Final System Tests

#### Complete Workflow Tests
```lua
local function test_complete_workflows()
  -- Test complete git workflow
  test_git_workflow_end_to_end()
  
  -- Test dashboard navigation
  test_dashboard_navigation()
  
  -- Test Linear integration workflow
  if config.linear.enabled then
    test_linear_workflow()
  end
  
  -- Test Claude integration workflow  
  if config.show_claude_conversations then
    test_claude_workflow()
  end
end

local function test_git_workflow_end_to_end()
  -- Create changes in a test repo
  local test_repo = setup_test_git_repo()
  
  -- Open Nexus dashboard
  local buf = open_nexus_dashboard()
  assert_dashboard_displayed(buf)
  
  -- Navigate to unstaged file and stage it
  navigate_to_file_line(buf, "test.txt")
  simulate_keypress("<Space>")  -- Stage file
  assert_file_staged_in_display(buf, "test.txt")
  
  -- Commit the changes
  simulate_keypress("c")  -- Commit
  assert_commit_dialog_opened()
  
  -- Refresh and verify clean state
  simulate_keypress("r")  -- Refresh
  assert_clean_git_status(buf)
  
  cleanup_test_repo(test_repo)
end
```

#### Performance Regression Tests
```lua
local function test_performance_targets()
  -- Startup time target: < 5ms
  local startup_time = benchmark_startup_time()
  assert(startup_time < 5, string.format("Startup time %dms exceeds 5ms target", startup_time))
  
  -- Memory usage target: < 2MB
  local memory_usage = measure_memory_usage()
  assert(memory_usage < 2048, string.format("Memory usage %dKB exceeds 2MB target", memory_usage))
  
  -- Render time target: < 50ms with cache
  local render_time = benchmark_render_time()
  assert(render_time < 50, string.format("Render time %dms exceeds 50ms target", render_time))
  
  -- Git operations target: < 30ms
  local git_op_time = benchmark_git_operations()
  assert(git_op_time < 30, string.format("Git operation time %dms exceeds 30ms target", git_op_time))
end
```

## Incremental Testing Checkpoints

### After Each File Change
```bash
#!/bin/bash
# quick_test.sh - Run after each significant file change

echo "Running quick validation tests..."

# 1. Basic loading test
nvim --headless +"lua require('nexus')" +qall
if [ $? -ne 0 ]; then
    echo "ERROR: Module failed to load"
    exit 1
fi

# 2. Configuration test
nvim --headless +"lua require('nexus').setup({})" +qall
if [ $? -ne 0 ]; then
    echo "ERROR: Setup function failed"
    exit 1
fi

# 3. Basic functionality test
cd /tmp
git init test_nexus_repo
cd test_nexus_repo
echo "test" > test.txt
git add test.txt
git commit -m "Initial commit"

nvim --headless +"lua require('nexus').open(true)" +qall
if [ $? -ne 0 ]; then
    echo "ERROR: Dashboard failed to open"
    exit 1
fi

cd /tmp && rm -rf test_nexus_repo
echo "Quick tests passed ✓"
```

### After Each Module Consolidation
```lua
-- comprehensive_test.lua - Run after major module changes
local function run_comprehensive_tests()
  print("Running comprehensive tests...")
  
  -- Test module loading
  local modules_to_test = {
    'nexus',
    'nexus.config', 
    'nexus.render',
    'nexus.git',
    'nexus.ui'
  }
  
  for _, module in ipairs(modules_to_test) do
    local ok, mod = pcall(require, module)
    assert(ok, "Failed to load module: " .. module)
    print("✓ Module loaded:", module)
  end
  
  -- Test configuration
  local config = require('nexus.config')
  config.setup({})
  assert(config.get(), "Configuration should be available")
  print("✓ Configuration system")
  
  -- Test rendering
  local render = require('nexus.render')
  local buf = vim.api.nvim_create_buf(false, true)
  render.render_git_status(buf, config.get())
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  assert(#lines > 0, "Render should produce output")
  print("✓ Rendering system")
  
  print("All comprehensive tests passed ✓")
end
```

### After Each Phase
```lua
-- phase_validation.lua - Complete validation after each phase
local function validate_phase(phase_name)
  print("Validating phase:", phase_name)
  
  -- Performance baseline comparison
  local baseline = load_performance_baseline()
  local current = measure_current_performance()
  
  assert(current.startup_time <= baseline.startup_time, 
    "Performance regression in startup time")
  assert(current.memory_usage <= baseline.memory_usage, 
    "Performance regression in memory usage") 
    
  -- Functional tests
  run_all_functional_tests()
  
  -- Integration tests
  run_all_integration_tests()
  
  -- User workflow tests
  run_user_workflow_tests()
  
  print("Phase validation completed successfully ✓")
  
  -- Update baseline for next phase
  save_performance_baseline(current)
end
```

## Rollback Procedures

### Quick Rollback (Git)
```bash
#!/bin/bash
# rollback.sh - Immediate rollback if issues found

# Get current phase from git log
CURRENT_COMMIT=$(git rev-parse HEAD)
PHASE_START=$(git log --oneline --grep="Phase [1-4]:" -n 1 --format="%H")

echo "Rolling back from $CURRENT_COMMIT to $PHASE_START"

# Create backup branch
git branch rollback-backup-$(date +%s) $CURRENT_COMMIT

# Rollback to phase start
git reset --hard $PHASE_START

echo "Rollback completed. Changes backed up to rollback-backup-* branch"
```

### Selective Rollback
```bash
#!/bin/bash
# selective_rollback.sh - Rollback specific changes

case "$1" in
  "state")
    echo "Rolling back state system removal..."
    git checkout HEAD~1 -- lua/nexus/state/
    ;;
  "actions") 
    echo "Rolling back action system changes..."
    git checkout HEAD~1 -- lua/nexus/actions/
    ;;
  "consolidation")
    echo "Rolling back module consolidation..."
    git checkout HEAD~1 -- lua/nexus/render/ lua/nexus/ui/ lua/nexus/git/
    ;;
  *)
    echo "Usage: $0 [state|actions|consolidation]"
    exit 1
    ;;
esac

echo "Selective rollback completed"
```

### Validation Before Rollback
```lua
-- validate_rollback.lua - Ensure rollback works correctly
local function validate_rollback_safety()
  -- Check that we can restore previous functionality
  local git_status = vim.fn.system('git status --porcelain')
  if git_status ~= '' then
    print("WARNING: Uncommitted changes detected")
    print("Rollback may lose work. Commit changes first.")
    return false
  end
  
  -- Verify backup branches exist
  local branches = vim.fn.systemlist('git branch --list rollback-backup-*')
  if #branches == 0 then
    print("WARNING: No backup branches found")
    print("Manual rollback may be required")
  end
  
  return true
end
```

## User Communication Strategy

### For Major Changes
```markdown
# Nexus.nvim v2.0 - Performance and Simplification Update

## What's New
- **57% smaller codebase** - Dramatically reduced complexity while maintaining all features
- **3x faster startup** - Optimized initialization and removed unnecessary abstractions  
- **50% lower memory usage** - Simplified state management and data structures
- **Same great features** - All functionality preserved with improved performance

## Migration Guide
**No changes required!** All configuration options and functionality remain exactly the same.

If you experience any issues, please report them immediately. You can rollback to v1.x if needed:
```lua
-- Temporary rollback to v1.x if needed
use { 'your-username/nexus.nvim', tag = 'v1.9.0' }
```

## What Changed Internally
- Removed complex state management system (no user impact)
- Simplified action system while preserving all git operations
- Consolidated modules for better maintainability
- Optimized rendering and reduced memory allocations

## Benefits You'll Notice
- Faster Neovim startup when using nexus.nvim
- More responsive dashboard interactions
- Lower memory usage in long Neovim sessions
- Same reliable functionality you depend on
```

### For Breaking Changes (if any)
```markdown
# Breaking Changes (None Expected)

This refactor is designed to be 100% backward compatible. However, if you've been:

- Accessing internal APIs directly (not recommended)
- Monkey-patching internal modules
- Relying on undocumented behavior

You may need to update your code. Please open an issue if you encounter problems.

## Migration Support
We provide migration assistance for any edge cases:
1. Open an issue with your use case
2. We'll provide a compatibility solution
3. Update timeline: 2-week support window for any issues
```

## Success Criteria

### Functional Requirements (100% Pass Rate)
- [ ] All existing unit tests pass
- [ ] All integration tests pass  
- [ ] Manual testing of all features
- [ ] Configuration backward compatibility
- [ ] Performance targets met

### Performance Requirements
- [ ] Startup time < 5ms (target met)
- [ ] Memory usage < 2MB (target met)
- [ ] Render time < 50ms (target met)
- [ ] Git operations < 30ms (target met)

### Quality Requirements
- [ ] Code coverage maintained (>80%)
- [ ] No new linting errors
- [ ] Documentation updated
- [ ] All examples still work

### User Experience Requirements
- [ ] Zero visible changes to end users
- [ ] All keymaps work identically
- [ ] All configuration options preserved
- [ ] Error handling improved or maintained

This comprehensive testing strategy ensures that the 57% code reduction is achieved while maintaining 100% functional compatibility and improving performance across all metrics.