-- Tests of the agent with Dart / Flutter: the analyzers' output as errors (`dart analyze` human and machine formats,
-- `flutter analyze`), the build check command after accepting (`dart analyze` on the saved file). Real output captured
-- from Dart 3.13 / Flutter 3.47. Hermetic: no SDK, LSP or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq = K.eq

local parse = require "agent.errors.parse"
local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/lib", "p")
vim.fn.writefile({ "x" }, dir .. "/lib/bad.dart")
local bad = dir .. "/lib/bad.dart"

local function short(errors)
  return vim.tbl_map(function(e)
    return { vim.fn.fnamemodify(e.file, ":t"), e.lnum, e.col, e.severity, e.tool }
  end, errors)
end

eq(
  "flutter analyze: errors and warnings with their place",
  short(parse.parse(
    table.concat({
      "Analyzing gen...",
      "",
      "warning • The value of the local variable 'unused' isn't used. Try removing the variable or using it • lib/bad.dart:2:9 • unused_local_variable",
      "  error • Undefined name 'b'. Try correcting the name to one that is defined, or defining the name • lib/bad.dart:3:14 • undefined_identifier",
      "   info • Prefer const constructors • lib/bad.dart:5:1 • prefer_const_constructors",
      "",
      "3 issues found. (ran in 0.1s)",
    }, "\n"),
    { root = dir }
  )),
  {
    { "bad.dart", 2, 9, "warn", "flutter" },
    { "bad.dart", 3, 14, "error", "flutter" },
    { "bad.dart", 5, 1, "warn", "flutter" },
  }
)

eq(
  "dart analyze: the human format from the project root",
  short(parse.parse(
    table.concat({
      "Analyzing gen...",
      "  error - lib/bad.dart:3:10 - A value of type 'double' can't be returned. - return_of_invalid_type",
      "warning - lib/bad.dart:2:9 - The value of the local variable 'unused' isn't used. - unused_local_variable",
      "   info - lib/bad.dart:4:3 - Unnecessary statement. - unnecessary_statements",
    }, "\n"),
    { root = dir }
  )),
  {
    { "bad.dart", 3, 10, "error", "dart" },
    { "bad.dart", 2, 9, "warn", "dart" },
    { "bad.dart", 4, 3, "warn", "dart" },
  }
)

local machine = parse.parse(
  table.concat({
    "ERROR|COMPILE_TIME_ERROR|RETURN_OF_INVALID_TYPE|" .. bad .. "|3|10|5|A value of type 'double' can't be returned.",
    "ERROR|COMPILE_TIME_ERROR|UNDEFINED_IDENTIFIER|" .. bad .. "|3|14|1|Undefined name 'b'.",
    "WARNING|STATIC_WARNING|UNUSED_LOCAL_VARIABLE|"
      .. bad
      .. "|2|9|6|The value of the local variable 'unused' isn't used.",
  }, "\n"),
  { root = dir }
)
eq("dart analyze --format=machine: absolute paths", short(machine), {
  { "bad.dart", 3, 10, "error", "dart" },
  { "bad.dart", 3, 14, "error", "dart" },
  { "bad.dart", 2, 9, "warn", "dart" },
})
eq("dart analyze --format=machine: the message", machine[2].text, "Undefined name 'b'.")

-- ── the check after accepting ───────────────────────────────────────────────
local build = require "agent.verify.build"
vim.fn.writefile({ "name: gen" }, dir .. "/pubspec.yaml")
local run = build.command_for(bad, "dart", true)
eq("verify: dart analyzes the saved file in machine format", run and run.cmd, {
  "dart",
  "analyze",
  "--no-fatal-warnings",
  "--format=machine",
  bad,
})
eq("verify: from the package root", run and run.cwd, dir)

-- ── what a Dart target calls (no call nodes in its grammar) ──────────────────
local cbuf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(cbuf, 0, -1, false, {
  "Widget build(BuildContext context) {",
  "  final x = repo.load(id);",
  "  save(x);",
  "  return Text('a', style: Theme.of(context).textTheme.bodyLarge);",
  "}",
})
vim.bo[cbuf].filetype = "dart"
local calls = require("agent.context.providers.callees").calls { buf = cbuf, lang = "dart", first = 1, last = 5 }
eq(
  "dart callees: method, function, constructor and static calls",
  vim.tbl_map(function(c)
    return c.name
  end, calls),
  { "load", "save", "Text", "of" }
)
eq(
  "dart callees: getters are not calls",
  vim.tbl_contains(
    vim.tbl_map(function(c)
      return c.name
    end, calls),
    "bodyLarge"
  ),
  false
)

-- ── generated files ─────────────────────────────────────────────────────────
local generated = require "utils.generated"
eq(
  "generated: build_runner and protobuf outputs",
  vim.tbl_map(generated.is_generated, {
    "lib/user.g.dart",
    "lib/user.freezed.dart",
    "lib/router.gr.dart",
    "test/repo.mocks.dart",
    "api/v1/user.pb.go",
    "lib/user.dart",
    "lib/config.dart",
    "main.go",
  }),
  { true, true, true, true, true, false, false, false }
)

K.project {
  ["pubspec.yaml"] = { "name: app" },
  ["lib/user.g.dart"] = { "part of 'user.dart';", "", "User _$UserFromJson(Map<String, dynamic> json) => User();" },
}
local FAKE = K.fake()
local gbuf = K.open("lib/user.g.dart", "dart")
K.at(3)
require("agent.pipeline").run "fix_block"
eq("generated: an editing action does not run there", FAKE.calls, 0)
eq("generated: and says why", K.note(FAKE):find("this file is generated", 1, true) ~= nil, true)
FAKE.text = "It maps the JSON."
require("agent.pipeline").run "explain"
K.idle()
eq("generated: reading it is fine", FAKE.calls, 1)
vim.api.nvim_buf_delete(gbuf, { force = true })

vim.fn.delete(dir, "rf")
K.finish()
