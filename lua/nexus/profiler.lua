-- Enhanced profiler for Nexus with conditional compilation
local M = {}

local logger = require('nexus.logger')

-- Profiling state
local start_time = vim.uv.hrtime()
local timings = {}
local last_time = start_time
local is_enabled = false
local memory_snapshots = {}

-- Enable profiling (controlled by environment variable or config)
function M.enable()
  is_enabled = true
  start_time = vim.uv.hrtime()
  last_time = start_time
  timings = {}
  memory_snapshots = {}
  logger.info('PROFILER', 'Performance profiling enabled')
end

function M.disable()
  is_enabled = false
  logger.info('PROFILER', 'Performance profiling disabled')
end

function M.is_enabled()
  return is_enabled
end

-- Record a timing point
function M.mark(label)
  if not is_enabled then
    return
  end
  
  local current_time = vim.uv.hrtime()
  local elapsed = (current_time - start_time) / 1000000  -- Convert to milliseconds
  local delta = (current_time - last_time) / 1000000     -- Time since last mark
  
  table.insert(timings, {
    label = label,
    elapsed = elapsed,
    delta = delta,
    timestamp = current_time
  })
  
  last_time = current_time
  logger.debug('PROFILER', string.format('%s: +%.2fms (total: %.2fms)', label, delta, elapsed))
end

-- Take memory snapshot
function M.memory_snapshot(label)
  if not is_enabled then
    return
  end
  
  -- Force garbage collection for accurate measurement
  collectgarbage('collect')
  
  local memory_kb = collectgarbage('count')
  table.insert(memory_snapshots, {
    label = label,
    memory_kb = memory_kb,
    timestamp = vim.uv.hrtime()
  })
  
  logger.debug('PROFILER', string.format('%s: %.2f KB memory', label, memory_kb))
end

-- Get performance report
function M.get_report()
  local report = {
    enabled = is_enabled,
    total_time_ms = M.get_total_time(),
    timings = timings,
    memory_snapshots = memory_snapshots,
    summary = {}
  }
  
  if #timings > 0 then
    -- Calculate summary statistics
    local total_delta = 0
    local max_delta = 0
    local max_label = ''
    
    for _, timing in ipairs(timings) do
      total_delta = total_delta + timing.delta
      if timing.delta > max_delta then
        max_delta = timing.delta
        max_label = timing.label
      end
    end
    
    report.summary = {
      total_marks = #timings,
      total_delta_ms = total_delta,
      average_delta_ms = total_delta / #timings,
      slowest_operation = {
        label = max_label,
        time_ms = max_delta
      }
    }
  end
  
  if #memory_snapshots > 0 then
    local min_memory = math.huge
    local max_memory = 0
    
    for _, snapshot in ipairs(memory_snapshots) do
      min_memory = math.min(min_memory, snapshot.memory_kb)
      max_memory = math.max(max_memory, snapshot.memory_kb)
    end
    
    report.memory_summary = {
      snapshots = #memory_snapshots,
      min_memory_kb = min_memory,
      max_memory_kb = max_memory,
      memory_growth_kb = max_memory - min_memory
    }
  end
  
  return report
end

-- Print detailed timing report
function M.report()
  if not is_enabled then
    print('Profiling disabled')
    return
  end
  
  local report = M.get_report()
  
  print(string.format('\n=== Nexus Performance Report ==='))
  print(string.format('Total Time: %.2f ms', report.total_time_ms))
  print(string.format('Timing Marks: %d', #timings))
  
  if report.summary.slowest_operation then
    print(string.format('Slowest Operation: %s (%.2f ms)', 
      report.summary.slowest_operation.label, 
      report.summary.slowest_operation.time_ms))
  end
  
  print('\n--- Detailed Timings ---')
  for i, timing in ipairs(timings) do
    print(string.format('%2d. %s: +%.2fms (%.2fms total)', 
      i, timing.label, timing.delta, timing.elapsed))
  end
  
  if #memory_snapshots > 0 then
    print('\n--- Memory Usage ---')
    for _, snapshot in ipairs(memory_snapshots) do
      print(string.format('%s: %.2f KB', snapshot.label, snapshot.memory_kb))
    end
    
    if report.memory_summary then
      print(string.format('Memory Growth: %.2f KB', report.memory_summary.memory_growth_kb))
    end
  end
  
  print('=== End Report ===\n')
end

-- Get total startup time
function M.get_total_time()
  local current_time = vim.uv.hrtime()
  return (current_time - start_time) / 1000000
end

-- Profile a function execution
function M.profile_function(label, func, ...)
  if not is_enabled then
    return func(...)
  end
  
  M.mark(label .. ' - start')
  local results = {func(...)}
  M.mark(label .. ' - end')
  
  return unpack(results)
end

-- Auto-enable profiling based on environment or config
function M.auto_enable()
  -- Enable if DEBUG environment variable is set
  if vim.env.NEXUS_PROFILE or vim.env.DEBUG then
    M.enable()
    return
  end
  
  -- Enable if config requests it
  local config = require('nexus.config')
  if config.get().enable_profiling then
    M.enable()
    return
  end
  
  -- Keep disabled by default for performance
  M.disable()
end

-- Initialize profiler
function M.init()
  M.auto_enable()
  
  if is_enabled then
    M.mark('profiler_init')
    M.memory_snapshot('init')
  end
end

return M