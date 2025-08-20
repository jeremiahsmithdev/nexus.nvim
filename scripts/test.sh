#!/usr/bin/env bash
# Test runner script for Nexus.nvim

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_INIT="$PROJECT_ROOT/tests/minimal_init.lua"
TEST_RUNNER="$PROJECT_ROOT/tests/test_runner.lua"

# Default values
VERBOSE=false
TYPE="all"
FILE=""
COVERAGE=false
BENCHMARK=false

# Help function
show_help() {
    echo -e "${BLUE}Nexus.nvim Test Runner${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -v, --verbose           Enable verbose output"
    echo "  -t, --type TYPE         Test type: all, unit, integration, performance"
    echo "  -f, --file FILE         Run specific test file"
    echo "  -c, --coverage          Show coverage analysis"
    echo "  -b, --benchmark         Run benchmark tests (multiple iterations)"
    echo "  --ci                    Run in CI mode (no colors, structured output)"
    echo ""
    echo "Examples:"
    echo "  $0                                      # Run all tests"
    echo "  $0 -t unit                             # Run only unit tests"
    echo "  $0 -f tests/unit/config_spec.lua      # Run specific test file"
    echo "  $0 -v -t integration                  # Run integration tests with verbose output"
    echo "  $0 -c                                  # Show coverage analysis"
    echo "  $0 -b                                  # Run benchmark tests"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--type)
            TYPE="$2"
            shift 2
            ;;
        -f|--file)
            FILE="$2"
            shift 2
            ;;
        -c|--coverage)
            COVERAGE=true
            shift
            ;;
        -b|--benchmark)
            BENCHMARK=true
            shift
            ;;
        --ci)
            CI_MODE=true
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}" >&2
            show_help
            exit 1
            ;;
    esac
done

# Validate test type
if [[ "$TYPE" != "all" && "$TYPE" != "unit" && "$TYPE" != "integration" && "$TYPE" != "performance" ]]; then
    echo -e "${RED}Error: Invalid test type '$TYPE'. Valid types: all, unit, integration, performance${NC}" >&2
    exit 1
fi

# Check if Neovim is available
if ! command -v nvim &> /dev/null; then
    echo -e "${RED}Error: Neovim not found. Please install Neovim.${NC}" >&2
    exit 1
fi

# Check if test files exist
if [[ ! -f "$TEST_INIT" ]]; then
    echo -e "${RED}Error: Test initialization file not found: $TEST_INIT${NC}" >&2
    exit 1
fi

if [[ ! -f "$TEST_RUNNER" ]]; then
    echo -e "${RED}Error: Test runner file not found: $TEST_RUNNER${NC}" >&2
    exit 1
fi

# Function to run neovim with test configuration
run_nvim_test() {
    local cmd="$1"
    if [[ "$CI_MODE" == "true" ]]; then
        # CI mode: no colors, structured output
        nvim --headless --noplugin -u "$TEST_INIT" -c "$cmd" 2>&1
    else
        nvim --headless --noplugin -u "$TEST_INIT" -c "$cmd"
    fi
}

# Function to check dependencies
check_dependencies() {
    echo -e "${BLUE}Checking test dependencies...${NC}"
    
    # Check for plenary.nvim
    local plenary_paths=(
        "$HOME/.local/share/nvim/site/pack/packer/start/plenary.nvim"
        "$HOME/.local/share/nvim/lazy/plenary.nvim"
        "$HOME/.config/nvim/pack/plugins/start/plenary.nvim"
    )
    
    local plenary_found=false
    for path in "${plenary_paths[@]}"; do
        if [[ -d "$path" ]]; then
            plenary_found=true
            break
        fi
    done
    
    if [[ "$plenary_found" == "false" ]]; then
        echo -e "${YELLOW}Warning: plenary.nvim not found in common locations.${NC}"
        echo -e "${YELLOW}Installing plenary.nvim to default location...${NC}"
        
        local install_path="$HOME/.local/share/nvim/site/pack/packer/start/plenary.nvim"
        mkdir -p "$(dirname "$install_path")"
        
        if git clone --quiet https://github.com/nvim-lua/plenary.nvim.git "$install_path"; then
            echo -e "${GREEN}✓ plenary.nvim installed successfully${NC}"
        else
            echo -e "${RED}✗ Failed to install plenary.nvim${NC}"
            echo -e "${YELLOW}Please install plenary.nvim manually${NC}"
        fi
    else
        echo -e "${GREEN}✓ plenary.nvim found${NC}"
    fi
}

# Function to show coverage analysis
show_coverage() {
    echo -e "${BLUE}Analyzing test coverage...${NC}"
    echo ""
    
    local total_files=0
    local covered_files=0
    
    while IFS= read -r -d '' lua_file; do
        total_files=$((total_files + 1))
        
        # Get relative path from lua/
        local rel_path="${lua_file#$PROJECT_ROOT/lua/}"
        local module_name="${rel_path%.lua}"
        module_name="${module_name//\//.}"
        
        # Look for corresponding test files
        local test_patterns=(
            "tests/unit/${module_name##*.}_spec.lua"
            "tests/unit/test_${module_name##*.}.lua"
            "tests/integration/${module_name##*.}_spec.lua"
            "tests/**/*${module_name##*.}*_spec.lua"
        )
        
        local has_tests=false
        for pattern in "${test_patterns[@]}"; do
            if find "$PROJECT_ROOT/tests" -name "*${module_name##*.}*" -type f 2>/dev/null | grep -q .; then
                has_tests=true
                break
            fi
        done
        
        if [[ "$has_tests" == "true" ]]; then
            echo -e "${GREEN}✓${NC} $rel_path"
            covered_files=$((covered_files + 1))
        else
            echo -e "${RED}✗${NC} $rel_path (no tests found)"
        fi
        
    done < <(find "$PROJECT_ROOT/lua/nexus" -name '*.lua' -type f -print0)
    
    echo ""
    local coverage_percent=$((covered_files * 100 / total_files))
    echo -e "${BLUE}Coverage Summary:${NC}"
    echo -e "  Total files: $total_files"
    echo -e "  Covered files: $covered_files"
    echo -e "  Coverage: ${coverage_percent}%"
    
    if [[ $coverage_percent -gt 80 ]]; then
        echo -e "${GREEN}✓ Good coverage${NC}"
    elif [[ $coverage_percent -gt 60 ]]; then
        echo -e "${YELLOW}⚠ Moderate coverage${NC}"
    else
        echo -e "${RED}✗ Low coverage${NC}"
    fi
}

# Function to run benchmark tests
run_benchmark() {
    echo -e "${BLUE}Running benchmark tests (5 iterations)...${NC}"
    
    local total_time=0
    local runs=5
    
    for i in $(seq 1 $runs); do
        echo -e "${YELLOW}Benchmark run $i/$runs${NC}"
        
        local start_time=$(date +%s.%3N)
        run_nvim_test "lua require('plenary.test_harness').test_directory('tests/performance')" > /dev/null 2>&1 || true
        local end_time=$(date +%s.%3N)
        
        local run_time=$(echo "$end_time - $start_time" | bc)
        total_time=$(echo "$total_time + $run_time" | bc)
        
        echo "  Run $i: ${run_time}s"
    done
    
    local avg_time=$(echo "scale=3; $total_time / $runs" | bc)
    echo ""
    echo -e "${BLUE}Benchmark Results:${NC}"
    echo "  Total time: ${total_time}s"
    echo "  Average time: ${avg_time}s"
    echo "  Runs: $runs"
}

# Main execution
main() {
    cd "$PROJECT_ROOT"
    
    # Check dependencies
    check_dependencies
    
    # Show coverage if requested
    if [[ "$COVERAGE" == "true" ]]; then
        show_coverage
        return
    fi
    
    # Run benchmark tests if requested
    if [[ "$BENCHMARK" == "true" ]]; then
        run_benchmark
        return
    fi
    
    # Configure verbose output
    local verbose_config=""
    if [[ "$VERBOSE" == "true" ]]; then
        verbose_config="require('tests.test_runner').config.verbose = true;"
    fi
    
    # Run specific file if provided
    if [[ -n "$FILE" ]]; then
        if [[ ! -f "$FILE" ]]; then
            echo -e "${RED}Error: Test file not found: $FILE${NC}" >&2
            exit 1
        fi
        
        echo -e "${BLUE}Running test file: $FILE${NC}"
        run_nvim_test "${verbose_config}lua require('plenary.test_harness').test_file('$FILE')"
        return
    fi
    
    # Run tests based on type
    case "$TYPE" in
        "all")
            echo -e "${BLUE}Running all tests...${NC}"
            run_nvim_test "${verbose_config}lua dofile('$TEST_RUNNER')"
            ;;
        "unit")
            echo -e "${BLUE}Running unit tests...${NC}"
            run_nvim_test "${verbose_config}lua require('plenary.test_harness').test_directory('tests/unit')"
            ;;
        "integration")
            echo -e "${BLUE}Running integration tests...${NC}"
            run_nvim_test "${verbose_config}lua require('plenary.test_harness').test_directory('tests/integration')"
            ;;
        "performance")
            echo -e "${BLUE}Running performance tests...${NC}"
            run_nvim_test "${verbose_config}lua require('plenary.test_harness').test_directory('tests/performance')"
            ;;
    esac
}

# Run main function
main "$@"