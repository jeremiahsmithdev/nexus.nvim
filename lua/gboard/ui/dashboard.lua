local M = {}

function M.get_dashboard_buttons(config)
  if not config.show_dashboard_buttons then
    return {}
  end
  
  return {
    "",
    "    Find file                   SPC f f",
    "    Recently opened files       SPC f h", 
    "    Find word                   SPC f g",
    "    New file                    SPC f n",
    "    Bookmarks                   SPC b m",
    "    Restore session             SPC s s",
    ""
  }
end

return M
