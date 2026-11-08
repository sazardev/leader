-- ── Chat geometry (pure) ────────────────────────────────────────────────────
-- Where the transcript/input blocks go for the active view. Takes the numbers
-- in (columns, rows, config) and returns them: no editor calls, so every
-- screen size and view is testable.
local M = {}

M.MIN_WIDTH = 28
M.MAX_WIDTH = 72
M.MIN_TRANSCRIPT = 4

--- Width of the panel.
---@param cfg table settings.agent.chat
---@param cols integer
---@param collapsed boolean
---@param view "mini"|"full"
---@return integer
function M.width(cfg, cols, collapsed, view)
  if collapsed then
    return math.min(cfg.rail_width or 9, math.max(6, cols - 4))
  end
  if view == "full" then
    return math.max(1, cols)
  end
  local want = math.floor(cols * (cfg.width or 0.38))
  want = math.max(40, math.min(M.MAX_WIDTH, want))
  local editor_min = cols >= 60 and 20 or 0
  want = math.min(want, math.max(M.MIN_WIDTH, cols - 4 - editor_min))
  return math.max(M.MIN_WIDTH, want)
end

--- Geometry of the blocks.
--- mini: right-anchored floats (like commit/panel.lua).
--- full: two borderless floats edge to edge, the last row left for the statusline.
---@param cfg table
---@param cols integer
---@param rows integer
---@param collapsed boolean
---@param view "mini"|"full"
---@param input_lines integer? desired input height
---@return integer w, integer col, integer top, integer transcript_h, integer input_h, boolean full
function M.geometry(cfg, cols, rows, collapsed, view, input_lines)
  input_lines = math.max(1, input_lines or 1)
  if view == "full" and not collapsed then
    local max_h = math.min(cfg.input_height or 5, math.max(3, rows - 12))
    local input_h = math.min(max_h, input_lines)
    local usable = math.max(6, rows - 1) -- last row: the single statusline
    return cols, 0, 0, math.max(M.MIN_TRANSCRIPT, usable - input_h), input_h, true
  end

  local w = M.width(cfg, cols, collapsed, view)
  local right = cfg.right_margin or 2
  local top = cfg.top_margin or 2
  if rows < 24 then
    top = 1
  end
  local input_h = cfg.input_height or 5
  if rows < 30 then
    input_h = math.min(input_h, 3)
  end
  input_h = math.min(input_h, input_lines)
  if collapsed then
    return w, cols - (w + 2) - math.max(1, right - 1), top, math.max(6, rows - top - 4), 0, false
  end
  local transcript_h = math.max(6, rows - top - input_h - 6)
  local col = cols - (w + 2) - math.max(1, right - 1)
  return w, math.max(0, col), top, transcript_h, input_h, false
end

return M
