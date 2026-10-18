-- ── Dart / Flutter actions ───────────────────────────────────────────────────
local actions = require "utils.actions"
local log = require "utils.log"
local project = require "utils.project"
local terminal = require "utils.terminal"

local ex = actions.ex

--- Runs `flutter <flutter_sub>` in Flutter projects or `dart <dart_sub>` in plain Dart
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
  -- run / debug: a picker of entry points when there are several (lua/dartrun)
  {
    "r",
    "run",
    function()
      require("dartrun").run()
    end,
  },
  {
    "d",
    "debug",
    function()
      require("dartrun").run(true)
    end,
  },
  { "h", "hot reload", ex "FlutterReload" },
  { "R", "hot restart", ex "FlutterRestart" },
  { "q", "quit app", ex "FlutterQuit" },
  { "D", "devices", ex "FlutterDevices" },
  { "e", "emulators", ex "FlutterEmulators" },
  { "o", "widget outline", ex "FlutterOutlineToggle" },
  { "l", "log toggle", ex "FlutterLogToggle" },
  { "t", "devtools", ex "FlutterDevTools" },
  { "p", "pub get", ex "FlutterPubGet" },
  -- dependencies (lua/dartpub): what is behind, written next to it in pubspec.yaml; pub add
  {
    "U",
    "pub outdated",
    function()
      require("dartpub").show_outdated()
    end,
  },
  {
    "P",
    "pub add",
    function()
      require("dartpub").add()
    end,
  },
  -- tests inside the editor (lua/darttest): marks on the test lines, failures as diagnostics, quickfix
  {
    "m",
    "test nearest",
    function()
      require("darttest").run "nearest"
    end,
  },
  {
    "M",
    "test file",
    function()
      require("darttest").run "file"
    end,
  },
  {
    "A",
    "test all",
    function()
      require("darttest").run "all"
    end,
  },
  {
    ".",
    "test again",
    function()
      require("darttest").run "again"
    end,
  },
  {
    "T",
    "test file toggle",
    function()
      require("darttest").toggle_file()
    end,
  },
  {
    "w",
    "test output",
    function()
      require("darttest").show_output()
    end,
  },
  { "v", "analyze", tool("analyze", "analyze") },
  { "x", "dart fix --apply", tool("pub get && dart fix --apply", "fix --apply") },
  { "f", "format", actions.format },
  -- code generation (build_runner: lua/dartgen)
  {
    "g",
    "codegen watch (toggle)",
    function()
      require("dartgen").toggle()
    end,
  },
  {
    "G",
    "codegen build once",
    function()
      require("dartgen").build()
    end,
  },
  {
    "L",
    "codegen output",
    function()
      require("dartgen").show_log()
    end,
  },
  -- debugging (nvim-dap; <leader>dd starts the app under the debugger)
  {
    "b",
    "breakpoint toggle",
    function()
      require("dap").toggle_breakpoint()
    end,
  },
  {
    "B",
    "breakpoint condition",
    function()
      require("dap").set_breakpoint(vim.fn.input "Condition: ")
    end,
  },
  {
    "c",
    "continue",
    function()
      require("dap").continue()
    end,
  },
  {
    "n",
    "step over",
    function()
      require("dap").step_over()
    end,
  },
  {
    "i",
    "step into",
    function()
      require("dap").step_into()
    end,
  },
  {
    "O",
    "step out",
    function()
      require("dap").step_out()
    end,
  },
  { "u", "debug panel", "<cmd>DapViewToggle<cr>" },
  -- code folds (<leader>dz…), mirroring the global <leader>z menu so they are reachable from <leader>d
  {
    "zf",
    "fold function here",
    function()
      require("utils.folds").here "function"
    end,
  },
  {
    "zt",
    "fold type here (struct, class, interface)",
    function()
      require("utils.folds").here "type"
    end,
  },
  {
    "zo",
    "fold object here (table, map, array)",
    function()
      require("utils.folds").here "object"
    end,
  },
  { "zb", "fold block here (again: the one around it)", function() require("utils.folds").block() end },
  { "zm", "fold methods of this type", function() require("utils.folds").methods() end },
  { "zF", "fold all functions", function() require("utils.folds").all "function" end },
  { "zT", "fold all types", function() require("utils.folds").all "type" end },
  { "zO", "fold all objects", function() require("utils.folds").all "object" end },
  { "za", "fold all (outline only)", function() require("utils.folds").close_all_folds() end },
  { "ze", "expand all", function() require("utils.folds").open_all_folds() end },
  { "zs", "fold all but this (focus)", function() require("utils.folds").focus() end },
  { "zu", "unfold here and inside", function() require("utils.folds").open_here() end },
  { "zz", "toggle fold here", function() require("utils.folds").toggle() end },
  { "z1", "fold level 1", function() require("utils.folds").level(1) end },
  { "z2", "fold level 2", function() require("utils.folds").level(2) end },
  { "z3", "fold level 3", function() require("utils.folds").level(3) end },
}
