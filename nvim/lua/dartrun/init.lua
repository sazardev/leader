-- ── Run a Flutter app: which entry point ─────────────────────────────────────
-- `<leader>dr` / `<leader>dd` run (or debug) through flutter-tools. A package with several entry points
-- (`lib/main.dart`, `lib/main_dev.dart`, `lib/main_plank.dart`…) gets a picker with the last one used first, remembered
-- per project (stdpath("state")/dartrun.json); with one entry point it just runs. Project configurations you declared
-- yourself (`require("flutter-tools").setup_project`, flavors, dart-define) win: then flutter-tools asks as usual.
local log = require "utils.log"

local M = {}

local function store_path()
  return vim.fn.stdpath "state" .. "/dartrun.json"
end

---@return table<string, string> package root → last target
local function read_store()
  local f = io.open(store_path(), "r")
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  return ok and type(data) == "table" and data or {}
end

---@param root string
---@param target string
local function remember(root, target)
  local data = read_store()
  data[root] = target
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

--- Runs the app (`debug` = under the debugger, stopping at breakpoints from the start)
---@param debug boolean?
function M.run(debug)
  local ok, commands = pcall(require, "flutter-tools.commands")
  if not ok then
    return log.warn "Run: flutter-tools is not loaded (open a .dart file)"
  end
  if commands.is_running() then
    return log.info "Run: the app is already running (<leader>dh hot reload, <leader>dR restart, <leader>dq quit)"
  end
  local opts = debug and { force_debug = true } or {}
  -- configurations the user declared win: flutter-tools asks among them
  local declared = require("flutter-tools.config").project
  if type(declared) == "table" and #declared > 0 then
    return commands.run(opts)
  end
  local root = vim.fs.root(0, "pubspec.yaml")
  if not root then
    return log.warn "Run: no pubspec.yaml above this file"
  end
  local entries = M.entries(lib_files(root), read_store()[root])
  local function launch(entry)
    if entry then
      remember(root, entry.target)
    end
    commands.run(opts, { cwd = root, target = entry and entry.target or nil })
  end
  if #entries <= 1 then
    return launch(entries[1])
  end
  require("agent.ui.select").pick(entries, { title = "Run which entry point" }, launch)
end

--- Statusline: "▶ Pixel 7" while the app runs (the device flutter-tools runs on); "" otherwise
---@return string
function M.statusline()
  local commands = package.loaded["flutter-tools.commands"]
  if not (commands and commands.is_running()) then
    return ""
  end
  local device = (vim.g.flutter_tools_decorations or {}).device
  local name = type(device) == "table" and (device.name or device.id) or nil
  return "▶ " .. (name or "running")
end

return M
