-- Test runner for Nexus.nvim
-- This runs all tests and provides a comprehensive report

-- Load the test framework
require('tests.minimal_init')

local plenary = require('plenary.test_harness')

-- Color output functions
local function green(text)
  return '\27[32m' .. text .. '\27[0m'
end

local function red(text)
  return '\27[31m' .. text .. '\27[0m'
end

local function yellow(text)
  return '\27[33m' .. text .. '\27[0m'
end

local function blue(text)
  return '\27[34m' .. text .. '\27[0m'
end

-- Test suite configuration
local test_config = {
  -- Test directories to scan
  test_dirs = {
    'tests/unit',
    'tests/integration',
    'tests/performance'
  },
  
  -- Test pattern matching
  test_patterns = {
    '*_spec.lua',
    'test_*.lua'
  },
  
  -- Output configuration
  verbose = true,
  show_coverage = true,
  fail_fast = false
}

-- Main test runner function
local function run_all_tests()
  print(blue('==== Nexus.nvim Test Suite ===='))
  print()
  
  local total_tests = 0
  local passed_tests = 0
  local failed_tests = 0
  local test_results = {}
  
  -- Discover and run all test files
  for _, test_dir in ipairs(test_config.test_dirs) do
    local test_path = vim.fn.expand('%:p:h') .. '/' .. test_dir
    
    if vim.fn.isdirectory(test_path) == 1 then
      print(yellow('Running tests in: ' .. test_dir))
      
      -- Find all test files in directory
      for _, pattern in ipairs(test_config.test_patterns) do
        local files = vim.fn.glob(test_path .. '/' .. pattern, false, true)
        
        for _, file in ipairs(files) do
          local rel_path = vim.fn.fnamemodify(file, ':.')
          print('  ' .. rel_path)
          
          -- Run the test file
          local success, result = pcall(function()
            return plenary.test_file(file, {
              timeout = 30000,
              verbose = test_config.verbose
            })
          end)
          
          if success and result then
            passed_tests = passed_tests + (result.passed or 0)
            failed_tests = failed_tests + (result.failed or 0)
            total_tests = total_tests + (result.total or 0)
            
            table.insert(test_results, {
              file = rel_path,
              result = result,
              success = true
            })
          else
            failed_tests = failed_tests + 1
            total_tests = total_tests + 1
            
            table.insert(test_results, {
              file = rel_path,
              error = result or 'Unknown error',
              success = false
            })
          end
        end
      end
      print()
    end
  end
  
  -- Print summary
  print(blue('==== Test Summary ===='))
  print(string.format('Total: %d tests', total_tests))
  print(green(string.format('Passed: %d tests', passed_tests)))
  
  if failed_tests > 0 then
    print(red(string.format('Failed: %d tests', failed_tests)))
    
    -- Show failed test details
    print()
    print(red('Failed Tests:'))
    for _, test_result in ipairs(test_results) do
      if not test_result.success then
        print('  ' .. red('✗') .. ' ' .. test_result.file)
        if test_result.error then
          print('    Error: ' .. tostring(test_result.error))
        end
      end
    end
  else
    print(green('All tests passed! ✓'))
  end
  
  print()
  
  -- Calculate success rate
  local success_rate = total_tests > 0 and (passed_tests / total_tests * 100) or 0
  print(string.format('Success Rate: %.1f%%', success_rate))
  
  -- Exit with appropriate code
  if failed_tests > 0 then
    vim.cmd('cquit 1')
  else
    vim.cmd('quit 0')
  end
end

-- Export for external use
local M = {}
M.run_all_tests = run_all_tests
M.config = test_config

-- Auto-run if called directly
if ... == nil then
  run_all_tests()
end

return M