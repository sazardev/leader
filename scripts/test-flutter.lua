-- Tests of the Flutter / Dart helpers: build_runner's output (lua/dartgen/parse.lua, both formats, with the real output
-- captured from build_runner 2.16 in scripts/fixtures/dartgen), the generated parts a file expects, and the whole
-- codegen flow (lua/dartgen) against a fake `dart` that replays that output: statusline states, errors as diagnostics
-- on their file and line, the "fixed" note, the missing-part warning, light mode building once. Hermetic: no Flutter
-- SDK, network or tokens.
--   nvim -u NONE --headless -c "luafile scripts/test-flutter.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local root_dir = root
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if not vim.deep_equal(got, want) then
    fails = fails + 1
    print("FAIL " .. name)
    print("  got:  " .. vim.inspect(got))
    print("  want: " .. vim.inspect(want))
  end
end
local function ok(name, cond)
  eq(name, cond and true or false, true)
end

local notes = {}
local function note(level)
  return function(m)
    notes[#notes + 1] = level .. " " .. m
  end
end
package.loaded["utils.log"] = { info = note "info", warn = note "warn", error = note "error" }

local parse = require "dartgen.parse"

local function lines_of(name)
  return vim.fn.readfile(root .. "/scripts/fixtures/dartgen/" .. name)
end

--- Feeds lines, returns the events in order
local function run(state, lines)
  local events = {}
  for _, l in ipairs(lines) do
    local e = parse.feed(state, l)
    if e then
      events[#events + 1] = e
    end
  end
  return events
end

-- ── build_runner ≥ 2.5 ──────────────────────────────────────────────────────
local st = parse.new()
eq("new format: a good first build", run(st, lines_of "ok.txt"), { "start", "ok" })
eq("new format: the outputs it wrote", st.outputs, 2)
eq("new format: a warning is not an error", st.errors, {})

st = parse.new()
eq(
  "new format: a failed build",
  run(st, vim.list_extend({ "Starting build #2." }, lines_of "fail.txt")),
  { "start", "fail" }
)
eq("new format: both errors, with file, place and message", st.errors, {
  {
    builder = "json_serializable",
    file = "lib/user.dart",
    lnum = 13,
    col = 19,
    msg = "Could not generate `fromJson` code for `x`.",
  },
  {
    builder = "freezed",
    file = "lib/order.dart",
    lnum = 11,
    col = 1,
    msg = "Expected a method, getter, setter or operator declaration.",
  },
})
eq("new format: the next build starts clean", run(st, { "Starting build #3." }), { "start" })
eq("new format: errors are cleared on start", st.errors, {})

-- ── older build_runner ([INFO] / [SEVERE]) ──────────────────────────────────
st = parse.new()
eq(
  "old format: start, error, fail",
  run(st, {
    "[INFO] Starting Build",
    "[SEVERE] json_serializable on lib/a.dart:",
    "  Could not generate `toJson` code for `b`.",
    "  package:app/a.dart:7:3",
    "[SEVERE] Failed after 812ms",
  }),
  { "start", "fail" }
)
eq("old format: the error", st.errors, {
  {
    builder = "json_serializable",
    file = "lib/a.dart",
    lnum = 7,
    col = 3,
    msg = "Could not generate `toJson` code for `b`.",
  },
})
eq("old format: success", run(st, { "[INFO] Succeeded after 2.1s with 12 outputs (30 actions)" }), { "ok" })
eq("old format: its outputs", st.outputs, 12)
eq(
  "colors are ignored",
  run(parse.new(), { "\27[32m  Built with build_runner in 1s; wrote 0 outputs.\27[0m" }),
  { "ok" }
)

-- ── generated parts and pubspec ─────────────────────────────────────────────
eq(
  "parts: only generated ones (x.g.dart, x.freezed.dart)",
  parse.generated_parts {
    "import 'package:freezed_annotation/freezed_annotation.dart';",
    "part 'user.freezed.dart';",
    'part "user.g.dart";',
    "part 'src/helpers.dart';",
    "part of 'library.dart';",
  },
  { "user.freezed.dart", "user.g.dart" }
)
ok(
  "pubspec: build_runner under dev_dependencies",
  parse.uses_codegen "name: a\ndev_dependencies:\n  build_runner: ^2.4.0\n"
)
ok("pubspec: without it", not parse.uses_codegen "name: a\ndependencies:\n  flutter:\n    sdk: flutter\n")

-- ── completion: declarations for the project's stack ────────────────────────
local smart = require "utils.dartsmart"
local dh = require "utils.dartheader"
eq("names: widget from the file", smart.pascal "snippet_filter_bar", "SnippetFilterBar")
eq("names: provider without its suffix", smart.provider_name "cart_items_provider", "cartItems")
eq("names: notifier class", smart.notifier_name "cart_notifier", "Cart")

local RIDGE =
  dh.stack "name: ridge\ndependencies:\n  flutter:\n    sdk: flutter\n  flutter_riverpod: ^3.0.0\n  riverpod_annotation: ^3.0.0\n  freezed_annotation: ^3.1.0\ndev_dependencies:\n  freezed: ^4.0.1\n  json_serializable: ^6.14.1\n"
eq(
  "stack: ridge's",
  RIDGE,
  { flutter = true, freezed = true, json_serializable = true, drift = false, riverpod = true, consumer = true }
)

local function labels(items)
  return vim.tbl_map(function(i)
    return i.label
  end, items)
end
local function items_for(before, base, stack, file)
  return smart.items {
    before = before,
    row = #(file or {}),
    col = #before,
    file = file or {},
    base = base,
    stack = stack,
  }
end
eq("items: everything the stack allows", labels(items_for("f", "user", RIDGE)), {
  "consumer",
  "consumerstateful",
  "riverpod",
  "riverpodnotifier",
  "freezed",
  "freezedunion",
  "stateless",
  "stateful",
})
eq(
  "items: plain Flutter only gets the plain widgets",
  labels(items_for("s", "home", dh.stack "dependencies:\n  flutter:\n")),
  { "stateless", "stateful" }
)
eq("items: not inside code", items_for("  fre", "user", RIDGE), {})
eq("items: not on an empty line", items_for("", "user", RIDGE), {})
eq("items: not after other text", items_for("final x = fre", "user", RIDGE), {})

--- Applies an item the way blink does: its extra edits, then the snippet in place of what was typed
local function accept(file, before, base, label)
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, vim.list_extend(vim.deepcopy(file), { before }))
  local item
  for _, i in ipairs(items_for(before, base, RIDGE, file)) do
    if i.label == label then
      item = i
    end
  end
  -- what was typed goes (the item's range), the snippet takes its place on that same line, then the header (execute)
  local last = vim.api.nvim_buf_line_count(b)
  vim.api.nvim_buf_set_lines(b, last - 1, last, false, { "" })
  local win = vim.api.nvim_open_win(b, true, { relative = "editor", row = 0, col = 0, width = 80, height = 20 })
  vim.api.nvim_win_set_cursor(win, { last, 0 })
  vim.snippet.expand(item.textEdit.newText)
  smart.apply_header(b, item.data.header)
  vim.snippet.stop()
  local out = vim.api.nvim_buf_get_lines(b, 0, -1, false)
  vim.api.nvim_win_close(win, true)
  return out
end

eq(
  "accept freezed: class named after the file, import and both parts",
  accept({ "" }, "fre", "order_line", "freezed"),
  {
    "import 'package:freezed_annotation/freezed_annotation.dart';",
    "",
    "part 'order_line.freezed.dart';",
    "part 'order_line.g.dart';",
    "",
    "",
    "@freezed",
    "abstract class OrderLine with _$OrderLine {",
    "  const factory OrderLine({",
    "    required String id,",
    "  }) = _OrderLine;",
    "",
    "  factory OrderLine.fromJson(Map<String, Object?> json) => _$OrderLineFromJson(json);",
    "}",
  }
)
eq(
  "accept riverpod: after the existing imports, its part",
  accept({ "import 'package:flutter/material.dart';", "" }, "riv", "cart_provider", "riverpod"),
  {
    "import 'package:flutter/material.dart';",
    "import 'package:riverpod_annotation/riverpod_annotation.dart';",
    "",
    "part 'cart_provider.g.dart';",
    "",
    "@riverpod",
    "Future<Object> cart(Ref ref) async {",
    "  ",
    "}",
  }
)
eq("accept consumer: flutter_riverpod and material, no part", accept({}, "con", "snippet_filter_bar", "consumer"), {
  "import 'package:flutter_riverpod/flutter_riverpod.dart';",
  "import 'package:flutter/material.dart';",
  "",
  "class SnippetFilterBar extends ConsumerWidget {",
  "  const SnippetFilterBar({super.key});",
  "",
  "  @override",
  "  Widget build(BuildContext context, WidgetRef ref) {",
  "    return const Placeholder();",
  "  }",
  "}",
})
eq("accept: a file that already has what it needs gets nothing more", #items_for("con", "x", RIDGE, {
  "import 'package:flutter/widgets.dart';",
  "import 'package:flutter_riverpod/flutter_riverpod.dart';",
})[1].data.header, 0)

-- ── tests: the JSON reporter ────────────────────────────────────────────────
local tparse = require "darttest.parse"
local function feed_fixture(name, root)
  local st = tparse.new(root)
  for _, l in ipairs(vim.fn.readfile(root_dir .. "/scripts/fixtures/darttest/" .. name)) do
    tparse.feed(st, (l:gsub("ROOT", root)))
  end
  return st
end
local DT = feed_fixture("dart.jsonl", "/p")
eq(
  "dart: counts (the loading pseudo-test is not one)",
  tparse.summary(DT),
  { pass = 1, fail = 2, skip = 1, running = 0 }
)
eq("dart: done and failed", { DT.done, DT.success }, { true, false })
local failed = tparse.failures(DT)
eq(
  "dart: failures with full names",
  vim.tbl_map(function(t)
    return t.name
  end, failed),
  { "calc add fails", "calc throws" }
)
eq("dart: the failed expect's line from the stack trace", { failed[1].lnum, failed[1].errors[1].lnum }, { 9, 11 })
eq("dart: expected / actual", failed[1].errors[1].message, "Expected: <3>\n  Actual: <2>")
eq("dart: what the test printed", failed[1].prints, { "debug line" })
eq(
  "dart: an exception is a failure too",
  { failed[2].errors[1].message, failed[2].errors[1].lnum },
  { "Bad state: boom", 15 }
)
eq("dart: the file is absolute", failed[1].file, "/p/test/calc_test.dart")
local FT = feed_fixture("flutter.jsonl", "/r")
local widget = FT.tests[FT.order[1]]
eq(
  "flutter: testWidgets is placed on the test file's line, not flutter_test's",
  { widget.file, widget.lnum, widget.status },
  {
    "/r/test/features/practice/keyboard_required_notice_test.dart",
    11,
    "pass",
  }
)
eq("flutter: toolchain noise lines are skipped", tparse.summary(FT), { pass = 1, fail = 0, skip = 0, running = 0 })
eq("literal: quotes, escapes, raw, triple", {
  tparse.literal "'sums'",
  tparse.literal [["it\"s"]],
  tparse.literal "r'a$b'",
  tparse.literal "'''multi'''",
}, { "sums", 'it"s', "a$b", "multi" })
eq("literal: interpolation cannot be matched", tparse.literal "'value $x'", nil)

-- ── tests: what runs ────────────────────────────────────────────────────────
local dtest = require "darttest"
eq("command: flutter, a test by name", dtest.command("/r", "/r/test/a_test.dart", "calc add", true), {
  "flutter",
  "test",
  "--reporter",
  "json",
  "test/a_test.dart",
  "--plain-name",
  "calc add",
})
eq("command: dart, everything", dtest.command("/p", nil, nil, false), { "dart", "test", "--reporter", "json" })
eq(
  "counterpart: source → test",
  dtest.counterpart("/p", "/p/lib/src/cart/cart.dart"),
  "/p/test/src/cart/cart_test.dart"
)
eq(
  "counterpart: test → source",
  dtest.counterpart("/p", "/p/test/src/cart/cart_test.dart"),
  "/p/lib/src/cart/cart.dart"
)
eq("counterpart: elsewhere", dtest.counterpart("/p", "/p/tool/gen.dart"), nil)

local tbuf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(tbuf, 0, -1, false, {
  "void main() {", -- 1
  "  group('calc', () {", -- 2
  "    group('add', () {", -- 3
  "      test('sums', () {", -- 4
  "        expect(1 + 1, 2);", -- 5
  "      });", -- 6
  "    });", -- 7
  "    testWidgets('renders $x', (t) async {});", -- 8
  "  });", -- 9
  "}", -- 10
})
vim.bo[tbuf].filetype = "dart"
eq("nearest: inside a test", dtest.nearest(tbuf, 4, 10), { name = "calc add sums", kind = "test" })
eq("nearest: on a group's name", dtest.nearest(tbuf, 2, 4), { name = "calc add", kind = "group" })
eq("nearest: on the indentation of a group line", dtest.nearest(tbuf, 1, 0), { name = "calc", kind = "group" })
eq("nearest: an interpolated name cannot be run by name", dtest.nearest(tbuf, 7, 6), nil)
eq("nearest: outside any", dtest.nearest(tbuf, 0, 0), nil)

-- ── pub outdated, next to each dependency ───────────────────────────────────
local pub = require "dartpub"
local info = pub.outdated(table.concat(vim.fn.readfile(root_dir .. "/scripts/fixtures/dartpub/outdated.json"), "\n"))
eq("outdated: every package of the real answer", vim.tbl_count(info), 50)
eq("outdated: versions", info.build_runner, {
  kind = "dev",
  current = "2.16.1",
  upgradable = "2.16.2",
  latest = "2.17.1",
  discontinued = false,
  advisory = false,
  retracted = false,
})
eq("outdated: not JSON", pub.outdated "Resolving dependencies...", nil)
local fake = {
  go_router = { kind = "direct", current = "18.0.1", upgradable = "18.1.0", latest = "18.1.0" },
  intl = { kind = "direct", current = "0.19.0", upgradable = "0.19.0", latest = "0.20.2" },
  flutter_lints = { kind = "dev", current = "5.0.0", upgradable = "5.0.0", latest = "5.0.0" },
  old_pkg = { kind = "direct", current = "1.0.0", upgradable = "1.0.0", latest = "1.0.0", discontinued = true },
  build_runner = info.build_runner,
  meta = { kind = "transitive", current = "1.0.0", upgradable = "1.1.0", latest = "1.1.0" },
}
eq(
  "annotations: behind, constraint to change, flagged; never the up to date, transitive or other sections",
  pub.annotations({
    "name: app", -- 1
    "version: 1.0.0", -- 2
    "dependencies:", -- 3
    "  go_router: ^18.0.1", -- 4
    "  intl: ^0.19.0", -- 5
    "  old_pkg: ^1.0.0", -- 6
    "  meta: any", -- 7
    "dev_dependencies:", -- 8
    "  flutter_lints: ^5.0.0", -- 9
    "  build_runner: ^2.16.1", -- 10
    "flutter:", -- 11
    "  go_router: x", -- 12
  }, fake),
  {
    { lnum = 4, text = "↑ 18.1.0", hl = "DartPubUpgrade" },
    { lnum = 5, text = "latest 0.20.2 (change the constraint)", hl = "DartPubMajor" },
    { lnum = 6, text = "discontinued · latest 1.0.0", hl = "DartPubWarn" },
    { lnum = 10, text = "↑ 2.16.2 · latest 2.17.1", hl = "DartPubUpgrade" },
  }
)

-- ── run: entry points ───────────────────────────────────────────────────────
local drun = require "dartrun"
eq(
  "entries: main first, the rest by name, labelled after main_",
  vim.tbl_map(function(e)
    return e.label
  end, drun.entries { "main_squats.dart", "app.dart", "main.dart", "main_plank.dart" }),
  { "main  lib/main.dart", "plank  lib/main_plank.dart", "squats  lib/main_squats.dart" }
)
local last_first = drun.entries({ "main.dart", "main_plank.dart", "main_squats.dart" }, "lib/main_squats.dart")
eq(
  "entries: the last one used first, marked",
  { last_first[1].target, last_first[1].current },
  { "lib/main_squats.dart", true }
)
eq("entries: none", drun.entries { "app.dart" }, {})

-- ── run: devices (flutter devices --machine) ────────────────────────────────
local ddev = require "dartrun.devices"
local machine = vim.split(
  [=[Resolving dependencies...
[
  {"name":"Pixel 7","id":"AB12","isSupported":true,"targetPlatform":"android-arm64","emulator":false},
  {"name":"sdk gphone64","id":"emulator-5554","isSupported":true,"targetPlatform":"android-x64","emulator":true},
  {"name":"iPhone 15","id":"SIM1","isSupported":true,"targetPlatform":"ios","emulator":true},
  {"name":"Linux","id":"linux","isSupported":true,"targetPlatform":"linux-x64","emulator":false},
  {"name":"Chrome","id":"chrome","isSupported":true,"targetPlatform":"web-javascript","emulator":false},
  {"name":"macOS","id":"macos","isSupported":false,"targetPlatform":"darwin","emulator":false}
]]=],
  "\n"
)
local devs = ddev.parse(machine)
eq("devices: notices before the JSON are skipped", #devs, 6)
eq("devices: nothing to parse", ddev.parse { "No devices found" }, {})
local folders = { android = true, linux = true } -- the project has no ios/ and no web/
eq(
  "devices: unsupported and platforms the project lacks are dropped",
  vim.tbl_map(function(d)
    return d.id
  end, ddev.usable(devs, function(f)
    return folders[f] == true
  end)),
  { "AB12", "emulator-5554", "linux" }
)
eq(
  "devices: the last first, then phone, emulators (by name), desktop, web",
  vim.tbl_map(function(d)
    return d.id
  end, ddev.order(devs, "chrome")),
  { "chrome", "AB12", "SIM1", "emulator-5554", "linux", "macos" }
)
local rows = ddev.entries(devs, "AB12", "profile")
eq("devices: the last one is marked", { rows[1].device.id, rows[1].current }, { "AB12", true })
local labels = {}
for _, r in ipairs(rows) do
  labels[r.device.id] = r.label
end
eq("devices: an Android emulator runs profile, no warning", labels["emulator-5554"], "sdk gphone64  android-x64  · emulator")
eq("devices: the iOS simulator only runs debug, and says so", labels.SIM1, "iPhone 15  ios  · emulator, no profile")
eq("devices: debug mode adds nothing", ddev.entries(devs, nil, "debug")[3].label:find("no ", 1, true), nil)

-- ── run: the launch configuration (device and mode are TOOL arguments) ──────
local sdk = { dart_sdk = "/sdk/dart", flutter_sdk = "/sdk" }
local cfg = drun.launch_config { paths = sdk, root = "/p", target = "lib/main_dev.dart", device = "AB12", mode = "profile" }
eq("launch: profile goes in toolArgs, after -d", cfg.toolArgs, { "-d", "AB12", "--profile" })
eq("launch: target, cwd and sdk", { cfg.program, cfg.cwd, cfg.flutterSdkPath }, { "lib/main_dev.dart", "/p", "/sdk" })
eq("launch: never in args (the adapter would start paused)", cfg.args, nil)
eq("launch: debug adds no mode", drun.launch_config({ paths = sdk, root = "/p", device = "linux" }).toolArgs, { "-d", "linux" })
eq("launch: release", drun.launch_config({ paths = sdk, root = "/p", mode = "release" }).toolArgs, { "--release" })
eq("launch: default target", drun.launch_config({ paths = sdk, root = "/p" }).program, "lib/main.dart")

-- ── run: the statusline chip ────────────────────────────────────────────────
local dstate = require "dartrun.state"
eq("chip: nothing runs", dstate.text(nil), "")
eq("chip: building", dstate.text { device = "Pixel 7", started = false }, "◌ Pixel 7")
eq("chip: running", dstate.text { device = "Pixel 7", started = true, mode = "debug" }, "▶ Pixel 7")
eq("chip: profile says so", dstate.text { device = "Pixel 7", started = true, mode = "profile" }, "▶ Pixel 7 · profile")
eq("chip: stopped at a breakpoint", dstate.text { device = "Linux", started = true, stopped = true }, "⏸ Linux")
eq("chip: device not known yet", dstate.text { started = true }, "▶ running")
eq("chip: debug is green", dstate.group { started = true, mode = "debug" }, "FlutterRunning")
eq("chip: profile is apart", dstate.group { started = true, mode = "profile" }, "FlutterProfile")
eq("chip: building and stopped are yellow", { dstate.group { started = false }, dstate.group { started = true, stopped = true } }, { "FlutterStarting", "FlutterStarting" })
eq("chip: no app, no running state", dstate.current(), nil)

-- ── translations: what gen-l10n says went wrong ─────────────────────────────
eq(
  "l10n: the ICU error line",
  require("dartgen").l10n_error 'Because l10n.yaml exists, the options defined there will be used\n[app_en.arb:greeting] ICU Syntax Error: Expected "}" but found no tokens.\n',
  '[app_en.arb:greeting] ICU Syntax Error: Expected "}" but found no tokens.'
)

-- ── the whole flow, against a fake `dart` ───────────────────────────────────
-- the fake prints ok.txt for `build`; for `watch` it prints a good build, then a failed one, then a good one again
local tmp = vim.fn.tempname()
local bin, pkg = tmp .. "/bin", tmp .. "/pkg"
vim.fn.mkdir(bin, "p")
vim.fn.mkdir(pkg .. "/lib", "p")
local fixtures = root .. "/scripts/fixtures/dartgen"
vim.fn.writefile({
  "#!/bin/sh",
  -- `dart test --reporter json …`: the captured run, with its paths pointing at this package
  'if [ "$1" = "test" ]; then sed "s#ROOT#$PWD#g" ' .. root_dir .. "/scripts/fixtures/darttest/dart.jsonl; exit 1; fi",
  'if [ "$3" = "build" ]; then cat ' .. fixtures .. "/ok.txt; exit 0; fi",
  "cat " .. fixtures .. "/ok.txt",
  "sleep 0.3; echo 'Starting build #2.'; cat " .. fixtures .. "/fail.txt",
  "sleep 0.3; echo 'Starting build #3.'; echo '  Built with build_runner/aot in 0s; wrote 1 outputs.'",
  "trap 'exit 0' INT; while :; do sleep 0.1; done",
}, bin .. "/dart")
vim.fn.setfperm(bin .. "/dart", "rwxr-xr-x")
vim.env.PATH = bin .. ":" .. vim.env.PATH
vim.fn.writefile({ "name: gen", "dev_dependencies:", "  build_runner: any" }, pkg .. "/pubspec.yaml")
vim.fn.writefile({ "part 'user.g.dart';", "class User {}" }, pkg .. "/lib/user.dart")

local gen = require "dartgen"
gen.setup()
vim.cmd("silent edit " .. pkg .. "/lib/user.dart")
local buf = vim.api.nvim_get_current_buf()
ok(
  "missing part: warned once when the file opens",
  notes[#notes] and notes[#notes]:find("user.g.dart does not exist yet", 1, true)
)
local count = #notes
gen.check_parts(buf)
eq("missing part: not repeated", #notes, count)

eq("statusline: nothing before it runs", gen.statusline(), "")
gen.toggle()
local job = gen.job(pkg)
ok("watch: running", job and job.proc and job.watch)
local ns = vim.api.nvim_create_namespace "dartgen"
vim.wait(5000, function()
  return job.status == "failed"
end, 20)
eq("watch: a failed build shows in the statusline", gen.statusline(), "gen ✗ 2")
local diags = vim.diagnostic.get(buf, { namespace = ns })
eq(
  "watch: the error lands on its file, line and column",
  diags[1] and { diags[1].lnum, diags[1].col, diags[1].source },
  {
    12,
    18,
    "json_serializable",
  }
)
ok("watch: one notification names the first error", notes[#notes]:find("Codegen failed: 2 errors", 1, true))
vim.wait(5000, function()
  return job.status == "ok"
end, 20)
eq("watch: the next good build clears the diagnostics", #vim.diagnostic.get(buf, { namespace = ns }), 0)
eq("watch: and says it is fixed", notes[#notes], "info Codegen fixed: build_runner is up to date")
eq("watch: up to date in the statusline", gen.statusline(), "gen")
gen.toggle()
vim.wait(3000, function()
  return job.proc == nil
end, 20)
eq("watch: stopped, nothing in the statusline", gen.statusline(), "")
ok("watch: the process is gone", job.proc == nil)

-- light mode: the toggle builds once instead of keeping a watch
package.loaded["core.light"] = { enabled = true }
gen.toggle()
local once = gen.job(pkg)
ok("light mode: builds once", once and not once.watch)
vim.wait(3000, function()
  return once.proc == nil
end, 20)
eq("light mode: a finished build leaves the statusline empty", gen.statusline(), "")
ok("light mode: says how many files it wrote", notes[#notes]:find("Codegen done: 2 files written", 1, true))

-- tests through the fake `dart test`: marks, diagnostics, quickfix, note
vim.fn.mkdir(pkg .. "/test", "p")
vim.fn.writefile(
  vim.fn.readfile(root_dir .. "/scripts/fixtures/darttest/calc_test.dart"),
  pkg .. "/test/calc_test.dart"
)
dtest.setup()
vim.cmd("silent edit " .. pkg .. "/test/calc_test.dart")
local cbuf = vim.api.nvim_get_current_buf()
notes = {}
dtest.run "file"
vim.wait(5000, function()
  return #notes > 1
end, 20)
ok("run: one note sums it up", notes[#notes]:find("Tests failed: 2 of 3 · 1 skipped · calc add fails", 1, true))
local tmarks = {}
for _, m in
  ipairs(vim.api.nvim_buf_get_extmarks(cbuf, vim.api.nvim_create_namespace "darttest.marks", 0, -1, { details = true }))
do
  tmarks[#tmarks + 1] = (m[2] + 1) .. vim.trim(m[4].sign_text)
end
eq("run: a mark on each test line", tmarks, { "6✓", "9✗", "14✗", "17○" })
local tdiags = vim.diagnostic.get(cbuf, { namespace = vim.api.nvim_create_namespace "darttest" })
eq(
  "run: failures on the failing lines",
  vim.tbl_map(function(d)
    return d.lnum + 1
  end, tdiags),
  { 11, 15 }
)
eq("run: the quickfix has them", #vim.fn.getqflist(), 2)
eq("run: nothing running afterwards", dtest.statusline(), "")

vim.fn.delete(tmp, "rf")
print(fails == 0 and ("ALL OK (" .. total .. " checks)") or ("FAILURES: " .. fails .. " of " .. total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
