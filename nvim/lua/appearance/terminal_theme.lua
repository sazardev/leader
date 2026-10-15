-- ── base46 theme derived from the terminal palette ───────────────────────────
-- Converts the 16 ANSI colors + background/foreground into the `base_16` and
-- `base_30` tables NvChad expects. Rules:
--   · Neovim's background IS the terminal's background (zero seams);
--   · intermediate greys are interpolated between background and foreground, so
--     they work the same on dark and light themes;
--   · accents are pushed toward the foreground until they reach a minimum
--     contrast (some palettes ship unreadable blues/reds on their background).
local color = require "appearance.color"

local M = {}

local DARK_LUMINANCE = 0.179 -- point where white and black contrast equally

---@param palette table output of appearance.alacritty (background, foreground, ansi[1..16])
---@param min_contrast number
---@return table theme { base_16, base_30, type }
function M.build(palette, min_contrast)
  local bg, fg = palette.background, palette.foreground
  local dark = color.luminance(bg) < DARK_LUMINANCE
  local blend, ensure = color.blend, color.ensure_contrast

  --- ANSI color n (0-15)
  local function ansi(n)
    return palette.ansi[n + 1]
  end
  --- Point between background (0) and foreground (1)
  local function tint(t)
    return blend(bg, fg, t)
  end
  local function accent(hex)
    return ensure(hex, bg, fg, min_contrast)
  end

  -- Foreground extreme: lighter on dark themes, darker on light ones
  local extreme = dark and ansi(15) or ansi(0)
  local selection = palette.selection
  if not selection or color.contrast(selection, bg) < 1.15 then
    selection = tint(0.12)
  end

  local red, green, yellow = accent(ansi(1)), accent(ansi(2)), accent(ansi(3))
  local blue, magenta, cyan = accent(ansi(4)), accent(ansi(5)), accent(ansi(6))
  local orange = blend(red, yellow, 0.5)

  local base_16 = {
    base00 = bg,
    base01 = tint(0.06),
    base02 = selection,
    base03 = ensure(ansi(8), bg, fg, 2.2), -- comments
    base04 = tint(0.62),
    base05 = fg,
    base06 = blend(fg, extreme, 0.5),
    base07 = extreme,
    base08 = red,
    base09 = orange,
    base0A = yellow,
    base0B = green,
    base0C = cyan,
    base0D = blue,
    base0E = magenta,
    base0F = blend(orange, bg, 0.3),
  }

  local purple = blend(magenta, fg, 0.4)

  local base_30 = {
    white = base_16.base06,
    darker_black = blend(bg, "#000000", dark and 0.25 or 0.05),
    black = bg, -- nvim background
    black2 = tint(0.04),
    one_bg = tint(0.08),
    one_bg2 = tint(0.13),
    one_bg3 = tint(0.17),
    grey = tint(0.22),
    grey_fg = base_16.base03, -- base46 paints comments with it: the terminal's own bright black, like base03

    grey_fg2 = tint(0.26),
    light_grey = tint(0.38),
    red = red,
    baby_pink = blend(red, bg, 0.25),
    pink = blend(red, magenta, 0.5),
    line = tint(0.09), -- separators
    green = green,
    vibrant_green = accent(ansi(10)),
    nord_blue = blue,
    -- the terminal's exact accents, never dimmed toward the background (fidelity over base46's softer variants)
    blue = blue,
    yellow = yellow,
    sun = yellow,
    purple = purple,
    lavender = purple,
    dark_purple = magenta,
    teal = cyan,
    orange = orange,
    cyan = cyan,
    statusline_bg = tint(0.05),
    lightbg = tint(0.11),
    pmenu_bg = blue,
    folder_bg = blend(blue, cyan, 0.5),
  }

  return { base_16 = base_16, base_30 = base_30, type = dark and "dark" or "light" }
end

return M
