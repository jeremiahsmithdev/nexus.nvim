local M = {}

function M.get_dashboard_buttons(config)
  if not config.show_dashboard_buttons then
    return {}
  end
  
  return {
    "",
    "    󰈞  Find file                   SPC f",
    "    󰋚  Recently opened files       SPC r", 
    "    󰊄  Find word                   SPC w",
    "    󰈔  New file                    SPC n",
    "    󰃃  Bookmarks                   SPC b",
    "    󰁯  Restore session             SPC s",
    ""
  }
end

return M
