local M = {}

-- Registry of section-specific shortcuts
-- Each section can define shortcuts that are available when cursor is in that section
local shortcuts_registry = {
  dashboard_buttons = {
    {key = "<Enter>", action = "activate"}
  },
  
  git_status = {
    {key = "<Enter>", action = "open file"},
    {key = "a", action = "stage"},
    {key = "u", action = "unstage"}
  },
  
  linear_issues = {
    {key = "<Enter>", action = "details"},
    {key = "s", action = "update status"},
    {key = "c", action = "create issue"}
  },
  
  recent_commits = {
    {key = "<Enter>", action = "show commit"},
    {key = "e", action = "review toggle"}
  },
  
  todos = {
    {key = "<Enter>", action = "details"},
    {key = "c", action = "create"},
    {key = "e", action = "edit"},
    {key = "d", action = "done"},
    {key = "D", action = "delete"}
  },
  
  claude_conversations = {
    {key = "<Enter>", action = "resume conversation"}
  },
  
  -- Headers are generally not actionable, but can be expanded if needed
  recent_commits_header = {},
  git_status_header = {},
  linear_issues_header = {},
  todos_header = {},
  claude_conversations_header = {},
  
  -- Logo and keyboard shortcuts sections don't have specific actions
  logo = {},
  keyboard_shortcuts = {},
  
  -- Default/unknown sections
  unknown = {}
}

-- Get shortcuts for a specific section
function M.get_section_shortcuts(section_name)
  return shortcuts_registry[section_name] or shortcuts_registry.unknown
end

-- Format shortcuts as display string
function M.format_shortcuts(shortcuts)
  if not shortcuts or #shortcuts == 0 then
    return ""
  end
  
  local formatted = {}
  for _, shortcut in ipairs(shortcuts) do
    table.insert(formatted, shortcut.key .. " -> " .. shortcut.action)
  end
  
  return table.concat(formatted, ", ")
end

-- Get formatted shortcuts string for a section
function M.get_formatted_section_shortcuts(section_name)
  local shortcuts = M.get_section_shortcuts(section_name)
  return M.format_shortcuts(shortcuts)
end

-- Check if a section has any shortcuts
function M.has_shortcuts(section_name)
  local shortcuts = M.get_section_shortcuts(section_name)
  return shortcuts and #shortcuts > 0
end

-- Add a new shortcut to a section (for easy expansion)
function M.add_shortcut(section_name, key, action)
  if not shortcuts_registry[section_name] then
    shortcuts_registry[section_name] = {}
  end
  
  table.insert(shortcuts_registry[section_name], {key = key, action = action})
end

-- Remove a shortcut from a section
function M.remove_shortcut(section_name, key)
  local section_shortcuts = shortcuts_registry[section_name]
  if not section_shortcuts then
    return
  end
  
  for i = #section_shortcuts, 1, -1 do
    if section_shortcuts[i].key == key then
      table.remove(section_shortcuts, i)
    end
  end
end

-- Get all available sections
function M.get_all_sections()
  local sections = {}
  for section_name, _ in pairs(shortcuts_registry) do
    table.insert(sections, section_name)
  end
  return sections
end

return M
