-- ── Live tracking of the terminal config ─────────────────────────────────────
-- Polls (stat) the Alacritty config files every `watch_ms`. Polling is used
-- instead of inotify because in WSL the config lives on Windows (/mnt/c) and those
-- changes generate no events. It only runs while the active theme is the terminal one.
local alacritty = require "appearance.alacritty"
local settings = require "core.settings"

local M = {}

---@type uv.uv_timer_t?
local timer

---@return boolean
function M.active()
  return timer ~= nil
end

function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

--- Starts the polling; `on_change` is called (on the main thread) when changes are detected
---@param on_change fun()
function M.start(on_change)
  local interval = settings.theme.terminal.watch_ms
  if timer or not interval or interval <= 0 then
    return
  end
  timer = vim.uv.new_timer()
  timer:start(
    interval,
    interval,
    vim.schedule_wrap(function()
      if alacritty.is_stale() then
        on_change()
      end
    end)
  )
end

return M
