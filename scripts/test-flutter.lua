-- Tests of the Flutter / Dart helpers: build_runner's output (lua/dartgen/parse.lua, both formats, with the real output
-- captured from build_runner 2.16 in scripts/fixtures/dartgen), the generated parts a file expects, and the whole
-- codegen flow (lua/dartgen) against a fake `dart` that replays that output: statusline states, errors as diagnostics
-- on their file and line, the "fixed" note, the missing-part warning, light mode building once. Hermetic: no Flutter
-- SDK, network or tokens.
--   nvim -u NONE --headless -c "luafile scripts/test-flutter.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
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
package.loaded["utils.log"] = { info = note("info"), warn = note("warn"), error = note("error") }

local parse = require("dartgen.parse")

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
eq("new format: a good first build", run(st, lines_of("ok.txt")), { "start", "ok" })
eq("new format: the outputs it wrote", st.outputs, 2)
eq("new format: a warning is not an error", st.errors, {})

st = parse.new()
eq(
	"new format: a failed build",
	run(st, vim.list_extend({ "Starting build #2." }, lines_of("fail.txt"))),
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
	parse.generated_parts({
		"import 'package:freezed_annotation/freezed_annotation.dart';",
		"part 'user.freezed.dart';",
		'part "user.g.dart";',
		"part 'src/helpers.dart';",
		"part of 'library.dart';",
	}),
	{ "user.freezed.dart", "user.g.dart" }
)
ok(
	"pubspec: build_runner under dev_dependencies",
	parse.uses_codegen("name: a\ndev_dependencies:\n  build_runner: ^2.4.0\n")
)
ok("pubspec: without it", not parse.uses_codegen("name: a\ndependencies:\n  flutter:\n    sdk: flutter\n"))

-- ── completion: declarations for the project's stack ────────────────────────
local smart = require("utils.dartsmart")
local dh = require("utils.dartheader")
eq("names: widget from the file", smart.pascal("snippet_filter_bar"), "SnippetFilterBar")
eq("names: provider without its suffix", smart.provider_name("cart_items_provider"), "cartItems")
eq("names: notifier class", smart.notifier_name("cart_notifier"), "Cart")

local RIDGE =
	dh.stack("name: ridge\ndependencies:\n  flutter:\n    sdk: flutter\n  flutter_riverpod: ^3.0.0\n  riverpod_annotation: ^3.0.0\n  freezed_annotation: ^3.1.0\ndev_dependencies:\n  freezed: ^4.0.1\n  json_serializable: ^6.14.1\n")
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
	return smart.items({
		before = before,
		row = #(file or {}),
		col = #before,
		file = file or {},
		base = base,
		stack = stack,
	})
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
	labels(items_for("s", "home", dh.stack("dependencies:\n  flutter:\n"))),
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

-- ── the whole flow, against a fake `dart` ───────────────────────────────────
-- the fake prints ok.txt for `build`; for `watch` it prints a good build, then a failed one, then a good one again
local tmp = vim.fn.tempname()
local bin, pkg = tmp .. "/bin", tmp .. "/pkg"
vim.fn.mkdir(bin, "p")
vim.fn.mkdir(pkg .. "/lib", "p")
local fixtures = root .. "/scripts/fixtures/dartgen"
vim.fn.writefile({
	"#!/bin/sh",
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

local gen = require("dartgen")
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
local ns = vim.api.nvim_create_namespace("dartgen")
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

vim.fn.delete(tmp, "rf")
print(fails == 0 and ("ALL OK (" .. total .. " checks)") or ("FAILURES: " .. fails .. " of " .. total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
