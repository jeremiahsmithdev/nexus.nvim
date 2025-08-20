# Pre-Linear Integration Refactoring Plan

## Executive Summary

This document outlines the necessary architectural refactoring of Nexus.nvim that should be completed **before** implementing Linear integration. Based on analysis from both `LUA-REFACTOR.md` and `CLAUDE-PLAN.md`, this refactoring will establish a solid foundation for integrating external service providers like Linear while maintaining plugin performance and maintainability.

## Strategic Objectives

### 1. Performance & Scalability
- Replace synchronous git operations with async alternatives
- Implement intelligent caching layer
- Establish lazy loading patterns for external integrations

### 2. Maintainability & Architecture
- Decompose monolithic render module into focused components
- Implement command pattern for decoupled operations
- Establish centralized state management

### 3. Extensibility Foundation
- Create provider abstraction for external services (Linear, GitHub, Jira)
- Implement event-driven architecture for reactive updates
- Establish plugin API for future extensions

## Phase 1: Core Infrastructure Refactoring (Week 1)

### Priority 1: Async Git Operations Foundation

**Current Problem:**
```lua
-- Blocking I/O in git/status.lua
local handle = io.popen('git status --porcelain=v1 2>/dev/null')
local result = handle:read('*a')  -- Blocks UI thread
handle:close()
```

**Solution: Async Git Module**
```
lua/nexus/git/
├── async.lua           -- Async git operations using vim.fn.jobstart
├── parser.lua          -- Git output parsing logic
├── cache.lua           -- Git status caching
└── operations.lua      -- Git command wrappers
```

**Implementation Steps:**
1. Create `lua/nexus/git/async.lua` with async git operations
2. Implement progressive loading (show cached data, update when fresh data arrives)
3. Add error handling with fallback to synchronous operations
4. Implement git status caching with TTL (30 seconds default)

### Priority 2: Render Module Decomposition

**Current Problem:**
- `render.lua` (408 lines) handles too many responsibilities
- Mixed concerns: content generation, highlighting, event handling

**Solution: Render Component Architecture**
```
lua/nexus/render/
├── init.lua            -- Main render coordinator
├── components/
│   ├── header.lua      -- Logo and project info
│   ├── git_status.lua  -- Git status section
│   ├── commits.lua     -- Recent commits section
│   └── footer.lua      -- Session and navigation info
├── layout.lua          -- Layout management and positioning
├── highlighting.lua    -- Highlight application
└── events.lua          -- Event handling setup
```

**Implementation Steps:**
1. Extract component rendering logic into focused modules
2. Implement layout manager for responsive design
3. Create highlight namespace manager
4. Establish event handling patterns for interactive elements

### Priority 3: State Management System

**Current Problem:**
- State scattered across modules
- No centralized state coordination
- Repeated expensive operations

**Solution: Centralized State with Observer Pattern**
```
lua/nexus/state/
├── init.lua            -- Main state manager
├── git.lua             -- Git-related state
├── ui.lua              -- UI state and preferences
└── cache.lua           -- Cache state management
```

**Implementation Steps:**
1. Create centralized state store with observer pattern
2. Implement reactive state updates
3. Add state persistence for user preferences
4. Create state validation and error recovery

## Phase 2: Service Provider Architecture (Week 2)

### Priority 4: Provider Abstraction Layer

**Purpose:** Establish foundation for Linear and future integrations

**Provider Interface Design:**
```lua
-- lua/nexus/providers/base.lua
---@class Provider
---@field name string Provider identifier
---@field config table Provider configuration
local Provider = {}

function Provider:new(config) end
function Provider:authenticate() end
function Provider:get_issues(opts) end
function Provider:update_issue(id, data) end
function Provider:create_issue(data) end
function Provider:get_user_info() end
function Provider:health_check() end
```

**Provider Architecture:**
```
lua/nexus/providers/
├── base.lua            -- Abstract provider interface
├── linear.lua          -- Linear implementation (placeholder)
├── github.lua          -- GitHub Issues (future)
├── jira.lua            -- Jira integration (future)
└── manager.lua         -- Provider registration and management
```

**Implementation Steps:**
1. Design abstract provider interface
2. Create provider registration system
3. Implement provider lifecycle management
4. Add provider health checking

### Priority 5: Command Pattern Implementation

**Current Problem:**
- Keymaps tightly coupled to implementation
- Difficult to extend or modify actions

**Solution: Command Pattern with Action Registry**
```
lua/nexus/actions/
├── init.lua            -- Action registry and dispatcher
├── git/
│   ├── add.lua         -- Git add command
│   ├── commit.lua      -- Git commit command
│   └── diff.lua        -- Show diff command
├── navigation/
│   ├── open_file.lua   -- File navigation
│   └── refresh.lua     -- Refresh dashboard
└── base.lua            -- Abstract action class
```

**Implementation Steps:**
1. Create action base class and registry
2. Extract existing keybind logic into action classes
3. Implement action validation and error handling
4. Add action context management

### Priority 6: Configuration System Enhancement

**Current Problem:**
- Configuration spread across modules
- No runtime configuration updates
- Limited validation

**Solution: Enhanced Configuration Management**
```
lua/nexus/config/
├── init.lua            -- Main configuration manager
├── validation.lua      -- Schema validation
├── defaults.lua        -- Default configurations
├── migration.lua       -- Config migration handling
└── watchers.lua        -- Configuration change handlers
```

**Implementation Steps:**
1. Create configuration schema with validation
2. Implement runtime configuration updates
3. Add configuration migration system
4. Create configuration change watchers

## Phase 3: Performance & Quality Improvements (Week 3)

### Priority 7: Caching Layer Implementation

**Cache Architecture:**
```
lua/nexus/cache/
├── init.lua            -- Cache manager
├── storage.lua         -- Persistent storage
├── memory.lua          -- In-memory caching
└── strategies.lua      -- Cache invalidation strategies
```

**Cache Strategy:**
- **Git Status**: 30-second TTL, invalidate on file changes
- **Git Commits**: 5-minute TTL, invalidate on new commits
- **Provider Data**: 5-minute TTL, configurable per provider
- **User Preferences**: Persistent storage, immediate updates

### Priority 8: Error Handling & Recovery

**Error System Architecture:**
```
lua/nexus/error/
├── init.lua            -- Error manager
├── handlers.lua        -- Error handling strategies
├── recovery.lua        -- Recovery mechanisms
└── reporting.lua       -- Error reporting and logging
```

**Error Handling Strategy:**
1. Graceful degradation for provider failures
2. Automatic retry with exponential backoff
3. User-friendly error messages
4. Fallback to cached data when possible

### Priority 9: Logging & Diagnostics

**Enhanced Logging System:**
```
lua/nexus/logging/
├── init.lua            -- Main logger
├── formatters.lua      -- Log formatting
├── appenders.lua       -- Log output destinations
└── levels.lua          -- Log level management
```

## Phase 4: Testing & Documentation (Week 4)

### Priority 10: Testing Framework

**Test Architecture:**
```
tests/
├── unit/
│   ├── git/
│   │   ├── async_spec.lua
│   │   └── parser_spec.lua
│   ├── render/
│   │   └── components_spec.lua
│   └── state/
│       └── manager_spec.lua
├── integration/
│   ├── full_dashboard_spec.lua
│   └── git_workflow_spec.lua
└── mocks/
    ├── git.lua
    └── providers.lua
```

### Priority 11: API Documentation

**Documentation Structure:**
```
docs/
├── api/
│   ├── public_api.md
│   ├── provider_api.md
│   └── configuration.md
├── architecture/
│   ├── overview.md
│   └── state_management.md
└── guides/
    ├── extending.md
    └── troubleshooting.md
```

## Expected Outcomes

### Performance Improvements
- **50% faster startup** through async operations and lazy loading
- **Reduced memory footprint** via intelligent caching
- **Non-blocking UI** with progressive data loading

### Architecture Benefits
- **Modular design** with clear separation of concerns
- **Extensible provider system** ready for Linear integration
- **Maintainable codebase** with focused responsibilities
- **Testable components** with dependency injection

### User Experience
- **Responsive interface** with no UI blocking
- **Graceful error handling** with helpful messages
- **Configurable behavior** with runtime updates
- **Professional reliability** with comprehensive error recovery

## Implementation Checklist

### Week 1: Core Infrastructure
- [ ] Implement async git operations
- [ ] Decompose render module
- [ ] Create state management system
- [ ] Add comprehensive error handling

### Week 2: Service Architecture
- [ ] Design provider abstraction
- [ ] Implement command pattern
- [ ] Enhance configuration system
- [ ] Create action registry

### Week 3: Performance & Quality
- [ ] Implement caching layer
- [ ] Add performance monitoring
- [ ] Create diagnostic system
- [ ] Optimize startup performance

### Week 4: Testing & Docs
- [ ] Write comprehensive tests
- [ ] Create API documentation
- [ ] Add troubleshooting guides
- [ ] Performance validation

## Risk Mitigation

### Backward Compatibility
- Maintain existing API surface during refactoring
- Provide migration helpers for configuration changes
- Add deprecation warnings for breaking changes

### Performance Regression
- Benchmark before/after refactoring
- Monitor memory usage and startup time
- Add performance regression tests

### Complexity Management
- Implement changes incrementally
- Maintain comprehensive documentation
- Use consistent patterns throughout

## Test Migration Strategy

### Expected Test Impact Post-Refactor

**High Impact Areas (Tests will need updates):**
- `git_status_spec.lua` & `git_utils_spec.lua` - Async git operations will require new mocking patterns
- Render module - New component-based architecture needs component-specific tests
- State management - Centralized state will change how modules are tested

**Low Impact Areas (Tests should continue passing):**
- `config_spec.lua` - Configuration enhancements build on existing patterns
- `buffer_spec.lua` - Buffer management logic remains stable
- `logger_spec.lua` - Core logging functionality unchanged

### Test Migration Approach

1. **Pre-Refactor**: Only create tests after new modules are implemented and working
2. **During Refactor**: Update existing test mocks as implementation changes (async jobs, state store, providers)
3. **Post-Refactor**: Run test suite to validate refactor success - expect:
   - 80%+ tests passing immediately (config, buffer, logger unchanged)
   - Git tests may need mock updates for async operations
   - New component tests validate modular architecture

### Success Validation
Post-refactor test results will indicate refactor quality:
- **90%+ pass rate**: Excellent backward compatibility maintained
- **70-90% pass rate**: Normal - update git/render mocks needed
- **<70% pass rate**: Review refactor approach, may need rollback

## Success Metrics

### Technical Metrics
- Startup time < 50ms (target: 30ms)
- Memory usage < 10MB steady state
- Git operation response time < 100ms
- Cache hit rate > 80% for repeated operations

### Quality Metrics
- Test coverage > 85%
- Zero critical issues in health checks
- Error recovery success rate > 95%
- User configuration validation 100%

## Post-Refactoring State

Upon completion of this refactoring plan, Nexus.nvim will have:

1. **Solid Architecture Foundation** - Ready for Linear integration without major structural changes
2. **Performance Optimization** - Fast, responsive, and efficient operation
3. **Extensibility Framework** - Easy addition of new providers and features
4. **Quality Assurance** - Comprehensive testing and error handling
5. **Professional Polish** - Production-ready reliability and user experience

This refactoring establishes the groundwork for seamless Linear integration while ensuring the plugin remains maintainable, performant, and extensible for future enhancements.