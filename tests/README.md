# Nexus.nvim Test Suite

A comprehensive test suite for the Nexus.nvim dashboard plugin, providing safety nets for refactoring and ensuring code quality.

## Overview

This test suite covers:

- **Unit Tests**: Individual module functionality
- **Integration Tests**: Component interactions and workflows
- **Performance Tests**: Startup time, rendering speed, and resource usage
- **Mock Framework**: Complete mocking of external dependencies

## Test Structure

```
tests/
├── README.md                    # This file
├── minimal_init.lua            # Minimal Neovim config for testing
├── test_runner.lua             # Main test runner with reporting
├── helpers/
│   └── mocks.lua               # Comprehensive mocking framework
├── unit/                       # Unit tests
│   ├── config_spec.lua         # Configuration system tests
│   ├── logger_spec.lua         # Logging functionality tests
│   ├── git_utils_spec.lua      # Git utilities tests
│   ├── git_status_spec.lua     # Git status parsing tests
│   ├── buffer_spec.lua         # Buffer management tests
│   └── logo_spec.lua           # Logo and UI component tests
├── integration/                # Integration tests
│   ├── dashboard_rendering_spec.lua     # Full dashboard workflow tests
│   └── keymap_interactions_spec.lua     # Keymap and navigation tests
└── performance/                # Performance tests
    └── startup_performance_spec.lua     # Startup and operation benchmarks
```

## Quick Start

### Prerequisites

1. **Neovim** (>= 0.8.0)
2. **plenary.nvim** (automatically installed if missing)

### Running Tests

```bash
# Run all tests
make test

# Or use the test script
./scripts/test.sh

# Run specific test types
make test-unit
make test-integration
make test-performance

# Run with verbose output
make test-verbose
./scripts/test.sh -v

# Run specific test file
make test-file FILE=tests/unit/config_spec.lua
./scripts/test.sh -f tests/unit/config_spec.lua
```

### Test Coverage

```bash
# Check test coverage
make coverage
./scripts/test.sh -c
```

### Performance Benchmarks

```bash
# Run performance benchmarks
make benchmark
./scripts/test.sh -b
```

## Test Framework

### Mock System

The test suite includes a comprehensive mocking framework (`tests/helpers/mocks.lua`) that provides:

- **Git Operations**: Mock git status, commits, and repository state
- **Tmux Integration**: Mock tmux environment and pane operations  
- **File System**: Mock file operations and directory structure
- **Buffer API**: Mock Neovim buffer operations
- **System Commands**: Mock external command execution
- **Logger**: Silent logging during tests for performance

### Example Test Setup

```lua
local mocks = require('tests.helpers.mocks')

describe('my module', function()
  before_each(function()
    mocks.setup_test_environment({
      git_repo = true,
      git_status = {
        {status = ' M', file = 'test.lua'},
        {status = '??', file = 'new.lua'}
      },
      tmux = {
        id = '%0',
        width = 80,
        height = 24
      }
    })
  end)
  
  after_each(function()
    mocks.restore_all()
  end)
  
  it('should work correctly', function()
    -- Your test code here
  end)
end)
```

## Unit Tests

### Configuration Tests (`config_spec.lua`)
- Default configuration validation
- User configuration merging
- Input validation and sanitization
- Backward compatibility handling
- Section ordering validation

### Logger Tests (`logger_spec.lua`)
- Log level handling (info, debug, warn, error)
- Log format consistency
- Tmux context integration
- Specialized logging functions
- File operations and cleanup

### Git Utilities Tests (`git_utils_spec.lua`)
- Git repository detection
- Git root path resolution
- Error handling for non-git directories
- Edge cases (bare repos, worktrees)

### Git Status Tests (`git_status_spec.lua`)
- Status parsing from porcelain output
- Diff statistics calculation
- Status icon formatting
- Visual diff stat creation
- Color coding for different states

### Buffer Management Tests (`buffer_spec.lua`)
- Buffer creation (persistent vs temporary)
- Window option configuration
- Autocommand setup and lifecycle
- Image rendering integration
- Git-specific autocommands

### Logo and UI Tests (`logo_spec.lua`)
- ASCII logo rendering
- Image logo integration
- Tmux coordinate handling
- Backward compatibility
- Configuration-based selection

## Integration Tests

### Dashboard Rendering (`dashboard_rendering_spec.lua`)
- Complete dashboard workflow
- Section ordering and display
- Git integration scenarios
- Buffer management integration
- Configuration change handling

### Keymap Interactions (`keymap_interactions_spec.lua`)
- Dashboard button activation
- Git status file operations
- Navigation behavior
- Quit logic testing
- Commit detail viewing

## Performance Tests

### Startup Performance (`startup_performance_spec.lua`)
- Module loading time (< 50ms)
- Configuration setup (< 25ms)
- Dashboard rendering (< 100ms for small repos)
- Git operations scaling (< 200ms for 1000 files)
- Memory efficiency validation

**Performance Targets:**
- Plugin startup: < 50ms
- Dashboard open: < 100ms (small repos), < 300ms (500 files)
- Git status parsing: < 200ms (1000 files)
- Configuration validation: < 25ms
- Dashboard refresh: < 50ms

## CI Integration

### GitHub Actions Example

```yaml
name: Test
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: rhymond/setup-neovim@v1
        with:
          version: stable
      - name: Run tests
        run: make test-ci
```

### Test Commands

```bash
# CI-friendly (no colors, structured output)
make test-ci
./scripts/test.sh --ci

# Generate test report
make report

# Watch for changes (requires entr)
make watch
```

## Writing Tests

### Test File Naming

- Unit tests: `*_spec.lua` or `test_*.lua`
- Place in appropriate subdirectory (`unit/`, `integration/`, `performance/`)
- Match module structure: `lua/nexus/config.lua` → `tests/unit/config_spec.lua`

### Best Practices

1. **Use Descriptive Test Names**
   ```lua
   it('should validate git_status_count as number', function()
   ```

2. **Setup and Teardown**
   ```lua
   before_each(function()
     mocks.setup_test_environment()
   end)
   
   after_each(function()
     mocks.restore_all()
   end)
   ```

3. **Test Edge Cases**
   ```lua
   it('should handle empty git output', function()
     -- Test with empty strings, nil values, etc.
   end)
   ```

4. **Performance Assertions**
   ```lua
   local time = measure_time(function()
     -- Operation to measure
   end)
   assert.is_true(time < 50, "Operation took too long")
   ```

5. **Mock External Dependencies**
   ```lua
   mocks.mock_system_command('git status', 'M  file.lua\n')
   ```

## Debugging Tests

### Enable Verbose Output

```bash
make test-verbose
./scripts/test.sh -v
```

### Individual Test Debugging

```bash
# Run single test file
make test-file FILE=tests/unit/config_spec.lua

# Run with Neovim directly for debugging
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "lua require('plenary.test_harness').test_file('tests/unit/config_spec.lua')"
```

### Logger Integration

Tests can use the logger for debugging:

```lua
local logger = require('nexus.logger')
logger.set_console_output(true)  -- Enable console output during tests
```

## Test Maintenance

### Adding New Tests

1. Create test file in appropriate directory
2. Follow naming conventions
3. Use the mocking framework
4. Add performance assertions for critical paths
5. Update this README if needed

### Updating Mocks

When adding new external dependencies:

1. Add mock implementations to `tests/helpers/mocks.lua`
2. Update `setup_test_environment()` function
3. Add restore logic to `restore_all()`
4. Document new mock capabilities

### Performance Monitoring

Run benchmarks regularly to catch performance regressions:

```bash
# Run multiple iterations for statistical analysis
make benchmark
```

Track key metrics:
- Module loading time
- Dashboard rendering speed
- Git operation performance
- Memory usage patterns

## Troubleshooting

### Common Issues

1. **plenary.nvim not found**
   ```bash
   make deps  # Installs missing dependencies
   ```

2. **Tests fail in CI but pass locally**
   - Check for OS-specific behavior
   - Verify all mocks are properly set up
   - Use `make test-ci` to reproduce CI environment

3. **Performance tests failing**
   - Check system load
   - Run benchmarks multiple times
   - Adjust thresholds if hardware differences are significant

4. **Mock-related failures**
   - Ensure `mocks.restore_all()` is called in `after_each`
   - Check that all external dependencies are properly mocked
   - Verify mock state is reset between tests

### Getting Help

- Check test output for specific failure messages
- Run individual test files to isolate issues
- Use verbose mode for detailed output
- Review mock setup in failing tests

## Contributing

When contributing to the test suite:

1. Maintain or improve test coverage
2. Follow existing naming and structure conventions
3. Add performance tests for new features
4. Update documentation as needed
5. Ensure all tests pass before submitting

The test suite is designed to provide confidence during refactoring and ensure the plugin maintains its performance and reliability characteristics.