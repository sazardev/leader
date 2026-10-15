-- Tests of how type definitions are compacted for the prompt (agent/context/providers/types.lua `compact`): comments
-- and blank lines dropped, `#` kept where it is not a comment, long enums joined and capped. Hermetic: no LSP or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq = K.eq

local compact = require("agent.context.providers.types").compact

eq(
  "go: doc comments and blank lines go, trailing comments stay",
  compact({
    "// Note is a note.",
    "type Note struct {",
    "\t// ID is the key.",
    "\tID string // uuid",
    "",
    "\tTitle string",
    "}",
  }, "go"),
  { "type Note struct {", "\tID string // uuid", "\tTitle string", "}" }
)

eq(
  "dart: /// and /* */ blocks go",
  compact({
    "/// A user.",
    "class User {",
    "  /**",
    "   * The name.",
    "   */",
    "  final String name;",
    "}",
  }, "dart"),
  { "class User {", "  final String name;", "}" }
)

eq(
  "rust: #[derive] is code, not a comment",
  compact({ "/// A point.", "#[derive(Debug)]", "struct P { x: i32 }" }, "rust"),
  {
    "#[derive(Debug)]",
    "struct P { x: i32 }",
  }
)
eq(
  "python: # is a comment",
  compact({ "class A:", "    # the id", "    id: int" }, "python"),
  { "class A:", "    id: int" }
)
eq("comments can be kept", compact({ "type A struct {", "\t// why", "\tX int", "}" }, "go", true), {
  "type A struct {",
  "\t// why",
  "\tX int",
  "}",
})

local values = { "enum Lang {" }
for i = 1, 30 do
  values[#values + 1] = "  /// value " .. i
  values[#values + 1] = "  v" .. i .. ","
end
values[#values + 1] = "}"
local out = compact(values, "dart")
eq("enum: values joined in a few lines", #out <= 6, true)
eq("enum: the first ones are shown", out[2]:match "^  v1, v2, v3," ~= nil, true)
eq("enum: the rest is counted", table.concat(out, "\n"):find("v24, … (6 more)", 1, true) ~= nil, true)
eq(
  "enum: short runs stay one per line",
  compact({ "enum A {", "  x,", "  y,", "}" }, "dart"),
  { "enum A {", "  x,", "  y,", "}" }
)
eq(
  "enum: values with a payload are not joined",
  compact({ "enum A {", "  a(1),", "  b(2),", "  c(3),", "  d(4),", "}" }, "dart"),
  {
    "enum A {",
    "  a(1),",
    "  b(2),",
    "  c(3),",
    "  d(4),",
    "}",
  }
)

K.finish()
