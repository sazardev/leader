-- ── Dashboard: actions of the start screen (ui/start) and the cheatsheet config ─
local M = {}

--- The start screen's buttons (ui/start): label, shortcut and the command each one runs. "Restore Session" only shows when this
--- folder has a saved session (see utils/session.lua).
---@return { label: string, key: string, cmd: string }[]
function M.actions()
  local actions = {
    { label = "Find File", key = "ff", cmd = "Telescope find_files" },
    { label = "Recent Files", key = "fo", cmd = "lua require('recent').open()" },
    { label = "Find Word", key = "fw", cmd = "Telescope live_grep" },
    { label = "Themes", key = "th", cmd = "lua require('nvchad.themes').open()" },
    { label = "Mappings", key = "ch", cmd = "NvCheatsheet" },
    { label = "Change Art", key = "ca", cmd = "lua require('ui.arts').pick()" },
  }
  if require("utils.session").exists() then
    table.insert(actions, 1, { label = "Restore Session", key = "rs", cmd = "lua require('utils.session').restore()" })
  end
  return actions
end

--- `nvdash` table for chadrc: NvChad's own start screen is OFF, `ui/start` draws it
---@return table
function M.config()
  return { load_on_startup = false }
end

--- `cheatsheet` table for chadrc (Mappings button → NvCheatsheet).
--- NvCheatsheet lists ALL keymaps with a desc and groups them by their first word, so
--- the native Neovim key groups are excluded here. Our own groups come from the
--- `desc` convention ("Harpoon add file", "Go run"...: see utils/cheatsheet.lua).
---@return table
function M.cheatsheet()
  return {
    theme = "grid",
    excluded_groups = {
      -- defaults de NvChad
      "terminal (t)",
      "autopairs",
      "Nvim",
      "Opens",
      -- native to Neovim 0.11+
      ":help",
      "Add",
      "Jump",
      "Select",
      "Show",
      "vim.snippet.jump",
    },
  }
end

return M
