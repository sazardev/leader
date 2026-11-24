-- ── Dashboard: actions of the start screen (ui/start) ─────────────────────────
local M = {}

--- The start screen's buttons (ui/start): label, shortcut and the command each one runs. "Restore Session" only shows when this
--- folder has a saved session (see utils/session.lua), and "Agents" only when Herdr is there (lua/herdr/).
---@return { label: string, key: string, cmd: string }[]
function M.actions()
  local actions = {
    { label = "Find File", key = "ff", cmd = "Telescope find_files" },
    { label = "Recent Files", key = "fo", cmd = "lua require('recent').open()" },
    { label = "Find Word", key = "fw", cmd = "Telescope live_grep" },
    { label = "Themes", key = "th", cmd = "lua require('nvchad.themes').open()" },
    { label = "Mappings", key = "ch", cmd = "Cheatsheet" },
    { label = "Change Art", key = "ca", cmd = "lua require('ui.arts').pick()" },
  }
  if require("utils.session").exists() then
    table.insert(actions, 1, { label = "Restore Session", key = "rs", cmd = "lua require('utils.session').restore()" })
  end
  if require("herdr").enabled() then
    table.insert(actions, 1, { label = "Agents", key = "ag", cmd = "lua require('herdr.panel').open()" })
  end
  return actions
end

--- `nvdash` table for chadrc: NvChad's own start screen is OFF, `ui/start` draws it
---@return table
function M.config()
  return { load_on_startup = false }
end

return M
