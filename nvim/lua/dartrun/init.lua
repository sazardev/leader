-- ── Run a Flutter app: device, entry point, mode ─────────────────────────────
-- `<leader>dr` runs, `<leader>dd` runs with the debug panel open, `<leader>ds` runs in profile mode and `<leader>dD`
-- asks everything (device, entry point, mode). The device, the entry point (`lib/main.dart`, `lib/main_dev.dart`…) and
-- the last choice are remembered per project (stdpath("state")/dartrun.json): `r`/`d`/`s` start at once on them and ask
-- only what is missing. The launch configuration is ours (device and mode go in `toolArgs`, where flutter's debug adapter
-- reads them: `--profile` anywhere else leaves the adapter believing it is debugging). Project configurations you
-- declared yourself (`require("flutter-tools").setup_project`, flavors, dart-define) win for `r`/`d`.
-- `state.lua` is the statusline chip, `panels.lua` hides what a run puts on the screen, `devices.lua` lists devices.
local devices = require "dartrun.devices"
local log = require "utils.log"
local state = require "dartrun.state"

local M = {}

local function store_path()
  return vim.fn.stdpath "state" .. "/dartrun.json"
end

---@return table<string, string|table> package root → what was chosen last (the first format was the entry point alone)
local function read_store()
  local f = io.open(store_path(), "r")
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  return ok and type(data) == "table" and data or {}
end

--- What was chosen last in this package
---@param root string
---@return { target: string?, device: string?, device_name: string? }
local function recall(root)
  local value = read_store()[root]
  if type(value) == "string" then -- the first format: the entry point alone
    return { target = value }
  end
  return type(value) == "table" and value or {}
end

---@param root string
---@param patch table
local function remember(root, patch)
  local data = read_store()
  data[root] = vim.tbl_extend("force", recall(root), patch)
  local f = io.open(store_path(), "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

--- Entry points of a package: `lib/main.dart` and `lib/main_*.dart`, labelled by what follows `main_`
---@param names string[] file names inside lib/
---@param last string? the target used last (`lib/main_plank.dart`)
---@return { label: string, target: string, current: boolean }[]
function M.entries(names, last)
  local out = {}
  for _, name in ipairs(names) do
    local suffix = name:match "^main_?(.-)%.dart$"
    if suffix then
      local target = "lib/" .. name
      out[#out + 1] = { label = suffix ~= "" and suffix or "main", target = target, current = target == last }
    end
  end
  table.sort(out, function(a, b)
    if a.current ~= b.current then
      return a.current
    end
    if (a.label == "main") ~= (b.label == "main") then
      return a.label == "main"
    end
    return a.label < b.label
  end)
  for _, e in ipairs(out) do
    e.label = ("%s  %s"):format(e.label, e.target)
  end
  return out
end

---@param root string
---@return string[]
local function lib_files(root)
  local names = {}
  for name, kind in vim.fs.dir(root .. "/lib") do
    if kind == "file" then
      names[#names + 1] = name
    end
  end
  return names
end

--- The launch configuration for flutter's debug adapter. `-d` and the mode are tool arguments (`toolArgs`): that is where
--- the adapter looks for `--profile`/`--release` (with them in `args` it would start the app paused, as if debugging)
---@param spec { paths: { dart_sdk: string?, flutter_sdk: string? }, root: string, target: string?, device: string?, mode: string? }
---@return table
function M.launch_config(spec)
  local mode = spec.mode or "debug"
  local tool = {}
  if spec.device then
    vim.list_extend(tool, { "-d", spec.device })
  end
  if mode ~= "debug" then
    tool[#tool + 1] = "--" .. mode
  end
  return {
    type = "dart",
    request = "launch",
    name = "Launch flutter (" .. mode .. ")",
    dartSdkPath = spec.paths.dart_sdk,
    flutterSdkPath = spec.paths.flutter_sdk,
    program = spec.target or "lib/main.dart",
    cwd = spec.root,
    toolArgs = tool,
  }
end

M.MODES = {
  { label = "debug  hot reload, breakpoints", mode = "debug" },
  { label = "profile  performance (DevTools), no debugger", mode = "profile" },
  { label = "release  as it ships", mode = "release" },
}

--- Stops the running app and calls `cb` once the debug session is gone (a new one started before would be tracked wrong)
---@param commands table flutter-tools.commands
---@param cb fun()
local function stop_then(commands, cb)
  commands.quit()
  local tries = 0
  local function wait()
    local dap = package.loaded["dap"]
    tries = tries + 1
    if not (dap and dap.session()) or tries > 50 then
      return cb()
    end
    vim.defer_fn(wait, 100)
  end
  wait()
end

local function pick(items, title, on_choice)
  require("agent.ui.select").pick(items, { title = title }, on_choice)
end

--- The device: the remembered one when it is connected, the only one there is, otherwise a picker
---@param root string
---@param opts dartrun.Opts
---@param done fun(device: dartrun.Device)
local function choose_device(root, opts, done)
  local last = recall(root).device
  devices.list(function(list, err)
    if not list then
      return log.warn("Run: " .. err)
    end
    local usable = devices.usable(list, function(folder)
      return vim.uv.fs_stat(root .. "/" .. folder) ~= nil
    end)
    if #usable == 0 then
      return log.warn "Run: no device connected (<leader>de starts an emulator)"
    end
    if not opts.ask then
      for _, d in ipairs(usable) do
        if d.id == last then
          return done(d)
        end
      end
    end
    if #usable == 1 then
      return done(usable[1])
    end
    pick(devices.entries(usable, last, opts.mode), "Run on which device", function(entry)
      done(entry.device)
    end)
  end)
end

--- The entry point: the last one used, the only one there is, otherwise a picker (nil: the package has none → main.dart)
---@param root string
---@param opts dartrun.Opts
---@param done fun(entry: { label: string, target: string }?)
local function choose_entry(root, opts, done)
  local entries = M.entries(lib_files(root), recall(root).target)
  if #entries == 0 then
    return done(nil)
  end
  if #entries == 1 or (entries[1].current and not opts.ask) then
    return done(entries[1])
  end
  pick(entries, "Run which entry point", done)
end

---@class dartrun.Opts
---@field debug boolean? open the debug panel with the session
---@field mode string? "debug" (default) | "profile" | "release"
---@field ask boolean? ask for the device, the entry point and the mode even when they are remembered

--- Runs the app. A running one is stopped first only when the choice is made here (`ask` or a mode): `r` and `d` never
--- interrupt it.
---@param opts dartrun.Opts?
function M.start(opts)
  opts = opts or {}
  local ok, commands = pcall(require, "flutter-tools.commands")
  if not ok then
    return log.warn "Run: flutter-tools is not loaded (open a .dart file)"
  end
  local restarts = opts.ask or opts.mode ~= nil
  if commands.is_running() and not restarts then
    return log.info "Run: the app is already running (<leader>dh hot reload, <leader>dR restart, <leader>dq quit)"
  end
  local root = vim.fs.root(0, "pubspec.yaml")
  if not root then
    return log.warn "Run: no pubspec.yaml above this file"
  end
  -- a plain Dart package has no devices or modes: flutter-tools runs it as it always did
  if not require("flutter-tools.utils.config_utils").has_flutter_dependency_in_pubspec(root) then
    return commands.run(opts.debug and { force_debug = true } or {})
  end
  -- configurations the user declared win: flutter-tools asks among them
  local declared = require("flutter-tools.config").project
  if type(declared) == "table" and #declared > 0 and not restarts then
    return commands.run(opts.debug and { force_debug = true } or {})
  end

  local function launch(device, entry, mode)
    remember(root, { target = entry and entry.target or nil, device = device.id, device_name = device.name })
    require("flutter-tools.executable").get(function(paths)
      local config = M.launch_config {
        paths = paths,
        root = root,
        target = entry and entry.target or nil,
        device = device.id,
        mode = mode,
      }
      local function go()
        pcall(require, "dap") -- loads it (lazy): the listeners below need it
        state.panel = opts.debug == true
        state.begin { device = device.name, mode = mode, started = false }
        state.watch()
        commands.run(
          { force_debug = true, device = { id = device.id, name = device.name } },
          { cwd = root, target = config.program },
          config
        )
      end
      if commands.is_running() then
        stop_then(commands, go)
      else
        go()
      end
    end)
  end

  choose_device(root, opts, function(device)
    choose_entry(root, opts, function(entry)
      if opts.ask and not opts.mode then
        return pick(M.MODES, "Run in which mode", function(item)
          launch(device, entry, item.mode)
        end)
      end
      launch(device, entry, opts.mode or "debug")
    end)
  end)
end

--- `<leader>dr` / `<leader>dd`: on the remembered device and entry point (`debug` = with the debug panel)
---@param debug boolean?
function M.run(debug)
  M.start { debug = debug }
end

--- `<leader>ds`: profile mode, one key, on the remembered device and entry point
function M.profile()
  M.start { mode = "profile" }
end

--- `<leader>dD`: asks the device, the entry point and the mode
function M.ask()
  M.start { ask = true }
end

--- Statusline: "▶ Pixel 7" while the app runs ("◌" building, "▶ Pixel 7 · profile", "⏸" at a breakpoint); "" otherwise
---@return string
function M.statusline()
  return state.text(state.current())
end

--- Highlight group of the chip (profile and release are painted apart: they are not the build you debug)
---@return string
function M.statusline_group()
  return state.group(state.current())
end

--- Once, when flutter-tools loads
function M.setup()
  state.setup()
end

--- Whether the debug panel opens with a Dart session: `<leader>dd` asks for it; a plain run opens it only when stopped
---@return boolean
function M.wants_panel()
  return state.panel
end

return M
