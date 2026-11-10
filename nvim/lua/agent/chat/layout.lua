-- ── Chat geometry (pure) ────────────────────────────────────────────────────
-- Where the transcript/input blocks go for the active view. Takes the numbers
-- in (columns, rows, config) and returns them: no editor calls, so every
-- screen size and view is testable.
--
-- mini (the default) is a partition: half the screen, flush to the right edge
-- and the full usable height, separated from the editor by an edge (a real
-- split when settings.agent.chat.dock, the old float otherwise); transcript and
-- input are stacked with no editor row between them.
-- full is borderless and edge to edge; collapsed is the right-edge rail.
local M = {}

M.MIN_WIDTH = 28
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
  local want = math.floor(cols * (cfg.width or 0.5))
  -- leave the editor usable; a huge terminal still gives a true half partition
  local editor_min = cols >= 60 and math.floor(cols * 0.25) or 0
  want = math.min(want, cols - editor_min - 1)
  return math.max(M.MIN_WIDTH, want)
end

--- Geometry of the blocks.
--- mini: right-anchored blocks flush to the edge (one half-cell edge to the left).
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
  local usable = math.max(6, rows - 1) -- one row for the command line / statusline
  local top = 0
  if collapsed then
    return w, math.max(0, cols - w), top, usable, 0, false
  end

  local max_input = math.min(cfg.input_height or 5, math.max(3, usable - 6))
  local input_h = math.min(max_input, input_lines)
  local gap = cfg.gap or 1
  local transcript_h = math.max(M.MIN_TRANSCRIPT, usable - input_h - gap)
  -- with the flat partition border (one half-cell column at the left) the
  -- content starts at cols - w, so the block ends exactly on the last column
  local col = math.max(0, cols - w)
  return w, col, top, transcript_h, input_h, false
end

return M
