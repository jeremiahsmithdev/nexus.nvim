--- Linear-specific keymap handlers
--- Handles Linear issue browsing, creation, and status updates
---@module nexus.keymaps.linear

local M = {}

local linear_state = require('nexus.state.linear')
local linear_component = require('nexus.render.components.linear')
local linear_popup = require('nexus.ui.popups.linear')
local actions = require('nexus.actions')
local logger = require('nexus.logger')

--- Handle Enter key in Linear section
function M.handle_enter(current_line, config, buf, render_callback)
  if current_line:match("No API key found") or current_line:match("Invalid API key") then
    logger.info('LINEAR', 'Triggering API key setup')
    M.setup_api_key(config, function()
      render_callback(buf)
    end)
    return
  end
  
  local is_issue, identifier = linear_component.is_linear_issue_line(current_line)
  if is_issue and identifier then
    local issues = linear_state.get_issues()
    local issue = linear_component.get_issue_from_line(current_line, issues)
    if issue and issue.url then
      logger.info('LINEAR', 'Opening Linear issue', {
        identifier = issue.identifier,
        url = issue.url
      })
      linear_popup.show_linear_issue_details(issue, config)
    else
      logger.warn('LINEAR', 'Could not find issue data', {
        identifier = identifier,
        issue = issue
      })
    end
  end
end

--- Handle 'c' key in Linear section - create new issue
function M.handle_create(buf, render_callback, config)
  logger.info('LINEAR', 'Starting issue creation')
  
  -- Get title
  vim.ui.input({ 
    prompt = 'Issue title: ',
    default = ''
  }, function(title)
    if not title or #title == 0 then
      return
    end
    
    -- Get description (optional)
    vim.ui.input({ 
      prompt = 'Issue description (optional): ',
      default = ''
    }, function(description)
      local linear_provider = require('nexus.providers.linear'):new(config.linear)
      
      -- Try to get team/project info from existing issues
      local issues = linear_state.get_issues()
      local team_id, project_id
      
      if issues and #issues > 0 then
        -- Use team and project from first available issue
        local first_issue = issues[1]
        if first_issue.team then
          team_id = first_issue.team.id
        end
        if first_issue.project then
          project_id = first_issue.project.id
        end
        
        logger.debug('LINEAR', 'Using team and project from existing issues', {
          team_id = team_id,
          team_name = first_issue.team and first_issue.team.name,
          project_id = project_id,
          project_name = first_issue.project and first_issue.project.name
        })
      end
      
      local issue_data = {
        title = title,
        description = description or "",
        team_id = team_id,
        project_id = project_id
      }
      
      local issue, err = linear_provider:create_issue(issue_data)
      
      if issue then
        logger.info('LINEAR', 'Issue created successfully', {
          identifier = issue.identifier,
          title = issue.title
        })
        vim.notify(string.format("Created issue %s: %s", issue.identifier, issue.title), vim.log.levels.INFO)
        
        -- Refresh Linear data to show the new issue
        linear_state.refresh_issues(config)
        render_callback(buf)
      else
        logger.error('LINEAR', 'Failed to create issue', { error = err })
        vim.notify(string.format("Failed to create issue: %s", err or "Unknown error"), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Show Linear issue details popup
function M.show_issue_details(issue, config)
  local issue_details = {}
  
  -- Header
  table.insert(issue_details, string.format("[%s] %s", issue.identifier, issue.title))
  table.insert(issue_details, string.rep("=", #issue_details[1]))
  table.insert(issue_details, "")
  
  -- Status and Priority
  if issue.state then
    table.insert(issue_details, string.format("Status: %s", issue.state.name))
  end
  
  if issue.priority and issue.priority > 0 then
    local priority_names = { "Low", "Medium", "High", "Urgent" }
    local priority_name = priority_names[issue.priority] or "Unknown"
    table.insert(issue_details, string.format("Priority: %s", priority_name))
  end
  
  table.insert(issue_details, "")
  
  -- Assignee
  if issue.assignee and type(issue.assignee) == "table" and issue.assignee.name then
    table.insert(issue_details, string.format("Assignee: %s", issue.assignee.name))
    table.insert(issue_details, "")
  end
  
  -- Estimate
  if issue.estimate and issue.estimate > 0 then
    table.insert(issue_details, string.format("Estimate: %d point%s", issue.estimate, issue.estimate == 1 and "" or "s"))
    table.insert(issue_details, "")
  end
  
  -- Cycle/Sprint
  if issue.cycle and type(issue.cycle) == "table" and issue.cycle.name then
    table.insert(issue_details, string.format("Cycle: %s", issue.cycle.name))
    table.insert(issue_details, "")
  end
  
  -- Description
  if issue.description and #issue.description > 0 then
    table.insert(issue_details, "Description:")
    table.insert(issue_details, issue.description)
    table.insert(issue_details, "")
  end
  
  -- URLs and actions
  table.insert(issue_details, "Actions:")
  table.insert(issue_details, "  o - Open in browser")
  table.insert(issue_details, "  q - Close")
  
  -- Create popup
  local popup_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(popup_buf, 0, -1, false, issue_details)
  
  -- Calculate popup size
  local width = math.min(80, math.max(50, vim.fn.max(vim.tbl_map(vim.fn.strlen, issue_details)) + 4))
  local height = math.min(20, #issue_details + 2)
  
  -- Center the popup
  local ui = vim.api.nvim_list_uis()[1]
  local popup_win = vim.api.nvim_open_win(popup_buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = (ui.height - height) / 2,
    col = (ui.width - width) / 2,
    style = 'minimal',
    border = 'rounded',
    title = ' Linear Issue ',
    title_pos = 'center'
  })
  
  -- Set popup options
  vim.api.nvim_buf_set_option(popup_buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(popup_buf, 'readonly', true)
  
  -- Keymaps for popup
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'q', '<cmd>close<cr>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', '<Esc>', '<cmd>close<cr>', { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(popup_buf, 'n', 'o', '', {
    noremap = true,
    silent = true,
    callback = function()
      if issue.url then
        vim.fn.jobstart({'open', issue.url}, { detach = true })
      end
      vim.cmd('close')
    end
  })
end

--- Setup Linear API key
function M.setup_api_key(config, callback)
  vim.ui.input({ 
    prompt = 'Enter Linear API key: ',
    default = ''
  }, function(api_key)
    if api_key and #api_key > 0 then
      -- Update environment variable
      vim.env.LINEAR_API_KEY = api_key
      
      -- Update config
      if not config.linear then
        config.linear = {}
      end
      config.linear.api_key = api_key
      
      vim.notify("Linear API key configured. Refreshing data...", vim.log.levels.INFO)
      
      -- Trigger callback to refresh
      if callback then
        callback()
      end
    end
  end)
end

--- Handle Linear status update for current issue
function M.handle_status_update(buf, render_callback, config)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_line = lines[line_num]
  
  if not current_line then return end
  
  local is_issue, identifier = linear_component.is_linear_issue_line(current_line)
  if is_issue and identifier then
    local issues = linear_state.get_issues()
    local issue = linear_component.get_issue_from_line(current_line, issues)
    if issue then
      -- Use existing Linear status update functionality
      -- This would typically involve showing status selection UI
      vim.notify("Linear status update - functionality available in popup (Enter -> 's')", vim.log.levels.INFO)
    end
  end
end

--- Handle Linear project selection 
function M.handle_project_selection(buf, render_callback, config)
  logger.info('LINEAR', 'Starting project selection')
  
  -- Show project selection modal (two-step: team -> project)
  M.show_project_selection_modal(config, function(new_team_id, new_project_id)
    if new_team_id then
      logger.info('LINEAR', 'Updating team/project selection', {
        new_team_id = new_team_id,
        new_project_id = new_project_id
      })
      
      -- Update config for this session
      if not config.linear then
        config.linear = {}
      end
      config.linear.team_id = new_team_id
      if new_project_id then
        config.linear.project_id = new_project_id
        
        -- Save project selection to persistent cache
        local provider = linear_state.get_cached_provider(config)
        if provider then
          local projects = provider:get_projects(new_team_id)
          if projects then
            for _, project in ipairs(projects) do
              if project.id == new_project_id then
                M.save_project_selection(project, config)
                break
              end
            end
          end
        end
      end
      
      vim.notify("Switching Linear project...", vim.log.levels.INFO)
      
      -- Force refresh Linear data with new team/project
      linear_state.refresh_data(config)
      
      -- Re-render the buffer after a short delay to allow data refresh
      vim.defer_fn(function()
        render_callback(buf)
      end, 500)
    end
  end)
end

--- Save project selection to persistent cache
---@param project table The selected project
---@param config table Nexus configuration  
function M.save_project_selection(project, config)
  local cwd = vim.fn.getcwd()
  local cache_file = vim.fn.stdpath('cache') .. '/nexus_linear_projects.json'
  
  -- Load existing selections
  local selections = {}
  if vim.fn.filereadable(cache_file) == 1 then
    local content = vim.fn.readfile(cache_file)
    if content and #content > 0 then
      local ok, parsed = pcall(vim.json.decode, table.concat(content, '\n'))
      if ok and parsed then
        selections = parsed
      end
    end
  end
  
  -- Save selection for current directory
  selections[cwd] = {
    project_id = project.id,
    project_name = project.name,
    selected_at = os.time()
  }
  
  -- Write back to cache
  local ok, encoded = pcall(vim.json.encode, selections)
  if ok then
    vim.fn.writefile({encoded}, cache_file)
    logger.info('LINEAR', 'Saved project selection', {
      cwd = cwd,
      project = project.name
    })
  end
end

--- Load project selection from persistent cache
---@param config table Nexus configuration
---@return string|nil project_id The cached project ID for current directory
function M.load_project_selection(config)
  local cwd = vim.fn.getcwd()
  local cache_file = vim.fn.stdpath('cache') .. '/nexus_linear_projects.json'
  
  if vim.fn.filereadable(cache_file) ~= 1 then
    return nil
  end
  
  local content = vim.fn.readfile(cache_file)
  if not content or #content == 0 then
    return nil
  end
  
  local ok, selections = pcall(vim.json.decode, table.concat(content, '\n'))
  if not ok or not selections or not selections[cwd] then
    return nil
  end
  
  local selection = selections[cwd]
  logger.info('LINEAR', 'Loaded cached project selection', {
    cwd = cwd,
    project = selection.project_name
  })
  
  return selection.project_id
end

--- Show project selection modal (two-step: team then project)
function M.show_project_selection_modal(config, callback)
  logger.info('LINEAR', 'Showing project selection modal')
  
  -- Get cached Linear provider
  local provider = linear_state.get_cached_provider(config)
  
  if not provider then
    vim.notify("Failed to get Linear provider", vim.log.levels.ERROR)
    return
  end
  
  -- Step 1: Get available teams
  local teams, error_msg = provider:get_teams()
  
  if not teams then
    vim.notify("Failed to fetch Linear teams: " .. (error_msg or "Unknown error"), vim.log.levels.ERROR)
    return
  end
  
  if #teams == 0 then
    vim.notify("No Linear teams available", vim.log.levels.WARN)
    return
  end
  
  -- Sort teams by name
  table.sort(teams, function(a, b) 
    return a.name < b.name 
  end)
  
  -- Create team selection menu
  local team_options = {}
  local current_team_idx = nil
  
  for i, team in ipairs(teams) do
    local display_name = string.format("%s (%s)", team.name, team.key)
    if config.linear.team_id and config.linear.team_id == team.id then
      display_name = display_name .. " (current)"
      current_team_idx = i
    end
    table.insert(team_options, display_name)
  end
  
  -- Show team selection using vim.ui.select
  vim.ui.select(team_options, {
    prompt = "Step 1: Select Linear team:",
    format_item = function(item)
      return "  " .. item
    end,
  }, function(choice, idx)
    if choice and idx then
      local selected_team = teams[idx]
      logger.info('LINEAR', 'Team selected', { 
        team_name = selected_team.name,
        team_id = selected_team.id
      })
      
      -- Step 2: Get projects for the selected team
      M.show_team_projects_selection(provider, selected_team, config, callback)
    else
      logger.debug('LINEAR', 'Team selection cancelled')
    end
  end)
end

--- Show projects selection for a specific team
function M.show_team_projects_selection(provider, selected_team, config, callback)
  logger.info('LINEAR', 'Showing projects for team', { team_name = selected_team.name })
  
  -- Get projects for the selected team
  local projects, error_msg = provider:get_projects(selected_team.id)
  
  if not projects then
    vim.notify("Failed to fetch projects for " .. selected_team.name .. ": " .. (error_msg or "Unknown error"), vim.log.levels.ERROR)
    -- Still allow team-only selection
    callback(selected_team.id, nil)
    return
  end
  
  if #projects == 0 then
    vim.notify("No active projects in " .. selected_team.name .. ". Selecting team only.", vim.log.levels.INFO)
    callback(selected_team.id, nil)
    return
  end
  
  -- Sort projects by name
  table.sort(projects, function(a, b) 
    return a.name < b.name 
  end)
  
  -- Create project selection menu with team-only option
  local project_options = {"[No specific project - team only]"}
  local current_project_idx = nil
  
  for i, project in ipairs(projects) do
    local display_name = project.name
    if project.description and project.description ~= "" then
      display_name = display_name .. " - " .. project.description:gsub("\n.*", ""):sub(1, 50) -- First line, truncated
    end
    
    if config.linear.project_id and config.linear.project_id == project.id then
      display_name = display_name .. " (current)"
      current_project_idx = i + 1 -- +1 because of the "no project" option
    end
    table.insert(project_options, display_name)
  end
  
  -- Show project selection
  vim.ui.select(project_options, {
    prompt = string.format("Step 2: Select project in %s:", selected_team.name),
    format_item = function(item)
      return "  " .. item
    end,
  }, function(choice, idx)
    if choice and idx then
      if idx == 1 then
        -- Selected "no specific project"
        logger.info('LINEAR', 'Team-only selection', { 
          team_name = selected_team.name,
          team_id = selected_team.id
        })
        callback(selected_team.id, nil)
      else
        -- Selected a specific project
        local selected_project = projects[idx - 1] -- -1 because of the "no project" option
        logger.info('LINEAR', 'Team and project selected', { 
          team_name = selected_team.name,
          team_id = selected_team.id,
          project_name = selected_project.name,
          project_id = selected_project.id
        })
        callback(selected_team.id, selected_project.id)
      end
    else
      logger.debug('LINEAR', 'Project selection cancelled')
    end
  end)
end

return M