local M = {}

function M.longest_line(lines)
  local longest = 0
  for _, line in ipairs(lines) do
    longest = math.max(longest, #line)
  end
  return longest
end

function M.center_lines(lines, width)
  -- Use alpha-nvim's centering approach
  local longest = M.longest_line(lines)
  local left = math.floor((width - longest) / 2)
  left = math.max(0, left)
  local padding = string.rep(" ", left)
  
  local centered = {}
  for _, line in ipairs(lines) do
    table.insert(centered, padding .. line)
  end
  return centered
end

return M