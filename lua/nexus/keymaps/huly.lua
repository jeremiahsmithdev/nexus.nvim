--- Huly-specific keymap handlers
--- Handles Huly issue browsing, creation, and status updates
---@module nexus.keymaps.huly

local M = {}

local huly_state = require('nexus.state.huly')
local huly_component = require('nexus.render.components.huly')
local huly_popup = require('nexus.ui.popups.huly')
local actions = require('nexus.actions')
local logger = require('nexus.logger')

--- Handle Enter key in Huly section
function M.handle_enter(current_line, config, buf, render_callback)
  if current_line:match("No API key found") or current_line:match("Invalid API key") or current_line:match("No authentication provided") then
    logger.info('HULY', 'Triggering API key setup')
    M.setup_api_key(config, function()
      render_callback(buf)
    end)
    return
  end

  if current_line:match("Press 'H' to configure") then
    M.handle_setup(buf, render_callback, config)
    return
  end

  local is_issue, identifier = huly_component.is_huly_issue_line(current_line)
  if is_issue and identifier then
    logger.info('HULY', 'Fetching full issue details', { identifier = identifier })
    vim.notify("Loading issue details...", vim.log.levels.INFO)

    -- Fetch full issue details (including description) from API
    local provider = huly_state.get_cached_provider()
    local full_issue, err = provider:get_issue(identifier)

    if full_issue then
      logger.info('HULY', 'Opening Huly issue', {
        identifier = full_issue.identifier,
        has_description = full_issue.description ~= nil and full_issue.description ~= ""
      })
      M.show_huly_issue_details(full_issue, config)
    else
      logger.warn('HULY', 'Could not fetch full issue details', {
        identifier = identifier,
        error = err
      })
      -- Show error but ALSO try to show cached version (clearly marked as cached)
      vim.notify("Note: Showing cached data (API fetch failed: " .. (err or "Unknown") .. ")", vim.log.levels.WARN)
      local issues = huly_state.get_issues()
      local cached_issue = huly_component.get_issue_from_line(current_line, issues)
      if cached_issue then
        -- Mark that this is cached data without full description
        cached_issue._cached = true
        M.show_huly_issue_details(cached_issue, config)
      else
        vim.notify("Could not load issue: " .. (err or "Unknown error"), vim.log.levels.ERROR)
      end
    end
  end
end

--- Handle 'c' key in Huly section - create new issue
function M.handle_create(buf, render_callback, config)
  logger.info('HULY', 'Starting issue creation')

  -- First, ensure we have a project selected
  local current_project = huly_state.get_current_project()
  if not current_project then
    logger.info('HULY', 'No project selected, prompting for project selection')
    M.select_project_for_issue(buf, render_callback, config)
    return
  end

  -- Get title
  vim.ui.input({
    prompt = 'Issue title: ',
    default = ''
  }, function(title)
    if not title or title == '' then
      logger.info('HULY', 'Issue creation cancelled')
      return
    end

    -- Get description
    vim.ui.input({
      prompt = 'Issue description (optional): ',
      default = ''
    }, function(description)
      -- Get priority
      vim.ui.select({
        'low', 'medium', 'high', 'urgent'
      }, {
        prompt = 'Select priority:',
        kind = 'huly_priority'
      }, function(priority)
        if not priority then
          logger.info('HULY', 'Issue creation cancelled')
          return
        end

        -- Create the issue
        local issue_data = {
          title = title,
          description = description or "",
          priority = priority,
          project_id = current_project
        }

        huly_state.create_issue(issue_data, function(issue, error)
          if error then
            logger.error('HULY', 'Failed to create issue', { error = error })
            vim.notify("Failed to create issue: " .. error, vim.log.levels.ERROR)
          else
            logger.info('HULY', 'Issue created successfully', {
              id = issue.id,
              identifier = issue.identifier
            })
            vim.notify("Issue created: " .. (issue.identifier or issue.id), vim.log.levels.INFO)

            -- Refresh the display
            render_callback(buf)
          end
        end)
      end)
    end)
  end)
end

--- Select project for issue creation
function M.select_project_for_issue(buf, render_callback, config)
  -- First select workspace if not already selected
  local current_workspace = huly_state.get_current_workspace()
  if not current_workspace then
    huly_state.select_workspace(function(workspace, error)
      if error then
        logger.error('HULY', 'Failed to select workspace', { error = error })
        vim.notify("Failed to select workspace: " .. error, vim.log.levels.ERROR)
        return
      end

      if workspace then
        -- Now select project
        huly_state.select_project(workspace.name, function(project, error)
          if error then
            logger.error('HULY', 'Failed to select project', { error = error })
            vim.notify("Failed to select project: " .. error, vim.log.levels.ERROR)
            return
          end

          if project then
            -- Now create the issue
            M.handle_create(buf, render_callback, config)
          end
        end)
      end
    end)
  else
    -- Workspace already selected, just select project
    huly_state.select_project(current_workspace, function(project, error)
      if error then
        logger.error('HULY', 'Failed to select project', { error = error })
        vim.notify("Failed to select project: " .. error, vim.log.levels.ERROR)
        return
      end

      if project then
        -- Now create the issue
        M.handle_create(buf, render_callback, config)
      end
    end)
  end
end

--- Handle 'w' key in Huly section - select workspace
function M.handle_workspace_selection(buf, render_callback, config)
  logger.info('HULY', 'Starting workspace selection')

  huly_state.select_workspace(function(workspace, error)
    if error then
      logger.error('HULY', 'Failed to select workspace', { error = error })
      vim.notify("Failed to select workspace: " .. error, vim.log.levels.ERROR)
      return
    end

    if workspace then
      logger.info('HULY', 'Workspace selected', { workspace = workspace.name })
      vim.notify("Workspace selected: " .. workspace.name, vim.log.levels.INFO)

      -- Refresh the display
      render_callback(buf)
    end
  end)
end

--- Handle 'p' key in Huly section - select project
function M.handle_project_selection(buf, render_callback, config)
  logger.info('HULY', 'Starting project selection')

  local current_workspace = huly_state.get_current_workspace()

  huly_state.select_project(current_workspace, function(project, error)
    if error then
      logger.error('HULY', 'Failed to select project', { error = error })
      vim.notify("Failed to select project: " .. error, vim.log.levels.ERROR)
      return
    end

    if project then
      logger.info('HULY', 'Project selected', {
        project = project.name,
        workspace = project.workspace and project.workspace.name
      })
      vim.notify("Project selected: " .. project.name, vim.log.levels.INFO)

      -- Refresh the display
      render_callback(buf)
    end
  end)
end

--- Handle 's' key in Huly section - update issue status
function M.handle_status_update(current_line, buf, render_callback, config)
  local is_issue, identifier = huly_component.is_huly_issue_line(current_line)
  if not is_issue or not identifier then
    return
  end

  local issues = huly_state.get_issues()
  local issue = huly_component.get_issue_from_line(current_line, issues)
  if not issue then
    logger.warn('HULY', 'Could not find issue for status update', { identifier = identifier })
    return
  end

  logger.info('HULY', 'Starting status update', {
    identifier = identifier,
    current_status = issue.status
  })

  -- Get available statuses (these are project-specific in Huly)
  local available_statuses = {
    'todo',
    'in progress',
    'done',
    'canceled',
    'backlog'
  }

  vim.ui.select(available_statuses, {
    prompt = 'Select new status:',
    kind = 'huly_status',
    format_item = function(item)
      return item:gsub("_", " "):gsub("^%l", string.upper)
    end
  }, function(new_status)
    if not new_status then
      logger.info('HULY', 'Status update cancelled')
      return
    end

    -- Update the issue
    huly_state.update_issue(issue.id, { status = new_status }, function(updated_issue, error)
      if error then
        logger.error('HULY', 'Failed to update issue status', { error = error })
        vim.notify("Failed to update status: " .. error, vim.log.levels.ERROR)
      else
        logger.info('HULY', 'Issue status updated', {
          identifier = updated_issue.identifier,
          new_status = new_status
        })
        vim.notify("Status updated to: " .. new_status:gsub("_", " "), vim.log.levels.INFO)

        -- Refresh the display
        render_callback(buf)
      end
    end)
  end)
end

--- Show Huly issue details in a popup
function M.show_huly_issue_details(issue, config)
  logger.info('HULY', 'Showing issue details popup', { identifier = issue.identifier })

  if huly_popup then
    huly_popup.show_issue_details(issue, config)
  else
    -- Fallback: just show basic info in a message
    local message = string.format("Issue: %s\nTitle: %s\nStatus: %s\nPriority: %s",
      issue.identifier or issue.id,
      issue.title or "No title",
      issue.status or "Unknown",
      issue.priority or "None"
    )
    vim.notify(message, vim.log.levels.INFO)
  end
end

--- Setup API key interactively
function M.setup_api_key(config, callback)
  logger.info('HULY', 'Starting API key setup')

  huly_state.setup_api_key(function(success, error)
    if success then
      logger.info('HULY', 'API key setup successful')
      vim.notify("Huly API key setup successful!", vim.log.levels.INFO)

      if callback then
        callback()
      end
    else
      logger.error('HULY', 'API key setup failed', { error = error })
      vim.notify("Failed to setup API key: " .. (error or "Unknown error"), vim.log.levels.ERROR)

      if callback then
        callback()
      end
    end
  end)
end

--- Handle refresh
function M.handle_refresh(buf, render_callback, config)
  logger.info('HULY', 'Manual refresh triggered')

  huly_state.refresh_data(config, function(success, error)
    if success then
      logger.info('HULY', 'Refresh completed successfully')
      vim.notify("Huly issues refreshed", vim.log.levels.INFO)
    else
      logger.error('HULY', 'Refresh failed', { error = error })
      vim.notify("Failed to refresh Huly issues: " .. (error or "Unknown error"), vim.log.levels.ERROR)
    end

    -- Always refresh the display
    render_callback(buf)
  end)
end

--- Handle 'H' key - setup/configure Huly integration
function M.handle_setup(buf, render_callback, config)
  logger.info('HULY', 'Starting Huly setup wizard')

  local config_module = require('nexus.config')
  local current_config = config_module.get()

  -- Check what's currently configured
  local current_token = (current_config.huly and current_config.huly.token) or os.getenv("HULY_TOKEN")
  local current_workspace = (current_config.huly and current_config.huly.workspace) or os.getenv("HULY_WORKSPACE")
  local has_token = current_token and current_token ~= ""
  local has_workspace = current_workspace and current_workspace ~= ""

  local function finish_setup()
    -- Enable Huly in runtime config
    if not current_config.huly then
      current_config.huly = {}
    end
    current_config.huly.enabled = true

    -- Reset provider to pick up new credentials
    huly_state._reset_provider()

    -- Save credentials to disk for persistence
    huly_state._save_persistent_config()

    vim.notify("Huly integration configured! Refreshing...", vim.log.levels.INFO)

    -- Refresh data and re-render
    huly_state.refresh_data(current_config, function(success, error)
      if not success then
        logger.error('HULY', 'Failed to fetch issues after setup', { error = error })
        vim.notify("Failed to connect: " .. (error or "Unknown error"), vim.log.levels.ERROR)
      end
      render_callback(buf)
    end)
  end

  local function prompt_workspace(callback)
    vim.ui.input({
      prompt = 'Enter Huly workspace name: ',
      default = current_workspace or ''
    }, function(workspace)
      if not workspace or workspace == '' then
        vim.notify("Huly setup cancelled", vim.log.levels.WARN)
        return
      end

      -- Store in runtime config
      if not current_config.huly then
        current_config.huly = {}
      end
      current_config.huly.workspace = workspace

      logger.info('HULY', 'Workspace configured', { workspace = workspace })
      callback()
    end)
  end

  local function prompt_token(callback)
    vim.ui.input({
      prompt = 'Enter Huly API token (from workspace settings): ',
      default = ''
    }, function(token)
      if not token or token == '' then
        vim.notify("Huly setup cancelled", vim.log.levels.WARN)
        return
      end

      -- Store in runtime config
      if not current_config.huly then
        current_config.huly = {}
      end
      current_config.huly.token = token

      logger.info('HULY', 'Token configured')
      callback()
    end)
  end

  local function run_full_setup()
    prompt_token(function()
      prompt_workspace(finish_setup)
    end)
  end

  -- If already configured, offer options
  if has_token and has_workspace then
    vim.ui.select({
      'Refresh issues',
      'Change token',
      'Change workspace',
      'Reconfigure all',
    }, {
      prompt = 'Huly is configured. What would you like to do?'
    }, function(choice)
      if not choice then return end

      if choice == 'Refresh issues' then
        finish_setup()
      elseif choice == 'Change token' then
        prompt_token(finish_setup)
      elseif choice == 'Change workspace' then
        prompt_workspace(finish_setup)
      elseif choice == 'Reconfigure all' then
        run_full_setup()
      end
    end)
  elseif not has_token then
    prompt_token(function()
      if not has_workspace then
        prompt_workspace(finish_setup)
      else
        finish_setup()
      end
    end)
  else
    prompt_workspace(finish_setup)
  end
end

--- Browse issue in browser (placeholder - would need URL construction)
function M.browse_issue(current_line)
  local is_issue, identifier = huly_component.is_huly_issue_line(current_line)
  if not is_issue or not identifier then
    return
  end

  local issues = huly_state.get_issues()
  local issue = huly_component.get_issue_from_line(current_line, issues)
  if not issue then
    logger.warn('HULY', 'Could not find issue for browsing', { identifier = identifier })
    return
  end

  -- Construct URL (this would depend on Huly's URL structure)
  local url = nil
  if issue.workspace and issue.identifier then
    -- Example URL structure - this may need adjustment based on actual Huly URLs
    url = string.format("https://huly.app/workspace/%s/tracker/issue/%s",
      issue.workspace.name or "default", issue.identifier)
  end

  if url then
    logger.info('HULY', 'Opening issue in browser', { url = url })
    vim.ui.open(url)
  else
    logger.warn('HULY', 'Could not construct URL for issue', { issue = issue })
    vim.notify("Could not open issue in browser", vim.log.levels.WARN)
  end
end

return M