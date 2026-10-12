-- ── Acciones de Dart / Flutter ───────────────────────────────────────────────
local actions = require "utils.actions"
local log = require "utils.log"
local project = require "utils.project"
local terminal = require "utils.terminal"

local ex = actions.ex

--- Corre `flutter <flutter_sub>` en proyectos Flutter o `dart <dart_sub>` en Dart puro
local function tool(flutter_sub, dart_sub)
  return function()
    local root = vim.fs.root(0, { "pubspec.yaml" })
    if not root then
      return log.warn "No pubspec.yaml found"
    end
    local pubspec = project.read(root .. "/pubspec.yaml") or ""
    local is_flutter = pubspec:find "\n%s*flutter:" ~= nil
    terminal.run(is_flutter and ("flutter " .. flutter_sub) or ("dart " .. dart_sub), root)
  end
end

return {
  { "r", "run", ex "FlutterRun" },
  { "d", "debug", ex "FlutterDebug" },
  { "h", "hot reload", ex "FlutterReload" },
  { "R", "hot restart", ex "FlutterRestart" },
  { "q", "quit app", ex "FlutterQuit" },
  { "D", "devices", ex "FlutterDevices" },
  { "e", "emulators", ex "FlutterEmulators" },
  { "o", "widget outline", ex "FlutterOutlineToggle" },
  { "l", "log toggle", ex "FlutterLogToggle" },
  { "t", "devtools", ex "FlutterDevTools" },
  { "p", "pub get", ex "FlutterPubGet" },
  { "m", "test (flutter or dart, auto-detected)", tool("test", "test") },
  { "v", "analyze", tool("analyze", "analyze") },
  { "x", "dart fix --apply", tool("pub get && dart fix --apply", "fix --apply") },
  { "f", "format", actions.format },
}
