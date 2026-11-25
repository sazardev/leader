-- Optional OpenTUI chat bridge: snapshot, commands and scoped cancellation.
-- Hermetic: no model, network or real state.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(ROOT .. "/nvim")

local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print(("FAIL %s\n  got:  %s\n  want: %s"):format(name, vim.inspect(got), vim.inspect(want)))
  end
end

local function ok(name, cond, extra)
  eq(name .. (cond and "" or ("  " .. tostring(extra or ""))), cond and true or false, true)
end

local bridge = require "agent.chat.opentui"
local chat = require "agent.chat"
local window = require "agent.chat.window"
local session = require "agent.chat.session"
local store = require "agent.chat.store"
local calls = require "agent.calls"

bridge.FILE = vim.fn.tempname() .. ".json"
bridge.COMMANDS = vim.fn.tempname() .. ".commands.json"
bridge.reset()
window.session, window.home, window.running = nil, nil, false
window.pending_text, window.pending_think, window.sent_text = "", "", nil
window.queue = {}

local draft = bridge.snapshot()
eq("bridge: draft snapshot has the required session", draft.session.id, "draft")
eq("bridge: empty message list", #draft.messages, 0)

local s = chat.ensure_session { root = ROOT }
eq("headless: ensure creates no window", not window.is_open(), true)
session.add(s, { role = "user", text = "hola" })
session.add(s, { role = "assistant", text = "respuesta", usage = { tokens_in = 10, tokens_out = 2 } })
window.running, window.sent_text = true, "siguiente"
window.pending_text, window.pending_think = "parcial", "razonando"
local live = bridge.snapshot()
eq("bridge: live user is visible", live.messages[#live.messages - 1].text, "siguiente")
eq("bridge: live assistant streams", live.messages[#live.messages].text, "parcial")
eq("bridge: live thinking travels", live.messages[#live.messages].thinking, "razonando")
eq("bridge: persisted usage travels", live.messages[2].usage.tokens_in, 10)
eq("bridge: flush is atomic", bridge.flush(), true)
local decoded = vim.json.decode(table.concat(vim.fn.readfile(bridge.FILE), "\n"))
eq("bridge: file matches schema", decoded.version, 1)
eq("bridge: file carries the live turn", decoded.session.running, true)
local before = vim.uv.hrtime()
eq("bridge: unchanged snapshot skips serialization", bridge.flush(), true)
ok("bridge: unchanged snapshot is cheap", (vim.uv.hrtime() - before) / 1e6 < 20, (vim.uv.hrtime() - before) / 1e6)

window.running, window.sent_text = false, nil
window.pending_text, window.pending_think = "", ""

local sent
local real_send = chat.send
chat.send = function(text)
  sent = text
  return true
end
eq("bridge: send command", bridge.handle { version = 1, id = "c1", action = "send", text = "revisa esto" }, true)
eq("bridge: send reaches the same runtime", sent, "revisa esto")
eq(
  "bridge: duplicate id is idempotent",
  bridge.handle { version = 1, id = "c1", action = "send", text = "otra vez" },
  true
)
eq("bridge: duplicate did not send twice", sent, "revisa esto")
eq("bridge: accepted command is acknowledged", bridge.snapshot().ack.ok, true)
eq(
  "bridge: UI-only slash is rejected",
  bridge.handle { version = 1, id = "c2", action = "send", text = "/model" },
  false
)
eq("bridge: rejected command is acknowledged", bridge.snapshot().ack.ok, false)
eq(
  "bridge: duplicate rejection stays rejected",
  bridge.handle { version = 1, id = "c2", action = "send", text = "/model" },
  false
)
chat.send = real_send

local old = session.new { id = "chat-old", root = ROOT, title = "Old", backend = "fake", model = "m" }
session.add(old, { role = "user", text = "old" })
store.put(old)
eq(
  "bridge: select persisted session",
  bridge.handle { version = 1, id = "c3", action = "select_session", session_id = old.id },
  true
)
eq("bridge: selection changed the active session", window.session.id, old.id)
eq("bridge: profile command", bridge.handle { version = 1, id = "c4", action = "set_profile", value = "ask" }, true)
eq("bridge: profile reached the session", window.session.profile, "ask")

local first = chat.new_headless()
eq("headless: new keeps the panel closed", not window.is_open(), true)
eq("headless: new changes session", first.id ~= old.id, true)

-- Stopping chat cancels only its call, never an unrelated one-shot.
window.running, window.turn_id, window.turn_cancelled = true, "turn-test", false
local chat_call = calls.start { action = "chat", label = "chat", quiet = true }
local other_call = calls.start { action = "review", label = "review" }
window.active_call = chat_call
chat.stop()
eq("stop: chat call cancelled", chat_call.cancelled, true)
eq("stop: unrelated call survives", other_call.cancelled, nil)
eq("stop: runtime idle", window.running, false)
calls.finish(chat_call, false)
calls.finish(other_call, false)

-- A late callback from the stopped turn must not write into the transcript.
local before = #window.session.messages
local runner = require "agent.chat.runner"
local real_run = runner.run
local callback
runner.run = function(_, _, _, cb)
  callback = cb
  return nil, { id = 999 }
end
chat._launch(window.session, { backend = "fake" }, "ignored", "system", "prompt", {}, "ask", 0)
chat.stop()
callback(true, "must not land", nil, nil)
runner.run = real_run
eq("race: stopped turn cannot append late output", #window.session.messages, before)

-- Command file polling consumes one complete command.
local f = assert(io.open(bridge.COMMANDS .. ".tmp", "w"))
f:write(vim.json.encode { version = 1, id = "poll-1", action = "history" })
f:close()
os.rename(bridge.COMMANDS .. ".tmp", bridge.COMMANDS)
bridge.poll_once()
eq("bridge: command slot drained", vim.fn.filereadable(bridge.COMMANDS), 0)

bridge.reset()
os.remove(bridge.FILE)
os.remove(bridge.COMMANDS)
window.session, window.running = nil, false
print(("\n%d checks, %d failed"):format(total, fails))
if fails > 0 then
  vim.cmd "cq 1"
end
