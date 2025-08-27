---@class LinearKeymaps
local M = {}

local linear_state = require('nexus.state.linear')
local linear_component = require('nexus.render.components.linear')
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
      M.show_issue_details(issue, config)
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

return M