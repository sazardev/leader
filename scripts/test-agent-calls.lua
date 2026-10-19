-- Tests of the one-shot calls registry (what the statusline shows while a document, commit draft or review is being
-- written): phases, label, outcome, cancel, and that oneshot reports to it. Hermetic: a fake model, no network or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok
local FAKE = K.fake()
local calls = require "agent.calls"

-- the registry alone
eq("calls: nothing running, nothing shown", calls.statusline(), "")
local call = calls.start({ action = "kit_screens" }, "fake/m")
ok("calls: the label comes from the action", calls.running()[1].label == "screens")
ok("calls: the badge is just the label", calls.statusline():find("screens", 1, true) ~= nil)
ok("calls: no seconds, no phase", not calls.statusline():find("%d+s") and not calls.statusline():find("·", 1, true))
eq("calls: the chip is blue while it runs", calls.statusline_group(), "AgentStatus")
calls.finish(call, true)
ok("calls: the outcome stays after it ends", calls.statusline():find("✓ screens", 1, true) ~= nil)
eq("calls: green when it worked", calls.statusline_group(), "AgentDone")
local failed = calls.start({ action = "x", label = "writing DESIGN.md" })
calls.finish(failed, false)
ok("calls: a failure says so", calls.statusline():find("✗ writing DESIGN.md", 1, true) ~= nil)
eq("calls: red when it failed", calls.statusline_group(), "DartgenFailed")
local quiet = calls.start({ action = "build_file", quiet = true })
eq("calls: a quiet call (the build has its own chip) is not shown", #calls.running(), 0)
calls.finish(quiet, true)

-- through oneshot: shown while the process runs, outcome after
FAKE.text, FAKE.slow = "## Screens\nhello", true
local answered
require("agent").complete({ action = "kit_screens", system = "s", prompt = "p" }, function(ok_, text)
  answered = { ok_, text }
end)
K.wait(function()
  return #calls.running() == 1
end, 4000)
ok("oneshot: a running request is on the statusline", calls.statusline():find("screens", 1, true) ~= nil)
eq("agent stop: kills it", require("agent.calls").cancel(), 1)
K.wait(function() -- the fake's `sleep` child keeps the pipe open until it ends
  return answered ~= nil
end, 12000)
eq("oneshot: a cancelled request answers cancelled", answered, { false, "cancelled" })
eq("oneshot: and nothing keeps spinning", #calls.running(), 0)

FAKE.slow = false
answered = nil
require("agent").complete({ action = "kit_screens", system = "s", prompt = "p" }, function(ok_, text)
  answered = { ok_, text }
end)
K.wait(function()
  return answered ~= nil
end, 4000)
eq("oneshot: a normal request answers", answered, { true, "## Screens\nhello" })
ok("oneshot: and leaves its outcome", calls.statusline():find("✓ screens", 1, true) ~= nil)

K.finish()
