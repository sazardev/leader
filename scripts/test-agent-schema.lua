-- Schema-constrained output through the whole road against a fake server that behaves like one that constrains decoding
-- (scripts/fake-llm.py): the request carries the schema, the server answers only JSON, the runner turns it back into the
-- protocol's text and the presenters never know. Nothing touches the network beyond 127.0.0.1.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

if vim.fn.executable "python3" ~= 1 then
  K.print "skip (no python3)"
  return K.finish()
end

local settings = require("core.settings").agent
local port = 18436
local server = vim.system { "python3", "-I", ROOT .. "/scripts/fake-llm.py", tostring(port) }
local up = vim.wait(4000, function()
  return vim.system({ "curl", "-s", "--max-time", "1", ("127.0.0.1:%d/api/version"):format(port) }):wait().code == 0
end, 150)
ok("the fake server starts", up)
local function last()
  return vim.json.decode(
    vim.system({ "curl", "-s", ("127.0.0.1:%d/__last"):format(port) }, { text = true }):wait().stdout
  )
end

K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["a.go"] = { "package p", "", "func Add(a, b int) int {", "\treturn a + b + 0", "}" },
}
K.fake() -- isolation only: the backends below are the real ones
settings.verify.command = false
settings.ollama.host = "127.0.0.1:" .. port
settings.openai.base_url = ("http://127.0.0.1:%d/v1"):format(port)
local replace = require "agent.output.replace"
local pipeline = require "agent.pipeline"
local actions = require "agent.actions"
local selection = require "agent.selection"
local buf = K.open "a.go"

local function launch(action_name, sel)
  K.at(4)
  local target = require("agent.context.target").resolve(buf, actions.get(action_name).scope, nil)
  return pipeline.launch {
    action = actions.get(action_name),
    target = target,
    selection = sel,
    input = action_name == "refactor" and "drop the + 0" or nil,
  }
end

-- ── Ollama, a 7b model: small profile, schema on ─────────────────────────────
local sel = { backend = "ollama", model = "qwen2.5-coder:7b", tier = "main" }
local job = launch("refactor", sel)
K.idle()
eq("ollama: the job is small", job.profile.name, "small")
local body = last().body
ok("ollama: the request carries the schema", type(body.format) == "table" and body.format.required[1] == "code")
ok(
  "ollama: and the format override in the system prompt",
  body.messages[1].content:find("FORMAT OVERRIDE", 1, true) ~= nil
)
eq(
  "ollama: the server answered only JSON, the proposal is code",
  job.proposal and job.proposal.lines,
  { "func Add(a, b int) int {", "\treturn a + b", "}" }
)
eq("ollama: usage still comes through", job.result.usage.tokens_in, 321)
eq("ollama: one call, no repair", job.spent.calls, 1)
replace.discard_all()

-- the same model with the profile off: no schema, the plain protocol
settings.capability.enabled = false
launch("refactor", sel)
K.idle()
body = last().body
eq(
  "ollama: without a profile nothing is constrained",
  { body.format, body.messages[1].content:find("FORMAT OVERRIDE", 1, true) },
  { nil, nil }
)
settings.capability.enabled = true
replace.discard_all()

-- findings through a schema
job = launch("review", sel)
K.idle()
ok("ollama review: the request carries the findings schema", last().body.format.required[1] == "findings")
local found = vim.diagnostic.get(buf, { namespace = require("agent.output.findings").namespace() })
-- the fake server answers L2 and L3 whatever the code; the function starts at line 3, so L2 is clamped into it
eq(
  "ollama review: the findings land inside the function",
  vim.tbl_map(function(d)
    return d.lnum + 1
  end, found),
  { 3, 3 }
)
require("agent.output.findings").clear(buf)

-- a strong class never asks the server to constrain
settings.capability.models["ollama/qwen2.5-coder:7b"] = "strong"
launch("refactor", sel)
K.idle()
eq("a strong class asks for no schema", last().body.format, nil)
settings.capability.models["ollama/qwen2.5-coder:7b"] = nil
replace.discard_all()

-- ── OpenAI-compatible ────────────────────────────────────────────────────────
settings.capability.models["openai/fake-small"] = "small"
job = launch("refactor", { backend = "openai", model = "fake-small", tier = "main" })
K.idle()
local rf = last().body.response_format
ok("openai: the request carries response_format", rf and rf.type == "json_schema" and rf.json_schema.strict == true)
eq("openai: the proposal is code", job.proposal and job.proposal.lines[2], "\treturn a + b")
replace.discard_all()

-- ── a server that ignores the schema still works ─────────────────────────────
-- (an older Ollama, or a proxy that drops unknown fields: the plain text comes back and is read as before)
local schema = require "agent.schema"
eq("plain text through the wrapper is untouched", schema.to_protocol("code", "```go\nx\n```"), "```go\nx\n```")

server:kill(15)
K.finish()
