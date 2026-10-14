-- ── Agent highlight groups ───────────────────────────────────────────────────
-- Colors are DERIVED from the active theme's palette (the real background, text and accents of
-- Normal/Added/Removed/Diagnostic*) instead of linking to Diff*/Comment, whose meaning
-- varies a lot between themes: so the diff, the spinner and the hint are readable in the ~100
-- base46 themes, light or dark, and in the theme inherited from the terminal.
-- They are recomputed when base46 reloads a theme (`User NvThemeReload`) or the colorscheme changes.
local color = require "appearance.color"

local M = {}

---@param name string
---@return table
local function get(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

---@param n integer?
---@return string?
local function hex(n)
  return n and ("#%06x"):format(n) or nil
end

--- First foreground color defined among the candidate groups
---@param names string[]
---@param fallback string
---@return string
local function accent(names, fallback)
  for _, name in ipairs(names) do
    local fg = hex(get(name).fg)
    if fg then
      return fg
    end
  end
  return fallback
end

--- Hue (0-360) of a color; 0 if it is gray
---@param hexcolor string
---@return number
local function hue(hexcolor)
  local r, g, b = color.to_rgb(hexcolor)
  r, g, b = r / 255, g / 255, b / 255
  local max, min = math.max(r, g, b), math.min(r, g, b)
  if max == min then
    return 0
  end
  local d = max - min
  local h
  if max == r then
    h = ((g - b) / d) % 6
  elseif max == g then
    h = (b - r) / d + 2
  else
    h = (r - g) / d + 4
  end
  return h * 60
end

--- The accent if its hue is within [lo, hi] (wrapping at 360); otherwise the canonical one.
--- Keeps "added" and "deleted" from looking alike in themes whose accents are not green/red.
---@param candidate string
---@param lo number
---@param hi number
---@param canonical string
---@return string
local function with_hue(candidate, lo, hi, canonical)
  local h = hue(candidate)
  local inside = lo <= hi and (h >= lo and h <= hi) or (lo > hi and (h >= lo or h <= hi))
  return inside and candidate or canonical
end

--- Background tinted with `tint`, strong enough to be seen over `bg` but without
--- the `fg` text dropping below 4.5:1
---@param bg string
---@param tint string
---@param fg string
---@param visible number minimum contrast of the tinted background against `bg`
---@return string
local function tinted(bg, tint, fg, visible)
  local best = color.blend(bg, tint, 0.14)
  for alpha = 0.14, 0.46, 0.04 do
    local candidate = color.blend(bg, tint, alpha)
    if color.contrast(fg, candidate) < 4.5 then
      break
    end
    best = candidate
    if color.contrast(candidate, bg) >= visible then
      break
    end
  end
  return best
end

---@return table<string, table>
local function derive()
  local flat = require "ui.flat"
  if flat.enabled() then
    return require("ui.flat.groups").agent(require("ui.flat.palette").current()) -- the flat design (ui/flat) owns these colors
  end
  local dark = vim.o.background ~= "light"
  local normal = get "Normal"
  local bg = hex(normal.bg) or (dark and "#1a1a1a" or "#fafafa")
  local fg = hex(normal.fg) or (dark and "#dddddd" or "#222222")
  local float_bg = hex(get("NormalFloat").bg) or bg

  local green = accent({ "Added", "GitSignsAdd", "DiagnosticOk", "String" }, "#5faf5f")
  local red = accent({ "Removed", "GitSignsDelete", "DiagnosticError", "ErrorMsg" }, "#d75f5f")
  local blue = accent({ "DiagnosticInfo", "Function", "Special" }, "#5f87d7")
  local border = accent({ "FloatBorder", "Special" }, blue)

  green = with_hue(green, 70, 170, "#4fa04f")
  red = with_hue(red, 340, 25, "#d04848")

  local add_bg = tinted(bg, green, fg, 1.16)
  local del_bg = tinted(bg, red, fg, 1.16)
  local input_bg = color.blend(bg, blue, 0.10)
  local status_bg = color.blend(bg, blue, 0.12)
  local done_bg = color.blend(bg, green, 0.12)
  local comment = accent({ "Comment" }, color.blend(fg, bg, 0.5))

  return {
    -- the code that was sent, while it runs: a veil barely stronger than the background
    AgentTarget = { bg = tinted(bg, fg, fg, 1.05) },
    AgentStatus = { fg = color.ensure_contrast(blue, status_bg, fg, 4.5), bg = status_bg, bold = true },
    AgentDone = { fg = color.ensure_contrast(green, done_bg, fg, 4.5), bg = done_bg },
    -- it carries the accept/reject keys: it must be readable, not hidden like a comment
    AgentHint = { fg = color.ensure_contrast(comment, bg, fg, 4.5), italic = true },
    AgentDiffAdd = { fg = fg, bg = add_bg },
    AgentDiffDelete = { bg = del_bg },
    -- inline instruction block: its own bluish veil, with the accent bar on the left
    AgentInput = { fg = fg, bg = input_bg },
    AgentInputBar = { fg = color.ensure_contrast(blue, input_bg, fg, 3.0), bg = input_bg },
    AgentInputTitle = { fg = color.ensure_contrast(blue, input_bg, fg, 4.5), bg = input_bg, bold = true },
    AgentInputMeta = { fg = color.ensure_contrast(color.blend(fg, input_bg, 0.45), input_bg, fg, 4.5), bg = input_bg },
    AgentInputHint = {
      fg = color.ensure_contrast(color.blend(fg, input_bg, 0.45), input_bg, fg, 4.5),
      bg = input_bg,
      italic = true,
    },
    AgentInputPlaceholder = {
      fg = color.ensure_contrast(color.blend(fg, input_bg, 0.55), input_bg, fg, 3.2),
      bg = input_bg,
      italic = true,
    },
    AgentFloat = { fg = fg, bg = float_bg },
    AgentBorder = { fg = color.ensure_contrast(border, float_bg, fg, 1.8), bg = float_bg },
    AgentTitle = { fg = color.ensure_contrast(blue, float_bg, fg, 4.5), bg = float_bg, bold = true },
  }
end

function M.apply()
  for name, def in pairs(derive()) do
    vim.api.nvim_set_hl(0, name, def)
  end
end

local ready = false

--- Defines the groups and hooks into theme changes. Idempotent: every agent UI entry point
--- (pipeline, inline prompt, panels, answer window) calls it, because not all of them go through the
--- `agent` facade: the DDD menu goes straight to `agent.ddd` and without this its blocks came out flat white.
function M.ensure()
  if ready then
    return
  end
  ready = true
  M.apply()
  local group = vim.api.nvim_create_augroup("AgentHighlights", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.apply })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "NvThemeReload", callback = M.apply })
end

M.setup = M.ensure -- previous name (used by the facade)

return M
