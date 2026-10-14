-- ── "Just changed" flash ─────────────────────────────────────────────────────
-- What you yank, or what the agent / a formatter just wrote, glows yellow and fades out (like the demo's
-- accepted lines). A few precomputed frames (FlatFresh1…N, see groups.lua) swapped on a timer: no plugin, no
-- redraw loop, and it stops by itself. `settings.ui.fresh_ms = 0` turns it off.
local groups = require "ui.flat.groups"

local M = {}

local ns = vim.api.nvim_create_namespace "FlatFresh"

---@return integer
local function duration()
  local ui = require("core.settings").ui or {}
  return ui.fresh_ms or 0
end

--- Fades the range in `buf` (0-based, end exclusive)
---@param buf integer
---@param srow integer
---@param scol integer
---@param erow integer
---@param ecol integer
function M.range(buf, srow, scol, erow, ecol)
  local ms = duration()
  if ms <= 0 or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local opts = { end_row = erow, end_col = ecol, hl_group = "FlatFresh1", priority = 200, strict = false }
  local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, ns, srow, scol, opts)
  if not ok then
    return
  end
  local frame, timer = 1, vim.uv.new_timer()
  timer:start(
    math.floor(ms / groups.FRESH_STEPS),
    math.floor(ms / groups.FRESH_STEPS),
    vim.schedule_wrap(function()
      frame = frame + 1
      if frame > groups.FRESH_STEPS or not vim.api.nvim_buf_is_valid(buf) then
        timer:stop()
        timer:close()
        pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
        return
      end
      opts.id = id
      opts.hl_group = "FlatFresh" .. frame
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, srow, scol, opts)
    end)
  )
end

--- Fades whole lines (0-based `from`, `to` exclusive)
---@param buf integer
---@param from integer
---@param to integer
function M.lines(buf, from, to)
  M.range(buf, from, 0, to, 0)
end

--- Flash on yank: charwise and linewise
function M.on_yank()
  local ev = vim.v.event
  if ev.operator ~= "y" or ev.visual == nil and ev.regtype == "" then
    return
  end
  local s, e = vim.api.nvim_buf_get_mark(0, "["), vim.api.nvim_buf_get_mark(0, "]")
  if s[1] == 0 then
    return
  end
  if ev.regtype == "v" then
    M.range(0, s[1] - 1, s[2], e[1] - 1, e[2] + 1)
  else
    M.lines(0, s[1] - 1, e[1])
  end
end

return M
