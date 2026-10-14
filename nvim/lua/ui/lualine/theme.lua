-- ── lualine theme derived from the flat tokens (or base46 without the flat design) ──
-- Changes with theme_toggle (gruvbox <-> gruvbox_light) and every theme switch.
local M = {}

---@param mode_color string
---@param p table already resolved palette
local function section(mode_color, p)
  return {
    a = { bg = mode_color, fg = p.mode_fg, gui = "bold" },
    b = { bg = p.b_bg, fg = p.b_fg },
    c = { bg = p.c_bg, fg = p.c_fg },
  }
end

--- The landing page's statusline: a soft bar, the mode chip (blue normal, green insert, yellow visual) with `on` text,
--- file and project chips one step lighter than the bar (`soft` 90% + `fg` 10%), the branch dim
---@return table
local function flat()
  local t = require("ui.flat.palette").current()
  local p = {
    mode_fg = t.on,
    c_bg = t.soft,
    c_fg = t.dim,
    b_bg = require("appearance.color").blend(t.soft, t.fg, 0.10),
    b_fg = t.fg,
  }
  return {
    normal = section(t.blue, p),
    insert = section(t.green, p),
    visual = section(t.yellow, p),
    replace = section(t.red, p),
    command = section(t.purple, p),
    terminal = section(t.orange, p),
    inactive = {
      a = { bg = p.b_bg, fg = p.c_fg, gui = "bold" },
      b = { bg = p.b_bg, fg = p.c_fg },
      c = { bg = p.c_bg, fg = p.c_fg },
    },
  }
end

---@return table theme for lualine
function M.build()
  if require("ui.flat").enabled() then
    return flat()
  end
  local ok, base46 = pcall(require, "base46")
  if not ok then
    return require "lualine.themes.gruvbox_dark"
  end

  local p30 = base46.get_theme_tb "base_30" or {}
  local p16 = base46.get_theme_tb "base_16" or {}
  local is_dark = base46.get_theme_tb "type" ~= "light"

  local p = {
    mode_fg = p16.base00 or "#282828",
    c_bg = is_dark and (p30.statusline_bg or "#2c2c2c") or (p16.base01 or "#3c3836"),
    c_fg = p16.base04 or "#bdae93",
    b_bg = p30.lightbg or p16.base01 or "#3d3d3d",
    b_fg = p30.white or p16.base06 or "#ebdbb2",
  }
  local inactive = is_dark and (p30.one_bg2 or "#3f3f3f") or (p16.base02 or "#423e3c")

  return {
    normal = section(p30.nord_blue or "#83a598", p),
    insert = section(p30.green or "#b8bb26", p),
    visual = section(p30.sun or "#fabd2f", p),
    replace = section(p30.red or "#fb4934", p),
    command = section(p30.dark_purple or "#d3869b", p),
    terminal = section(p30.orange or "#e78a4e", p),
    inactive = {
      a = { bg = inactive, fg = p.c_fg, gui = "bold" },
      b = { bg = inactive, fg = p.c_fg },
      c = { bg = p.c_bg, fg = p.c_fg },
    },
  }
end

return M
