-- Tests of the convert action (agent/convert.lua + agent/actions/convert.lua): recognising the source, what it becomes per
-- language, where it refuses, and the whole flow with a fake model (the JSON is replaced by the code). Hermetic: no network
-- or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local convert = require "agent.convert"

-- ── what the selection is ───────────────────────────────────────────────────
eq("detect: a JSON object", convert.detect { '  {"id": 1,', '"name": "x"}' }, "json")
eq("detect: a JSON array", convert.detect { "[", "  {}", "]" }, "json")
eq("detect: CREATE TABLE in any case", convert.detect { "Create Table notes (", "  id serial", ");" }, "sql")
eq("detect: CREATE TABLE after a comment line", convert.detect { "-- notes", "CREATE TABLE notes (id int);" }, "sql")
eq("detect: curl", convert.detect { "curl -X POST https://api.x/v1 \\", "  -H 'A: b'" }, "curl")
eq("detect: a shell prompt before curl", convert.detect { "$ curl https://x" }, "curl")
eq("detect: plain code is none of them", convert.detect { "func Add() {}" }, nil)
eq("detect: a SELECT is not a table", convert.detect { "SELECT * FROM notes" }, nil)

-- ── what it becomes ─────────────────────────────────────────────────────────
eq("language: tsx converts into typescript", convert.language "typescriptreact", "typescript")
eq("language: jsx stays javascript", convert.language "javascriptreact", "javascript")
ok(
  "goal: JSON in JavaScript is JSDoc, never TypeScript",
  convert.goal("json", "javascript"):find("no TypeScript syntax", 1, true) ~= nil
)
eq("language: a JSON file is not a destination", convert.language "json", nil)
ok("goal: JSON in Go asks for json tags", convert.goal("json", "go"):find("`json` tags", 1, true) ~= nil)
ok("goal: SQL in Go maps nullable columns to pointers", convert.goal("sql", "go"):find("pointers", 1, true) ~= nil)
ok("goal: curl never keeps secrets as literals", convert.goal("curl", "go"):find("never literals", 1, true) ~= nil)
ok(
  "goal: any other language gets the generic recipe",
  convert.goal("json", "Swift"):find("idiomatic Swift", 1, true) ~= nil
)

-- ── spacing between declarations ────────────────────────────────────────────
eq(
  "spaced: go types glued together get a blank line",
  convert.spaced({ "type A struct {", "\tX int", "}", "type B struct{}", "func F() {}" }, "go"),
  {
    "type A struct {",
    "\tX int",
    "}",
    "",
    "type B struct{}",
    "func F() {}",
  }
)
eq(
  "spaced: what is already spaced stays as it is",
  convert.spaced({ "interface A {", "  x: number", "}", "", "interface B {}" }, "typescript"),
  {
    "interface A {",
    "  x: number",
    "}",
    "",
    "interface B {}",
  }
)
eq(
  "spaced: python gets two blank lines and keeps decorators on their class",
  convert.spaced({ "@dataclass", "class A:", "    x: int", "@dataclass", "class B:", "    y: str" }, "python"),
  {
    "@dataclass",
    "class A:",
    "    x: int",
    "",
    "",
    "@dataclass",
    "class B:",
    "    y: str",
  }
)
eq(
  "spaced: a rust derive starts a declaration",
  convert.spaced({ "struct A {", "}", "#[derive(Debug)]", "struct B;" }, "rust"),
  {
    "struct A {",
    "}",
    "",
    "#[derive(Debug)]",
    "struct B;",
  }
)

-- ── Dart projects with code generation ──────────────────────────────────────
local stack =
  convert.dart_stack "name: a\ndependencies:\n  freezed_annotation: ^3.1.0\n  drift: ^2.0.0\ndev_dependencies:\n  freezed: ^4.0.1\n  json_serializable: ^6.14.1\n"
eq(
  "dart stack: read from pubspec",
  { stack.freezed, stack.json_serializable, stack.drift, stack.riverpod },
  { true, true, true, false }
)
eq(
  "dart stack: freezed_annotation alone is not freezed",
  convert.dart_stack("dependencies:\n  freezed_annotation: any\n").freezed,
  false
)
ok(
  "dart goal: JSON with freezed gives freezed classes",
  convert.goal("json", "dart", stack):find("@freezed abstract class", 1, true) ~= nil
)
ok(
  "dart goal: JSON with json_serializable only",
  convert.goal("json", "dart", { json_serializable = true }):find("@JsonSerializable()", 1, true) ~= nil
)
ok("dart goal: SQL with drift gives tables", convert.goal("sql", "dart", stack):find("extends Table", 1, true) ~= nil)
ok("dart goal: no generators, plain classes", convert.goal("json", "dart", {}):find("fromJson", 1, true) ~= nil)
ok(
  "dart goal: curl ignores the stack",
  convert.goal("curl", "dart", stack):find("dart function that sends", 1, true) ~= nil
)

eq(
  "json keys: nested ones too, sorted",
  convert.json_keys { '{"id": 1, "full_name": "x", "items": [{"unit_price": 2}]}' },
  {
    "full_name",
    "id",
    "items",
    "unit_price",
  }
)
eq("json keys: not JSON", convert.json_keys { "{ nope" }, nil)
eq(
  "camel: snake and kebab",
  { convert.camel "created_at", convert.camel "unit-price", convert.camel "id" },
  { "createdAt", "unitPrice", "id" }
)
eq(
  "dart keys: the forgotten @JsonKey is added, the others stay",
  convert.dart_json_keys({
    "  const factory Order({",
    "    required String id,",
    "    String? couponCode,",
    "    required DateTime createdAt,",
    "    @JsonKey(name: 'full_name') required String fullName,",
    "  }) = _Order;",
  }, { "coupon_code", "created_at", "full_name", "id" }),
  {
    "  const factory Order({",
    "    required String id,",
    "    @JsonKey(name: 'coupon_code') String? couponCode,",
    "    @JsonKey(name: 'created_at') required DateTime createdAt,",
    "    @JsonKey(name: 'full_name') required String fullName,",
    "  }) = _Order;",
  }
)
eq(
  "dart keys: json_serializable fields and constructor parameters",
  convert.dart_json_keys(
    { "  final DateTime createdAt;", "  const Order({required this.createdAt});" },
    { "created_at" }
  ),
  { "  @JsonKey(name: 'created_at') final DateTime createdAt;", "  const Order({required this.createdAt});" }
)

local FREEZED = {
  "@freezed",
  "abstract class User with _$User {",
  "  factory User.fromJson(Map<String, Object?> json) => _$UserFromJson(json);",
  "}",
}
eq("header: an empty file gets the import and both parts on top", convert.header({ "", "@freezed" }, "user", FREEZED), {
  {
    row = 0,
    lines = {
      "import 'package:freezed_annotation/freezed_annotation.dart';",
      "",
      "part 'user.freezed.dart';",
      "part 'user.g.dart';",
      "",
    },
  },
})
eq(
  "header: after the existing imports, parts below them",
  convert.header({ "import 'package:flutter/material.dart';", "", "@freezed" }, "user", FREEZED),
  {
    { row = 1, lines = { "", "part 'user.freezed.dart';", "part 'user.g.dart';" } },
    { row = 1, lines = { "import 'package:freezed_annotation/freezed_annotation.dart';" } },
  }
)
eq(
  "header: nothing that is already there",
  convert.header({
    "import 'package:freezed_annotation/freezed_annotation.dart';",
    "",
    "part 'user.freezed.dart';",
    "part 'user.g.dart';",
  }, "user", FREEZED),
  {}
)
eq(
  "header: freezed without fromJson needs no .g.dart",
  convert.header({}, "a", { "@freezed", "abstract class A with _$A {}" }),
  {
    {
      row = 0,
      lines = { "import 'package:freezed_annotation/freezed_annotation.dart';", "", "part 'a.freezed.dart';", "" },
    },
  }
)
eq(
  "header: drift only imports drift",
  convert.header({ "import 'x.dart';" }, "t", { "class Notes extends Table {}" }),
  {
    { row = 1, lines = { "import 'package:drift/drift.dart';" } },
  }
)
eq("header: plain code needs nothing", convert.header({}, "a", { "class A {}" }), {})

-- ── the action ──────────────────────────────────────────────────────────────
local action = require("agent.actions").get "convert"
eq(
  "check: refuses outside a code file",
  action.check({ lang = "json", lines = { "{}" } }):find("not a programming language", 1, true) ~= nil,
  true
)
ok("check: refuses what it cannot recognise", action.check { lang = "go", lines = { "x := 1" } } ~= nil)
eq("check: accepts JSON in a Go file", action.check { lang = "go", lines = { "{}" } }, nil)

-- ── whole flow: JSON pasted in a Go file becomes the structs, in its place ──
K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["note.go"] = {
    "package p", -- 1
    "", -- 2
    "{", -- 3
    '  "id": 7,', -- 4
    '  "title": "x"', -- 5
    "}", -- 6
  },
}
local FAKE = K.fake()
local pipeline = require "agent.pipeline"
local replace = require "agent.output.replace"
local buf = K.open "note.go"

FAKE.input = "Note"
FAKE.text = '```go\ntype Note struct {\n\tID    int64  `json:"id"`\n\tTitle string `json:"title"`\n}\n```'
K.at(4)
pipeline.run "convert"
K.idle()
eq("flow: one request", FAKE.calls, 1)
ok("flow: the recipe for JSON in Go is in the request", FAKE.req.system:find("`json` tags", 1, true) ~= nil)
ok("flow: the source is named", FAKE.req.system:find("is a JSON sample", 1, true) ~= nil)
ok("flow: the root name travels as the instruction", (FAKE.req.prompt or ""):find("Note", 1, true) ~= nil)
replace.accept()
eq("flow: accepting puts the struct where the JSON was", vim.api.nvim_buf_get_lines(buf, 0, -1, false), {
  "package p",
  "",
  "type Note struct {",
  '\tID    int64  `json:"id"`',
  '\tTitle string `json:"title"`',
  "}",
})

-- two glued types come out spaced
FAKE.text = '```go\ntype A struct {\n\tB B `json:"b"`\n}\ntype B struct {\n\tX int64 `json:"x"`\n}\n```'
vim.api.nvim_buf_set_lines(buf, 2, -1, false, { '{"b": {"x": 1}}' })
K.at(3)
pipeline.run "convert"
K.idle()
eq("flow: the proposal separates the declarations", replace.pending()[1] and replace.pending()[1].lines, {
  "type A struct {",
  '\tB B `json:"b"`',
  "}",
  "",
  "type B struct {",
  '\tX int64 `json:"x"`',
  "}",
})

-- ── whole flow in a freezed project: the answer replaces the JSON, the header lines arrive on accept ──
K.project {
  ["pubspec.yaml"] = {
    "name: app",
    "dependencies:",
    "  freezed_annotation: ^3.1.0",
    "dev_dependencies:",
    "  freezed: ^4.0.1",
    "  json_serializable: ^6.14.1",
  },
  ["lib/user.dart"] = {
    "import 'package:flutter/foundation.dart';", -- 1
    "", -- 2
    '{"id": 1, "full_name": "x"}', -- 3
  },
}
local dbuf = K.open("lib/user.dart", "dart")
FAKE.input = "User"
FAKE.text =
  "```dart\n@freezed\nabstract class User with _$User {\n  const factory User({required int id, @JsonKey(name: 'full_name') required String fullName}) = _User;\n  factory User.fromJson(Map<String, Object?> json) => _$UserFromJson(json);\n}\n```"
K.at(3)
pipeline.run "convert"
K.idle()
ok("dart flow: the request asks for freezed", FAKE.req.system:find("@freezed abstract class", 1, true) ~= nil)
replace.accept()
eq("dart flow: code in place, import and parts added at the top", vim.api.nvim_buf_get_lines(dbuf, 0, -1, false), {
  "import 'package:flutter/foundation.dart';",
  "import 'package:freezed_annotation/freezed_annotation.dart';",
  "",
  "part 'user.freezed.dart';",
  "part 'user.g.dart';",
  "",
  "@freezed",
  "abstract class User with _$User {",
  "  const factory User({required int id, @JsonKey(name: 'full_name') required String fullName}) = _User;",
  "  factory User.fromJson(Map<String, Object?> json) => _$UserFromJson(json);",
  "}",
})

K.finish()
