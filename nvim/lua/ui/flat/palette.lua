-- ── Flat design: color tokens ────────────────────────────────────────────────
-- ONE small set of tokens derived from the active theme (base46 palette: any of its ~100 themes, or the
-- one inherited from the terminal). Every surface of the flat design (floats, pickers, menus, notifications) is
-- painted ONLY with these tokens, so the whole UI changes together when the theme changes.
-- The derivation is the same one the landing page uses (docs/index.html), so web and editor look alike.
local color = require "appearance.color"

local M = {}

local DARK_LUMINANCE = 0.179 -- point where white and black contrast equally

---@class FlatTokens
---@field dark boolean
---@field bg string      the theme's background: the terminal float (the demo's page color)
---@field deep string    one step below it: the editor itself, tree, start screen, input fields (the demo's editor)
---@field soft string    one step above the background (every float, menu and panel)
---@field fg string
---@field dim string     secondary text
---@field faint string   hints, separators, comments
---@field on string      text over a solid accent
---@field red string
---@field green string
---@field yellow string
---@field blue string
---@field purple string
---@field aqua string
---@field orange string

--- Tokens from the two base46 tables (`base_16` and `base_30`)
---@param b16 table
---@param b30 table
---@return FlatTokens
function M.from(b16, b30)
  local bg, fg = b16.base00, b16.base05
  local dark = color.luminance(bg) < DARK_LUMINANCE
  local blend = color.blend
  local function tint(t)
    return blend(bg, fg, t)
  end
  local soft = tint(0.07)
  local function accent(hex, fallback)
    return color.ensure_contrast(hex or fallback, bg, fg, 3.0)
  end
  return {
    dark = dark,
    bg = bg,
    deep = blend(bg, "#000000", dark and 0.25 or 0.05),
    soft = soft,
    fg = fg,
    -- text on the blocks must stay readable on light themes too: pushed toward the foreground until it has enough contrast
    dim = color.ensure_contrast(tint(0.62), soft, fg, 4.0),
    faint = color.ensure_contrast(tint(0.34), soft, fg, 2.0),
    on = dark and blend(bg, "#000000", 0.45) or blend(bg, "#ffffff", 0.65),
    red = accent(b30.red, b16.base08),
    green = accent(b30.green, b16.base0B),
    yellow = accent(b30.sun, b16.base0A),
    blue = accent(b30.nord_blue, b16.base0D),
    purple = accent(b30.dark_purple, b16.base0E),
    aqua = accent(b30.cyan, b16.base0C),
    orange = accent(b30.orange, b16.base09),
  }
end

--- Tokens from the highlight groups already defined (fallback when base46 cannot be read)
---@return FlatTokens
function M.from_highlights()
  local function get(name)
    return vim.api.nvim_get_hl(0, { name = name, link = false })
  end
  local function hex(n, default)
    return n and ("#%06x"):format(n) or default
  end
  local dark = vim.o.background ~= "light"
  local bg = hex(get("Normal").bg, dark and "#1e1e1e" or "#fafafa")
  local fg = hex(get("Normal").fg, dark and "#dddddd" or "#222222")
  local function fgof(name, default)
    return hex(get(name).fg, default)
  end
  local b16 = {
    base00 = bg,
    base05 = fg,
    base08 = fgof("DiagnosticError", "#e06c75"),
    base09 = fgof("Number", "#d19a66"),
    base0A = fgof("DiagnosticWarn", "#e5c07b"),
    base0B = fgof("String", "#98c379"),
    base0C = fgof("Special", "#56b6c2"),
    base0D = fgof("Function", "#61afef"),
    base0E = fgof("Keyword", "#c678dd"),
  }
  return M.from(b16, {})
end

--- Tokens of the active theme
---@return FlatTokens
function M.current()
  local ok, tokens = pcall(function()
    local base46 = require "base46"
    return M.from(base46.get_theme_tb "base_16", base46.get_theme_tb "base_30")
  end)
  return ok and tokens or M.from_highlights()
end

--- The editor surface tinted `amount` (0..1) toward `toward`: the veil behind added lines, selections, matches.
--- The editor is painted `deep` (like the demo's), so veils start from it.
---@param t FlatTokens
---@param toward string
---@param amount number
---@return string
function M.veil(t, toward, amount)
  return color.blend(t.deep, toward, amount)
end

return M
