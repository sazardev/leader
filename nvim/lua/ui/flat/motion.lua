-- ── Flat design: motion ──────────────────────────────────────────────────────
-- The landing page's demo animates every overlay: which-key slides up from the statusline and fades in, menus and
-- modals fade in (0.15-0.2s, ease-out). `enter` does the same to floats: 'winblend' from 100 to 0 in a few frames and,
-- with `rise`, the window starting `rise` rows lower.
-- Rules that keep it from ever getting stuck:
--   · every frame flushes its own redraw: menus like which-key wait for a key in a loop that does not redraw;
--   · an animation stops (window settled where it is, fully opaque) as soon as someone else moves the window
--     (which-key resizing for a submenu, a picker relayout) or the window closes;
--   · animating a window again cancels the animation it had.
-- Off with `settings.ui.motion = false` (the demo honors reduced motion the same way) and without a UI.
local M = {}

local FRAMES, FRAME_MS = 5, 22 -- ~110ms: quick enough to never be in the way of the next key

---@type table<integer, uv.uv_timer_t>
local running = {}

---@return boolean
function M.enabled()
  return require("core.settings").ui.motion ~= false and #vim.api.nvim_list_uis() > 0
end

--- Ease-out (fast start, soft landing): the demo's cubic-bezier(.2,.7,.1,1), close enough
---@param x number 0..1
---@return number
function M.ease(x)
  return 1 - (1 - x) ^ 3
end

--- Rows a window is lifted by at frame `frame` of `frames`: whole rows only, never below 0
---@param rise integer
---@param frame integer
---@param frames integer
---@return integer
function M.offset(rise, frame, frames)
  return math.max(0, math.floor(rise * (1 - M.ease(frame / frames)) + 0.5))
end

---@param timer uv.uv_timer_t
local function stop(timer)
  if not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

---@param win integer
---@return integer
local function row_of(win)
  local row = vim.api.nvim_win_get_config(win).row
  return math.floor((type(row) == "table" and row[false] or row) + 0.5)
end

---@param win integer
---@param row integer
local function place(win, row)
  local c = vim.api.nvim_win_get_config(win)
  pcall(vim.api.nvim_win_set_config, win, { relative = c.relative, win = c.win, row = row, col = c.col })
end

local function flush()
  pcall(vim.api.nvim__redraw, { flush = true })
end

--- Fades the float `win` in and, with `rise`, slides it up `rise` rows into place
---@param win integer
---@param rise? integer
local function animate(win, rise)
  if running[win] then
    stop(running[win])
    running[win] = nil
  end
  local home = rise and row_of(win)
  local last = home
  vim.wo[win].winblend = 100
  if rise then
    last = home + rise
    place(win, last)
  end
  flush()
  local frame = 0
  local timer = assert(vim.uv.new_timer())
  running[win] = timer
  local function settle()
    stop(timer)
    if running[win] == timer then
      running[win] = nil
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].winblend = 0
    end
  end
  timer:start(
    FRAME_MS,
    FRAME_MS,
    vim.schedule_wrap(function()
      if timer:is_closing() then
        return
      end
      if not vim.api.nvim_win_is_valid(win) then
        return settle()
      end
      -- someone else moved it (a submenu, a relayout): it is theirs now
      if rise and row_of(win) ~= last then
        settle()
        return flush()
      end
      frame = frame + 1
      vim.wo[win].winblend = math.floor(100 * (1 - M.ease(frame / FRAMES)) + 0.5)
      if rise then
        last = home + M.offset(rise, frame, FRAMES)
        place(win, last)
      end
      if frame >= FRAMES then
        settle()
      end
      flush()
    end)
  )
end

--- Fades the floats `wins` in and, with `rise`, slides them up `rise` rows into place
---@param wins (integer|nil)[]
---@param rise? integer
function M.enter(wins, rise)
  if not M.enabled() then
    return
  end
  for _, win in pairs(wins) do
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= "" then
      animate(win, rise)
    end
  end
end

return M
