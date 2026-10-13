-- ── Commit panel colors ──────────────────────────────────────────────────────
-- They are DERIVED from the agent's (which in turn come from the active theme palette): the panel looks equally good in
-- any theme and shares background, border and titles with <leader>a. Only its own accents are added (staged,
-- added/removed, validation) with guaranteed minimum contrast over the floating background.
local color = require "appearance.color"

local M = {}

---@param names string[]
---@param fallback string
---@return string
local function accent(names, fallback)
  for _, name in ipairs(names) do
    local fg = vim.api.nvim_get_hl(0, { name = name, link = false }).fg
    if fg then
      return ("#%06x"):format(fg)
    end
  end
  return fallback
end

function M.apply()
  require("agent.ui.highlights").apply()
  local float = vim.api.nvim_get_hl(0, { name = "AgentFloat", link = false })
  local bg = float.bg and ("#%06x"):format(float.bg) or "#1a1a1a"
  local fg = float.fg and ("#%06x"):format(float.fg) or "#dddddd"

  local green = accent({ "Added", "GitSignsAdd", "DiagnosticOk" }, "#5faf5f")
  local red = accent({ "Removed", "GitSignsDelete", "DiagnosticError" }, "#d75f5f")
  local yellow = accent({ "DiagnosticWarn" }, "#d7af5f")
  local blue = accent({ "DiagnosticInfo", "Function" }, "#5f87d7")
  local function strong(c)
    return color.ensure_contrast(c, bg, fg, 4.5)
  end
  local dim = color.ensure_contrast(color.blend(fg, bg, 0.5), bg, fg, 3.6)

  local groups = {
    CommitOk = { fg = strong(green), bg = bg, bold = true },
    CommitErr = { fg = strong(red), bg = bg, bold = true },
    CommitWarn = { fg = strong(yellow), bg = bg },
    CommitInfo = { fg = strong(blue), bg = bg },
    CommitAdd = { fg = strong(green), bg = bg },
    CommitDel = { fg = strong(red), bg = bg },
    CommitChanged = { fg = strong(blue), bg = bg },
    CommitStaged = { fg = strong(green), bg = bg, bold = true },
    CommitUnstaged = { fg = dim, bg = bg },
    CommitDim = { fg = dim, bg = bg },
    CommitHeader = { fg = strong(blue), bg = bg, bold = true },
    CommitAI = { fg = strong(blue), bg = bg, bold = true },
    CommitCursor = { bg = color.blend(bg, blue, 0.16) },
  }
  for name, def in pairs(groups) do
    vim.api.nvim_set_hl(0, name, def)
  end
end

local ready = false

--- Defines the groups and hooks into theme changes. Idempotent
function M.ensure()
  if ready then
    return
  end
  ready = true
  M.apply()
  local group = vim.api.nvim_create_augroup("CommitHighlights", { clear = true })
  -- after the agent's (registered earlier): we must start from their already recalculated colors
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.apply })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "NvThemeReload", callback = M.apply })
end

return M
