-- File module for Nexus dashboard
-- Handles JSON file generation and reading for .nexus file

local M = {}

local git_state = require('nexus.state.git')

-- Get the .nexus file path in the current git repository
function M.get_nexus_file_path()
  local git_root = git_state.get_git_root()
  if not git_root then
    return nil
  end
  return git_root .. '/.nexus'
end

-- Generate JSON content from dashboard data
function M.generate_json(lines, highlights, metadata)
  local data = {
    lines = lines,
    highlights = highlights,
    metadata = metadata
  }

  return vim.json.encode(data)
end

-- Write dashboard data to .nexus file
function M.write_nexus_file(lines, highlights, metadata)
  local file_path = M.get_nexus_file_path()
  if not file_path then
    return false, "Not in a git repository"
  end

  local json_content = M.generate_json(lines, highlights, metadata)

  local file = io.open(file_path, 'w')
  if not file then
    return false, "Failed to open .nexus file for writing"
  end

  file:write(json_content)
  file:close()

  return true, file_path
end

-- Read and parse .nexus file
function M.read_nexus_file()
  local file_path = M.get_nexus_file_path()
  if not file_path then
    return nil, "Not in a git repository"
  end

  local file = io.open(file_path, 'r')
  if not file then
    return nil, "Failed to open .nexus file for reading"
  end

  local content = file:read('*all')
  file:close()

  if not content or content == '' then
    return nil, "Empty .nexus file"
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return nil, "Failed to parse .nexus JSON: " .. tostring(data)
  end

  return data
end

-- Apply highlights from JSON data to buffer
function M.apply_highlights(buf, highlights)
  if not highlights or #highlights == 0 then
    return
  end

  -- Clear all existing highlights
  vim.api.nvim_buf_clear_namespace(buf, 0, 0, -1)

  -- Apply each highlight
  for _, hl in ipairs(highlights) do
    local ns = vim.api.nvim_create_namespace(hl.ns)
    vim.api.nvim_buf_add_highlight(
      buf,
      ns,
      hl.group,
      hl.line,
      hl.col_start,
      hl.col_end
    )
  end
end

return M
