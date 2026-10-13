-- ── Color math (hex "#rrggbb") ───────────────────────────────────────────────
-- Pure functions, with no dependency on Neovim or base46.
local M = {}

---@param hex string "#rrggbb"
---@return number r, number g, number b  (0-255)
function M.to_rgb(hex)
  return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

---@param r number
---@param g number
---@param b number
---@return string
function M.to_hex(r, g, b)
  local function channel(v)
    return math.max(0, math.min(255, math.floor(v + 0.5)))
  end
  return ("#%02x%02x%02x"):format(channel(r), channel(g), channel(b))
end

--- Linear blend: t = 0 → a, t = 1 → b
---@param a string
---@param b string
---@param t number 0..1
---@return string
function M.blend(a, b, t)
  local ar, ag, ab = M.to_rgb(a)
  local br, bg, bb = M.to_rgb(b)
  return M.to_hex(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
end

--- Relative luminance (WCAG)
---@param hex string
---@return number 0..1
function M.luminance(hex)
  local function linear(c)
    c = c / 255
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  local r, g, b = M.to_rgb(hex)
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
end

--- Contrast ratio (WCAG), 1..21
---@param a string
---@param b string
---@return number
function M.contrast(a, b)
  local la, lb = M.luminance(a), M.luminance(b)
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

--- Moves `color` toward `toward` in 8% steps until it reaches `min` contrast
--- against `against`. If it already meets it, returns it untouched.
---@param color string
---@param against string background it is measured against
---@param toward string where to move toward (normally the foreground)
---@param min number minimum contrast
---@return string
function M.ensure_contrast(color, against, toward, min)
  local result = color
  for step = 1, 12 do
    if M.contrast(result, against) >= min then
      return result
    end
    result = M.blend(color, toward, step * 0.08)
  end
  return result
end

return M
