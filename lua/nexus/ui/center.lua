local M = {}

function M.longest_line(lines)
  local longest = 0
  for _, line in ipairs(lines) do
    -- Use vim.fn.strdisplaywidth for proper Unicode width calculation
    local display_width = vim.fn.strdisplaywidth and vim.fn.strdisplaywidth(line) or #line
    longest = math.max(longest, display_width)
  end
  return longest
end

-- Returns the number of leading spaces needed to block-center lines in width
function M.block_padding_amount(lines, width)
  local longest = M.longest_line(lines)
  return math.max(0, math.floor((width - longest) / 2))
end

-- Returns per-line padding amounts for individual centering (array parallel to lines)
function M.individual_padding_amounts(lines, width)
  local amounts = {}
  for _, line in ipairs(lines) do
    local display_width = vim.fn.strdisplaywidth and vim.fn.strdisplaywidth(line) or #line
    table.insert(amounts, math.max(0, math.floor((width - display_width) / 2)))
  end
  return amounts
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

-- Center each line individually (for paragraph-style centering)
function M.center_lines_individually(lines, width)
  local centered = {}
  for _, line in ipairs(lines) do
    local display_width = vim.fn.strdisplaywidth and vim.fn.strdisplaywidth(line) or #line
    local left = math.floor((width - display_width) / 2)
    left = math.max(0, left)
    local padding = string.rep(" ", left)
    table.insert(centered, padding .. line)
  end
  return centered
end

return M