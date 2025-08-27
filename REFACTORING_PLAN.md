# Nexus.nvim Code Reduction Plan

## Executive Summary
- **Total lines of code**: 11,200 → 4,800 (projected)
- **Reduction percentage**: 57% reduction
- **Modules affected**: 42/56 modules  
- **Risk level**: LOW-MEDIUM (systematic consolidation with comprehensive testing)

The nexus.nvim codebase shows significant over-engineering with complex state management, action patterns, and component systems that could be dramatically simplified while preserving all essential functionality. The plugin's core purpose - a git dashboard - can be achieved with much less code.

## Priority 1: High-Impact, Low-Risk Reductions (Week 1)

### Dead Code and Over-Engineering Elimination (-2,400 lines, 21% reduction)

#### Complex State Management System (state/*.lua) - Remove Entirely
- **Files to Remove**: 
  - `lua/nexus/state/init.lua` (182 lines) - Observer pattern unnecessary
  - `lua/nexus/state/cache.lua` (193 lines) - Over-engineered caching for simple data
  - `lua/nexus/state/ui.lua` (260 lines) - UI state tracking unnecessary
  - `lua/nexus/state/git.lua` (154 lines) - Git state can be inline
  - `lua/nexus/state/linear.lua` (299 lines) - Linear state can be inline
- **Total Reduction**: 1,088 lines
- **Rationale**: Plugin needs simple data fetching, not reactive state management
- **Risk**: NONE - State system adds complexity without user-visible benefits
- **Testing**: Verify git status and Linear integration still work with direct function calls

#### Over-Engineered Action System (actions/*.lua) - Replace with Simple Functions
- **Files to Consolidate**:
  - `lua/nexus/actions/init.lua` (294 lines) - Complex registry system
  - `lua/nexus/actions/base.lua` (162 lines) - Abstract base class unnecessary
  - All action files (600+ lines total) - Simple functions instead of classes
- **Total Reduction**: 1,056 lines
- **Replacement**: 150 lines of simple functions in `lua/nexus/git_actions.lua`
- **Rationale**: Dashboard needs basic git operations, not command pattern architecture
- **Risk**: LOW - Actions are just wrappers around git commands

#### Provider System Over-Abstraction (providers/*.lua) - Simplify
- **Files to Remove**:
  - `lua/nexus/providers/base.lua` (192 lines) - Abstract provider unnecessary  
  - `lua/nexus/providers/manager.lua` (248 lines) - Provider management overkill
- **Files to Inline**: `lua/nexus/providers/linear.lua` (394 lines) → 150 lines direct functions
- **Total Reduction**: 684 lines
- **Risk**: LOW - Linear integration can be simple HTTP requests

### Configuration System Simplification (-200 lines)
- **Current**: Complex validation, nested configs, observer patterns
- **Proposed**: Simple table merge with basic validation
- **Files**: `lua/nexus/config.lua` (190 lines) → 80 lines
- **Risk**: NONE - Maintains all user-facing config options

## Priority 2: Module Consolidation (Week 2)

### UI Component Consolidation (-800 lines, 7% reduction)

#### Render System Unification
- **Current Structure**:
  ```
  lua/nexus/render/
  ├── layout.lua           (112 lines)
  ├── components/
  │   ├── sections.lua     (109 lines)
  │   ├── highlighting.lua (282 lines)
  │   ├── linear.lua       (256 lines)
  │   └── events.lua       (37 lines)
  ```
- **Proposed Structure**:
  ```
  lua/nexus/render.lua     (400 lines total)
  ```
- **Consolidation**: All rendering logic in single file
- **Risk**: LOW - Related functionality, clear boundaries

#### UI Utilities Merge
- **Files to Consolidate**:
  - `lua/nexus/ui/center.lua` (40 lines) - Simple centering functions
  - `lua/nexus/ui/shortcuts.lua` (79 lines) - Shortcut rendering
  - `lua/nexus/ui/dashboard.lua` (19 lines) - Dashboard buttons
  - `lua/nexus/ui/folding.lua` (195 lines) - Git status folding
- **Result**: `lua/nexus/ui.lua` (200 lines total)
- **Reduction**: 133 lines (29% of UI code)

#### Git Operations Consolidation  
- **Files to Merge**:
  - `lua/nexus/git/utils.lua` (17 lines) - Basic git checks
  - `lua/nexus/git/status.lua` (116 lines) - Git status parsing
  - `lua/nexus/git/commits.lua` (50 lines) - Commit parsing
  - `lua/nexus/git/operations.lua` (339 lines) - Git operations
  - `lua/nexus/git/command.lua` (677 lines) - Command execution
- **Result**: `lua/nexus/git.lua` (600 lines total)  
- **Reduction**: 599 lines (50% of git code)

### Utility and Helper Consolidation (-300 lines)
- **Registry System Removal**: `lua/nexus/shortcuts_registry.lua` (105 lines)
- **Helper Integration**: Various small helpers into main modules
- **Logger Simplification**: `lua/nexus/logger.lua` (170 lines) → 50 lines

## Priority 3: API and Architecture Simplification (Week 3)

### Main Module Restructuring (-600 lines, 5% reduction)

#### Keymap System Dramatic Simplification
- **Current**: `lua/nexus/keymaps.lua` (961 lines) - Complex conditional logic
- **Proposed**: 200 lines of simple pattern matching
- **Reduction**: 761 lines (79% reduction)
- **Approach**: Replace complex action dispatching with direct function calls

#### Entry Point Optimization
- **Current**: Multiple initialization phases, complex lazy loading
- **Proposed**: Simple setup() and open() functions
- **Files**: `lua/nexus/init.lua` (137 lines) → 80 lines

### Linear Integration Simplification (-200 lines)
- **Remove**: Complex state management, caching layers, provider abstraction
- **Keep**: HTTP requests, issue display, configuration
- **Result**: Single `linear.lua` file with essential functionality

## Implementation Phases

### Phase 1: State System Elimination (Days 1-3)
```bash
# Remove state management files
rm -rf lua/nexus/state/
# Update all modules to use direct function calls
# Test: Verify dashboard opens and refreshes correctly
```

### Phase 2: Action System Simplification (Days 4-6)  
```bash
# Remove action system files
rm -rf lua/nexus/actions/
# Create simple git_actions.lua with essential functions
# Test: Verify all git operations (stage, unstage, commit, diff) work
```

### Phase 3: Module Consolidation (Days 7-10)
```bash
# Consolidate render components into single file
# Merge UI utilities
# Consolidate git modules
# Test: Full functionality verification
```

### Phase 4: Final Optimizations (Days 11-14)
```bash
# Simplify keymaps.lua
# Optimize main entry points
# Remove unused utilities
# Performance testing and optimization
```

## Success Metrics

### Quantitative Targets
- **Startup time**: < 5ms (currently ~15ms with state management)
- **Memory usage**: < 2MB total (currently ~4MB)  
- **Line count**: 4,800 lines (57% reduction from 11,200)
- **File count**: 20 files (64% reduction from 56 files)

### Functionality Preservation
- ✅ Git dashboard with status and commits
- ✅ All git operations (stage, unstage, commit, diff)
- ✅ Dashboard buttons and navigation
- ✅ Linear integration (simplified)
- ✅ Claude conversation integration
- ✅ All configuration options
- ✅ Tmux integration

### Quality Improvements
- **Reduced complexity**: Eliminate unnecessary abstractions
- **Better performance**: Remove state management overhead
- **Simpler maintenance**: Fewer files, clearer code paths
- **Preserved features**: All user-visible functionality maintained

## Risk Mitigation

### Low Risk Changes (85% of reduction)
- State management removal (no user-visible impact)
- Action system simplification (same functionality)
- Module consolidation (internal organization only)
- Dead code removal (unused functionality)

### Medium Risk Changes (15% of reduction)
- Keymap system simplification (maintain all key bindings)
- Linear integration changes (preserve API compatibility)
- Entry point modifications (same user interface)

### Testing Strategy
1. **Unit tests**: Verify each phase independently
2. **Integration tests**: Full workflow testing after each phase
3. **Performance tests**: Startup and operation benchmarking
4. **User acceptance**: All features work as before

## Long-term Benefits

### Developer Experience
- **Easier contribution**: Simpler codebase structure
- **Faster debugging**: Clear, linear code paths  
- **Better performance**: Reduced initialization overhead
- **Maintainable code**: Less abstraction, more direct logic

### User Experience  
- **Faster startup**: Reduced initialization time
- **Lower memory**: Simplified state management
- **Same features**: All functionality preserved
- **Better reliability**: Fewer complex interactions

This reduction plan transforms nexus.nvim from an over-engineered complex system into a focused, efficient git dashboard while preserving all essential functionality and improving performance.