-- ── Highlight overrides (base46) ─────────────────────────────────────────────
-- Colors refer to the theme palette (base0C, orange...).
local M = {}

-- Functions: the theme used base0D (muted blue) for names/calls.
-- Changed to vivid aqua (base0C, already used in @constructor) + bold.
local FUNCTION_GROUPS = {
  "Function",
  "@function",
  "@function.builtin",
  "@function.call",
  "@function.method",
  "@function.method.call",
}

-- Operators: the theme painted them with the same blue as functions.
local OPERATOR_GROUPS = { "Operator", "@operator" }

---@return table
function M.overrides()
  local hl = {
    Comment = { italic = true },
    ["@comment"] = { italic = true },
    St_gitIcons = { fg = "white", bg = "lightbg", bold = true },
  }
  for _, group in ipairs(FUNCTION_GROUPS) do
    hl[group] = { fg = "base0C", bold = true }
  end
  for _, group in ipairs(OPERATOR_GROUPS) do
    hl[group] = { fg = "orange" }
  end
  return hl
end

return M
