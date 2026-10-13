-- ── Dashboard (NvChad's nvdash) ──────────────────────────────────────────────
-- Split into: header (art, see ui/arts), git info and action buttons. Each part is
-- an independent function/table; `buttons()` only composes them.
local M = {}

--- Actions: { text, shortcut, command }
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

--- Repo (branch) and git user, if the cwd is inside a repository
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
  -- only if this folder has a saved session (see utils/session.lua)
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

--- `nvdash` table for chadrc
---@return table
function M.config()
  return {
    load_on_startup = true,
    header = require("ui.arts").lines,
    buttons = M.buttons,
  }
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
