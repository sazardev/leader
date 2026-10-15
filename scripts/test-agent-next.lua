-- Tests of "next edit" (agent/edits.lua, actions/next.lua): the hunks of what you changed (pure), how they are rendered
-- within a budget, the per-buffer tracker, and the flow with a fake model: no edits = no request, edits = a proposal over
-- the lines around the cursor. Hermetic: no network or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local edits = require "agent.edits"

-- ── hunks (pure) ────────────────────────────────────────────────────────────
eq("hunks: nothing changed", edits.hunks({ "a", "b" }, { "a", "b" }), {})
eq(
  "hunks: a replaced line",
  edits.hunks({ "a", "b", "c" }, { "a", "B", "c" }),
  { { line = 2, old = { "b" }, new = { "B" } } }
)
eq("hunks: an added line", edits.hunks({ "a", "c" }, { "a", "b", "c" }), { { line = 2, old = {}, new = { "b" } } })
eq("hunks: a removed line", edits.hunks({ "a", "b", "c" }, { "a", "c" }), { { line = 2, old = { "b" }, new = {} } })
eq(
  "hunks: two separate changes are two hunks",
  #edits.hunks({ "a", "b", "c", "d", "e" }, { "A", "b", "c", "d", "E" }),
  2
)
local long = {}
for i = 1, 30 do
  long[i] = "line" .. i
end
local h = edits.hunks({ "x" }, long)[1]
eq("hunks: a long side is cut", #h.new, 11)
ok("hunks: and says how many it left out", h.new[11]:find("more lines", 1, true) ~= nil)

-- ── render ──────────────────────────────────────────────────────────────────
local sample = {
  { line = 3, old = { "x := 1" }, new = { "y := 1" } },
  { line = 9, old = {}, new = { "z := 2" } },
}
eq("render: oldest first, - and + lines", edits.render(sample, 1000), "@@ line 3\n-x := 1\n+y := 1\n@@ line 9\n+z := 2")
eq("render: when it is tight the newest win", edits.render(sample, 20), "@@ line 9\n+z := 2")
eq("render: nothing, nothing", edits.render({}, 100), "")

-- ── the tracker ─────────────────────────────────────────────────────────────
K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["a.go"] = {
    "package p", -- 1
    "", -- 2
    "func One() int {", -- 3
    "\treturn 1", -- 4
    "}", -- 5
    "", -- 6
    "func Two() int {", -- 7
    "\treturn 1", -- 8
    "}", -- 9
  },
}
local FAKE = K.fake()
edits.reset()
local buf = K.open "a.go"
edits.watch(buf)
eq("tracker: nothing changed yet", edits.get(buf), {})
vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "\treturn 100" })
eq("tracker: an edit is seen", edits.get(buf), { { line = 4, old = { "\treturn 1" }, new = { "\treturn 100" } } })
eq("tracker: and seen once", #edits.get(buf), 1)
for i = 1, 10 do
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "// " .. i })
  edits.record(buf)
end
eq("tracker: only the latest are kept", #edits.get(buf), require("core.settings").agent.next_edit.keep)

-- ── the flow ────────────────────────────────────────────────────────────────
local pipeline = require "agent.pipeline"
local replace = require "agent.output.replace"

edits.reset()
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "" })
vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "\treturn 1" })
edits.watch(buf)
K.at(8)
pipeline.run "next"
K.idle()
eq("flow: with no recent edits it asks nothing", FAKE.calls, 0)
ok("flow: and says why", K.note(FAKE):find("no recent edits", 1, true) ~= nil)

vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "\treturn 100" })
edits.record(buf)
local window = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local predicted = vim.deepcopy(window)
predicted[8] = "\treturn 100"
FAKE.text = "```go\n" .. table.concat(predicted, "\n") .. "\n```"
K.at(8)
pipeline.run "next"
K.idle()
eq("flow: with edits it asks once", FAKE.calls, 1)
ok(
  "flow: the prompt carries the recent edit",
  FAKE.req.prompt:find("<edits>", 1, true) ~= nil and FAKE.req.prompt:find("+\treturn 100", 1, true) ~= nil
)
ok("flow: and the window around the cursor as the target", FAKE.req.prompt:find("func Two()", 1, true) ~= nil)
local pending = replace.pending()
eq("flow: a proposal is waiting", #pending, 1)
replace.accept()
eq("flow: accepting applies the predicted edit", vim.api.nvim_buf_get_lines(buf, 7, 8, false), { "\treturn 100" })

K.finish()
