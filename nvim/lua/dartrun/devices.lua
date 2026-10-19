-- ── Devices to run a Flutter app on ──────────────────────────────────────────
-- `flutter devices --machine` (JSON, ~0.5 s) → the list the run picker shows. `parse`/`usable`/`order`/`entries` are
-- pure (scripts/test-flutter.sh); `list` is the only function that starts a process.
local M = {}

-- prefix of `targetPlatform` → the folder the project needs for that platform, and the kind of device
local PLATFORMS = {
  { prefix = "android", folder = "android", kind = "mobile" },
  { prefix = "ios", folder = "ios", kind = "mobile" },
  { prefix = "darwin", folder = "macos", kind = "desktop" },
  { prefix = "linux", folder = "linux", kind = "desktop" },
  { prefix = "windows", folder = "windows", kind = "desktop" },
  { prefix = "web", folder = "web", kind = "web" },
}

---@param platform string?
local function platform_info(platform)
  for _, info in ipairs(PLATFORMS) do
    if platform and vim.startswith(platform, info.prefix) then
      return info
    end
  end
end

---@class dartrun.Device
---@field id string
---@field name string
---@field platform string `android-arm64`, `linux-x64`, `web-javascript`…
---@field emulator boolean
---@field supported boolean
---@field kind "mobile"|"desktop"|"web"|"other"
---@field folder string? the folder of the project this platform needs (`android`, `web`…)

--- The devices in `flutter devices --machine` output (notices such as the startup lock message may come before the JSON)
---@param lines string[]
---@return dartrun.Device[]
function M.parse(lines)
  local first
  for i, line in ipairs(lines) do
    if vim.startswith(line, "[") then
      first = i
      break
    end
  end
  if not first then
    return {}
  end
  local ok, decoded = pcall(vim.json.decode, table.concat(vim.list_slice(lines, first), "\n"))
  if not ok or type(decoded) ~= "table" then
    return {}
  end
  local out = {}
  for _, d in ipairs(decoded) do
    if type(d) == "table" and type(d.id) == "string" then
      local info = platform_info(d.targetPlatform)
      out[#out + 1] = {
        id = d.id,
        name = d.name or d.id,
        platform = d.targetPlatform or "",
        emulator = d.emulator == true,
        supported = d.isSupported ~= false,
        kind = info and info.kind or "other",
        folder = info and info.folder or nil,
      }
    end
  end
  return out
end

--- Drops the devices flutter cannot run this project on (unsupported, or the project has no folder for its platform)
---@param devices dartrun.Device[]
---@param has_folder fun(folder: string): boolean
---@return dartrun.Device[]
function M.usable(devices, has_folder)
  return vim.tbl_filter(function(d)
    return d.supported and (not d.folder or has_folder(d.folder))
  end, devices)
end

local function rank(d)
  if d.kind == "mobile" then
    return d.emulator and 2 or 1 -- a phone on the desk before an emulator
  end
  return d.kind == "desktop" and 3 or 4
end

--- The last one used first, then phones, emulators, desktop, web
---@param devices dartrun.Device[]
---@param last string? id of the device used last
---@return dartrun.Device[]
function M.order(devices, last)
  local out = vim.list_slice(devices, 1, #devices)
  table.sort(out, function(a, b)
    if (a.id == last) ~= (b.id == last) then
      return a.id == last
    end
    if rank(a) ~= rank(b) then
      return rank(a) < rank(b)
    end
    return a.name < b.name
  end)
  return out
end

--- Picker rows (`agent.ui.select` items). The iOS simulator only runs debug (flutter's own `supportsRuntimeMode`;
--- Android emulators do run profile and release): its row says so.
---@param devices dartrun.Device[]
---@param last string?
---@param mode string? "debug" | "profile" | "release"
---@return { label: string, device: dartrun.Device, current: boolean }[]
function M.entries(devices, last, mode)
  local out = {}
  for _, d in ipairs(M.order(devices, last)) do
    local tags = {}
    if d.emulator then
      tags[#tags + 1] = "emulator"
      if d.folder == "ios" and mode and mode ~= "debug" then
        tags[#tags + 1] = "no " .. mode
      end
    end
    out[#out + 1] = {
      label = ("%s  %s%s"):format(d.name, d.platform, #tags > 0 and ("  · " .. table.concat(tags, ", ")) or ""),
      device = d,
      current = d.id == last,
    }
  end
  return out
end

--- Asks flutter (the one flutter-tools resolved: PATH, FVM…) which devices are connected
---@param callback fun(devices: dartrun.Device[]?, err: string?)
function M.list(callback)
  local ok, executable = pcall(require, "flutter-tools.executable")
  if not ok then
    return callback(nil, "flutter-tools is not loaded")
  end
  executable.flutter(function(flutter)
    if not flutter or flutter == "" then
      return callback(nil, "flutter is not in PATH")
    end
    local started = pcall(vim.system, { flutter, "devices", "--machine" }, { text = true, timeout = 30000 }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          local why = vim.trim((res.stderr or "") ~= "" and res.stderr or (res.stdout or ""))
          return callback(nil, why ~= "" and why or "flutter devices failed")
        end
        callback(M.parse(vim.split(res.stdout or "", "\n")))
      end)
    end)
    if not started then
      callback(nil, "could not start flutter")
    end
  end)
end

return M
