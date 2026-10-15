-- Tests of the keys the agent's hints advertise: they must work from where the cursor is. The answer window never takes
-- focus, so its follow-up key ("Tab ask more") has to be bound on the code buffer while the answer is on screen, go away
-- with it, and not break a proposal that uses the same key. Hermetic: no network or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["a.go"] = {
    "package p", -- 1
    "", -- 2
    "func One() int {", -- 3
    "\treturn 1", -- 4
    "}", -- 5
  },
}
local FAKE = K.fake()
local pipeline = require "agent.pipeline"
local replace = require "agent.output.replace"
local float = require "agent.ui.float"
local buf = K.open "a.go"
local KEY = require("core.settings").agent.keys.refine

--- The buffer-local mapping of the refine key in the code buffer, if any
local function code_map()
  return vim.api.nvim_buf_call(buf, function()
    local m = vim.fn.maparg(KEY, "n", false, true)
    return m.buffer == 1 and m or nil
  end)
end

ok("setup: the refine key is Tab", KEY == "<Tab>")
eq("before an answer, the code buffer has no such mapping", code_map(), nil)

-- ── the answer window ───────────────────────────────────────────────────────
FAKE.text = "It returns one."
K.at(3)
pipeline.run "explain"
K.idle()
ok("answer: the window did not take focus (the cursor is still in the code)", vim.api.nvim_get_current_buf() == buf)
local m = code_map()
eq("answer: so its follow-up key is bound on the code", m and m.desc, "Agent ask more")

-- pressing it, from the code, asks the next question with the answer as the conversation
FAKE.input = "and why?"
m.callback()
K.idle()
eq("answer: the key asks the follow-up", FAKE.calls, 2)
ok(
  "answer: carrying the earlier answer",
  FAKE.req.prompt:find("<conversation>", 1, true) ~= nil and FAKE.req.prompt:find("It returns one.", 1, true) ~= nil
)
ok("answer: the first window was replaced by the new answer", vim.api.nvim_get_current_buf() == buf)

-- moving the cursor closes the window and takes the key with it
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
eq("answer: moving on releases the key", code_map(), nil)

-- the window closed by any other means releases it too
FAKE.input = nil
FAKE.text = "Another answer."
K.at(4)
pipeline.run "explain"
K.idle()
ok("answer: bound again for the next answer", code_map() ~= nil)
float.close()
eq("answer: closing the window releases the key", code_map(), nil)

-- a cached answer is shown the same way
K.at(4)
pipeline.run "explain"
K.idle()
ok("cache: an answer from the cache can be followed up too", code_map() ~= nil)
float.close()

-- ── a proposal that uses the same key ───────────────────────────────────────
FAKE.text = "```go\n// One returns one.\nfunc One() int {\n\treturn 1\n}\n```"
K.at(3)
pipeline.run "docs"
K.idle()
eq("proposal: a pending proposal owns the key", code_map() and code_map().desc, "Agent refine proposal")
FAKE.text = "It returns one, again."
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
FAKE.input = "second?"
pipeline.run "explain"
K.idle()
eq("proposal: an answer on top borrows the key", code_map() and code_map().desc, "Agent ask more")
float.close()
eq("proposal: and gives it back when it goes", code_map() and code_map().desc, "Agent refine proposal")
replace.reject()
eq("proposal: rejecting the proposal frees the key", code_map(), nil)

-- the proposal ending while an answer is on screen must not take the answer's key
FAKE.input = nil
FAKE.text = "```go\n// One again.\nfunc One() int {\n\treturn 1\n}\n```"
K.at(3)
pipeline.run "docs"
K.idle()
FAKE.text = "Answer over a proposal."
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
pipeline.run "explain"
K.idle()
replace.reject()
eq(
  "proposal: rejecting it while an answer is open keeps the answer's key",
  code_map() and code_map().desc,
  "Agent ask more"
)
float.close()
eq("proposal: and nothing is left behind", code_map(), nil)

-- ── Esc closes the answer from the code ─────────────────────────────────────
local function esc()
  local map = vim.fn.maparg("<Esc>", "n", false, true)
  map.callback()
end
FAKE.input, FAKE.text = nil, "A finished answer."
K.at(3)
pipeline.run "explain"
K.idle()
ok("esc: an answer is on screen", float.is_open())
esc()
ok("esc: Esc closes it from the code (the cursor never left)", not float.is_open())
eq("esc: and its follow-up key goes with it", code_map(), nil)
ok("esc: the cursor is still in the code", vim.api.nvim_get_current_buf() == buf)
esc() -- nothing to dismiss: the usual Esc, no error
ok("esc: with no answer it is the usual Esc", not float.is_open())

-- still being written: Esc stops the call too, and the window does not come back
require("core.settings").agent.cache.enabled = false -- the same function was explained above: a hit would never run
FAKE.slow, FAKE.text = true, "A long answer that is still being written when you press Esc."
K.at(4)
pipeline.run "explain"
K.wait(function()
  return float.is_open()
end)
ok("esc: streaming shows the window", float.is_open())
eq("esc: and the job is running", #require("agent.jobs").running(), 1)
esc()
ok("esc: Esc closes it", not float.is_open())
eq("esc: and stops the call", #require("agent.jobs").running(), 0)
vim.wait(300)
ok("esc: nothing reopens it", not float.is_open())
FAKE.slow = nil
require("core.settings").agent.cache.enabled = true

K.finish()
