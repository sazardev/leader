-- ── Diagnostic colors: a single source for the whole UI ──────────────────────
-- The statusline label (E2 / W1), the line number and the inline blocks
-- (utils/diagblocks.lua) come from here, so the error red is THE SAME in all three places.
-- The accent is the active theme's `DiagnosticX`; the text on top of it is the theme background (like
-- the text of lualine's mode section) and, if it lacks contrast, black or white.
local color = require "appearance.color"

local M = {}

local SEV = vim.diagnostic.severity

-- severity → short name and theme group the accent comes from
M.KINDS = {
  [SEV.ERROR] = { name = "Error", from = "DiagnosticError", fallback = "#e06c75" },
  [SEV.WARN] = { name = "Warn", from = "DiagnosticWarn", fallback = "#e5c07b" },
  [SEV.INFO] = { name = "Info", from = "DiagnosticInfo", fallback = "#61afef" },
  [SEV.HINT] = { name = "Hint", from = "DiagnosticHint", fallback = "#56b6c2" },
}

---@param name string
---@return integer?
local function fg_of(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false }).fg
end

---@param severity integer
---@return string hex accent color of that severity in the active theme
function M.accent(severity)
  local kind = M.KINDS[severity]
  local fg = fg_of(kind.from)
  return fg and ("#%06x"):format(fg) or kind.fallback
end

--- Readable text over an accent background (3.5: labels are bold, so the text is the
--- same on errors and warnings instead of jumping between background and black)
---@param accent string
---@return string
function M.on_accent(accent)
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  local base = bg and ("#%06x"):format(bg)
  if base and color.contrast(base, accent) >= 3.5 then
    return base
  end
  return color.contrast("#000000", accent) >= color.contrast("#ffffff", accent) and "#000000" or "#ffffff"
end

--- Solid severity label: background = accent, text = `on_accent`, bold
---@param severity integer
---@return { bg: string, fg: string, bold: boolean }
function M.pill(severity)
  local accent = M.accent(severity)
  return { bg = accent, fg = M.on_accent(accent), bold = true }
end

-- ── Theme sync ───────────────────────────────────────────────────────────────
-- Derived highlights (line number, blocks) are computed once; if the theme changes without
-- ColorScheme or NvThemeReload (base46 loads its cache silently at startup, the theme inherited from
-- the terminal is recompiled live), they would keep the old color while the statusline,
-- which is evaluated on every refresh, already uses the new one. `sync()` detects it by comparing signatures and
-- notifies whoever registered an `on_change`; it is called from every refresh of the bar and of the blocks.
local last ---@type string?
local listeners = {} ---@type fun()[]

---@return string
local function signature()
  local parts = { vim.o.background, tostring(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg) }
  for severity in pairs(M.KINDS) do
    parts[#parts + 1] = M.accent(severity)
  end
  return table.concat(parts, "|")
end

---@param fn fun() recomputes the derived highlights
function M.on_change(fn)
  listeners[#listeners + 1] = fn
end

--- If the theme changed since the last check, recomputes the derived stuff (on the next tick:
--- it can be called from the statusline evaluation)
function M.sync()
  local current = signature()
  if current == last then
    return
  end
  last = current
  vim.schedule(function()
    for _, fn in ipairs(listeners) do
      fn()
    end
  end)
end

return M
