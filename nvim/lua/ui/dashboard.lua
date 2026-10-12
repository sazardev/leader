-- ── Dashboard (nvdash de NvChad) ─────────────────────────────────────────────
-- Separado en: header (arte, ver ui/arts), info de git y botones de acción. Cada parte es
-- una función/tabla independiente; `buttons()` solo las compone.
local M = {}

--- Acciones: { texto, atajo, comando }
local ACTIONS = {
  { "  Find File", "ff", "Telescope find_files" },
  { "  Recent Files", "fo", "Telescope oldfiles" },
  { "  Find Word", "fw", "Telescope live_grep" },
  { "  Themes", "th", ":lua require('nvchad.themes').open()" },
  { "  Mappings", "ch", "NvCheatsheet" },
  { "  Change Art", "ca", "lua require('ui.arts').pick()" },
}

local function separator()
  return { txt = " ", hl = "NvDashFooter", no_gap = true, rep = true }
end

--- Repo (rama) y usuario de git, si el cwd está en un repositorio
---@return table[]
local function git_info()
  local info = require("utils.git").info()
  local lines = {}

  if info.repo ~= "" then
    local label = info.branch ~= "" and ("  %s (%s)"):format(info.repo, info.branch) or ("  " .. info.repo)
    table.insert(lines, { txt = label, hl = "NvDashFooter", no_gap = true, content = "fit" })
  end
  if info.user ~= "" then
    table.insert(lines, { txt = "  " .. info.user, hl = "Comment", no_gap = true, content = "fit" })
  end
  return lines
end

---@return table[]
local function action_buttons()
  local actions = vim.list_slice(ACTIONS)
  -- solo si esta carpeta tiene una sesión guardada (ver utils/session.lua)
  if require("utils.session").exists() then
    table.insert(actions, 1, { "  Restore Session", "rs", "lua require('utils.session').restore()" })
  end
  return vim.tbl_map(function(action)
    return { txt = action[1], keys = action[2], cmd = action[3] }
  end, actions)
end

---@return table[]
function M.buttons()
  local buttons = { separator() }
  vim.list_extend(buttons, git_info())
  table.insert(buttons, separator())
  vim.list_extend(buttons, action_buttons())
  return buttons
end

--- Tabla `nvdash` para chadrc
---@return table
function M.config()
  return {
    load_on_startup = true,
    header = require("ui.arts").lines,
    buttons = M.buttons,
  }
end

--- Tabla `cheatsheet` para chadrc (botón Mappings → NvCheatsheet).
--- NvCheatsheet lista TODOS los keymaps con desc y agrupa por su primera palabra, así que
--- aquí se excluyen los grupos de teclas nativas de Neovim. Los grupos propios salen de la
--- convención de `desc` ("Harpoon add file", "Go run"...: ver utils/cheatsheet.lua).
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
      -- nativos de Neovim 0.11+
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
