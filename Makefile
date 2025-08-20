# Makefile for Nexus.nvim

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Test configuration
TEST_INIT := tests/minimal_init.lua
TEST_RUNNER := tests/test_runner.lua
NVIM_CMD := nvim --headless --noplugin -u $(TEST_INIT)

# Default target
.PHONY: all
all: test

# Run all tests
.PHONY: test
test:
	@echo "$(BLUE)Running Nexus.nvim test suite...$(NC)"
	@$(NVIM_CMD) -c "lua dofile('$(TEST_RUNNER)')"

# Run only unit tests
.PHONY: test-unit
test-unit:
	@echo "$(BLUE)Running unit tests...$(NC)"
	@$(NVIM_CMD) -c "lua require('plenary.test_harness').test_directory('tests/unit')"

# Run only integration tests
.PHONY: test-integration
test-integration:
	@echo "$(BLUE)Running integration tests...$(NC)"
	@$(NVIM_CMD) -c "lua require('plenary.test_harness').test_directory('tests/integration')"

# Run only performance tests
.PHONY: test-performance
test-performance:
	@echo "$(BLUE)Running performance tests...$(NC)"
	@$(NVIM_CMD) -c "lua require('plenary.test_harness').test_directory('tests/performance')"

# Run specific test file
.PHONY: test-file
test-file:
	@if [ -z "$(FILE)" ]; then \
		echo "$(RED)Error: Please specify FILE=path/to/test_spec.lua$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Running test file: $(FILE)$(NC)"
	@$(NVIM_CMD) -c "lua require('plenary.test_harness').test_file('$(FILE)')"

# Run tests with verbose output
.PHONY: test-verbose
test-verbose:
	@echo "$(BLUE)Running tests with verbose output...$(NC)"
	@$(NVIM_CMD) -c "lua require('tests.test_runner').config.verbose = true; dofile('$(TEST_RUNNER)')"

# Check test coverage (basic)
.PHONY: coverage
coverage:
	@echo "$(BLUE)Checking test coverage...$(NC)"
	@echo "$(YELLOW)Basic coverage analysis:$(NC)"
	@find lua/nexus -name '*.lua' -type f | while read file; do \
		module_name=$$(echo $$file | sed 's/lua\///g' | sed 's/\.lua//g' | sed 's/\//./g'); \
		test_file_pattern="tests/**/test_*$$module_name*.lua tests/**/*_$$module_name*_spec.lua tests/**/$$module_name*_spec.lua"; \
		if find tests -name "*$$(basename $$file .lua)*" -type f | grep -q .; then \
			echo "$(GREEN)✓$(NC) $$file"; \
		else \
			echo "$(RED)✗$(NC) $$file (no tests found)"; \
		fi; \
	done

# Lint Lua files (if luacheck is available)
.PHONY: lint
lint:
	@if command -v luacheck >/dev/null 2>&1; then \
		echo "$(BLUE)Running luacheck...$(NC)"; \
		luacheck lua/ tests/ --globals vim --read-globals-from-config; \
	else \
		echo "$(YELLOW)luacheck not found, skipping lint$(NC)"; \
	fi

# Format Lua files (if stylua is available)
.PHONY: format
format:
	@if command -v stylua >/dev/null 2>&1; then \
		echo "$(BLUE)Formatting Lua files with stylua...$(NC)"; \
		stylua lua/ tests/; \
	else \
		echo "$(YELLOW)stylua not found, skipping format$(NC)"; \
	fi

# Check formatting (if stylua is available)
.PHONY: format-check
format-check:
	@if command -v stylua >/dev/null 2>&1; then \
		echo "$(BLUE)Checking Lua formatting...$(NC)"; \
		stylua --check lua/ tests/; \
	else \
		echo "$(YELLOW)stylua not found, skipping format check$(NC)"; \
	fi

# Clean test artifacts
.PHONY: clean
clean:
	@echo "$(BLUE)Cleaning test artifacts...$(NC)"
	@rm -f /tmp/nexus-debug.log
	@find . -name '*.tmp' -delete 2>/dev/null || true
	@echo "$(GREEN)Clean complete$(NC)"

# Install test dependencies
.PHONY: deps
deps:
	@echo "$(BLUE)Checking test dependencies...$(NC)"
	@if [ ! -d "$(HOME)/.local/share/nvim/site/pack/packer/start/plenary.nvim" ]; then \
		echo "$(YELLOW)Installing plenary.nvim...$(NC)"; \
		git clone https://github.com/nvim-lua/plenary.nvim.git \
			"$(HOME)/.local/share/nvim/site/pack/packer/start/plenary.nvim"; \
	else \
		echo "$(GREEN)plenary.nvim already installed$(NC)"; \
	fi

# Benchmark tests (run performance tests multiple times)
.PHONY: benchmark
benchmark:
	@echo "$(BLUE)Running benchmark tests...$(NC)"
	@for i in 1 2 3 4 5; do \
		echo "$(YELLOW)Benchmark run $$i/5$(NC)"; \
		$(NVIM_CMD) -c "lua require('plenary.test_harness').test_directory('tests/performance')" || true; \
	done

# Watch for file changes and run tests (requires entr)
.PHONY: watch
watch:
	@if command -v entr >/dev/null 2>&1; then \
		echo "$(BLUE)Watching for file changes...$(NC)"; \
		find lua/ tests/ -name '*.lua' | entr -c make test; \
	else \
		echo "$(RED)Error: entr not found. Install with: brew install entr$(NC)"; \
		exit 1; \
	fi

# CI-friendly test run (no colors, structured output)
.PHONY: test-ci
test-ci:
	@$(NVIM_CMD) -c "lua require('tests.test_runner').config.verbose = false; dofile('$(TEST_RUNNER)')"

# Generate test report
.PHONY: report
report:
	@echo "$(BLUE)Generating test report...$(NC)"
	@echo "# Nexus.nvim Test Report" > test_report.md
	@echo "" >> test_report.md
	@echo "Generated on: $$(date)" >> test_report.md
	@echo "" >> test_report.md
	@echo "## Test Results" >> test_report.md
	@$(NVIM_CMD) -c "lua dofile('$(TEST_RUNNER)')" 2>&1 | \
		sed 's/\x1b\[[0-9;]*m//g' >> test_report.md || true
	@echo "$(GREEN)Test report generated: test_report.md$(NC)"

# Help target
.PHONY: help
help:
	@echo "$(BLUE)Nexus.nvim Test Makefile$(NC)"
	@echo ""
	@echo "Available targets:"
	@echo "  $(GREEN)test$(NC)              Run all tests"
	@echo "  $(GREEN)test-unit$(NC)         Run only unit tests"
	@echo "  $(GREEN)test-integration$(NC)  Run only integration tests"
	@echo "  $(GREEN)test-performance$(NC)  Run only performance tests"
	@echo "  $(GREEN)test-file$(NC)         Run specific test file (use FILE=path)"
	@echo "  $(GREEN)test-verbose$(NC)      Run tests with verbose output"
	@echo "  $(GREEN)test-ci$(NC)           Run tests in CI mode (no colors)"
	@echo "  $(GREEN)coverage$(NC)          Check test coverage"
	@echo "  $(GREEN)lint$(NC)              Lint Lua files (requires luacheck)"
	@echo "  $(GREEN)format$(NC)            Format Lua files (requires stylua)"
	@echo "  $(GREEN)format-check$(NC)      Check formatting (requires stylua)"
	@echo "  $(GREEN)clean$(NC)             Clean test artifacts"
	@echo "  $(GREEN)deps$(NC)              Install test dependencies"
	@echo "  $(GREEN)benchmark$(NC)         Run performance tests multiple times"
	@echo "  $(GREEN)watch$(NC)             Watch for changes and run tests (requires entr)"
	@echo "  $(GREEN)report$(NC)            Generate test report"
	@echo "  $(GREEN)help$(NC)              Show this help"
	@echo ""
	@echo "Examples:"
	@echo "  make test"
	@echo "  make test-file FILE=tests/unit/config_spec.lua"
	@echo "  make benchmark"