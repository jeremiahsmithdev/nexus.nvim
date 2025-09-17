local M = {}

function M.get_dashboard_buttons(config)
  local config_module = require('nexus.config')
  if not config_module.is_section_enabled("dashboard_buttons") then
    return {}
  end
  
  return {
    "󰈞  Find file                   SPC f",
    "󰋚  Recently opened files       SPC r", 
    "󰊄  Find word                   SPC w",
    "󰈔  New file                    SPC n",
    "󰃃  Bookmarks                   SPC b",
    "󰁯  Restore session             SPC s",
    ""
  }
end

return M
