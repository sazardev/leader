-- ── What is running: the statusline chip ─────────────────────────────────────
-- `info` is what dartrun launched (`device`, `mode`, `started`); whether the app is running at all is asked to
-- flutter-tools every time, so the chip can never outlive the session. An app started with :FlutterRun or `dap.continue`
-- has no `info`: it shows the device flutter-tools resolved. `text`/`group` are pure.
local M = {}

---@class dartrun.Info
---@field device string? name of the device
---@field mode string? "debug" | "profile" | "release"
---@field started boolean? the app is up (false while it builds)
---@field stopped boolean? stopped at a breakpoint

---@type dartrun.Info?
M.info = nil

--- Whether the next session wants the debug panel open at once (`<leader>dd`); a plain run opens it only when stopped
M.panel = false

--- "◌ Pixel 7" while it builds, "▶ Pixel 7" running, "▶ Pixel 7 · profile", "⏸ Pixel 7" at a breakpoint
---@param info dartrun.Info?
---@return string
function M.text(info)
  if not info then
    return ""
  end
  local mode = info.mode and info.mode ~= "debug" and (" · " .. info.mode) or ""
  local glyph = info.stopped and "⏸" or (info.started == false and "◌" or "▶")
  return ("%s %s%s"):format(glyph, info.device or "running", mode)
end

---@param info dartrun.Info?
---@return string highlight group (ui/flat/groups.lua)
function M.group(info)
  if info and (info.stopped or info.started == false) then
    return "FlutterStarting"
  end
  if info and info.mode and info.mode ~= "debug" then
    return "FlutterProfile"
  end
  return "FlutterRunning"
end

--- Redraws the statusline now (lualine only refreshes on its own events); `delay` for the end of a session, which
--- flutter-tools notices a moment after the event
---@param delay integer?
function M.refresh(delay)
  local function now()
    local lualine = package.loaded["lualine"]
    if lualine then
      pcall(lualine.refresh)
    end
    pcall(vim.cmd.redrawstatus)
  end
  if delay then
    vim.defer_fn(now, delay)
  else
    vim.schedule(now)
  end
end

---@return dartrun.Info? nil when nothing runs
function M.current()
  local commands = package.loaded["flutter-tools.commands"]
  if not (commands and commands.is_running()) then
    return nil
  end
  local info = vim.deepcopy(M.info) or { started = true }
  if not info.device then
    local device = (vim.g.flutter_tools_decorations or {}).device
    info.device = type(device) == "table" and (device.name or device.id) or (type(device) == "string" and device or nil)
  end
  local dap = package.loaded["dap"]
  local session = dap and dap.session()
  info.stopped = session ~= nil and session.stopped_thread_id ~= nil
  return info
end

---@param info dartrun.Info
function M.begin(info)
  M.info = info
  M.refresh()
end

local watching = false

--- The chip follows the app: the debugger's own events (stopped at a breakpoint, continued, the session's end)
local function watch_dap()
  local dap = package.loaded["dap"]
  if not dap then
    return
  end
  -- flutter's debug adapter (3.47) says `flutter.appStarted`; flutter-tools still waits for `app.started`, which no
  -- longer comes, so its own event cannot be the only one the chip trusts
  dap.listeners.after["event_flutter.appStarted"]["dartrun"] = function()
    if M.info then
      M.info.started = true
    end
    M.refresh()
  end
  for _, event in ipairs { "event_stopped", "event_continued" } do
    dap.listeners.after[event]["dartrun"] = function()
      M.refresh()
    end
  end
  for _, event in ipairs { "event_terminated", "event_exited" } do
    dap.listeners.after[event]["dartrun"] = function()
      M.info = nil
      M.refresh(300)
    end
  end
end

--- Once, when flutter-tools loads
function M.setup()
  if watching then
    return
  end
  watching = true
  local group = vim.api.nvim_create_augroup("DartRun", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "FlutterToolsAppStarted",
    callback = function()
      if M.info then
        M.info.started = true
      end
      watch_dap() -- an app started from outside dartrun (:FlutterRun) is followed too
      M.refresh()
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "FlutterToolsDeviceChanged",
    callback = function()
      M.refresh()
    end,
  })
end

--- Called by dartrun right before launching (dap is loaded by then)
function M.watch()
  watch_dap()
end

return M
