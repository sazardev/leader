-- Capability profiles and what they do: classes, measured advice, the syntax check, schema-shaped output, the second try
-- with the reason, the cascade to the main model and the capability guard. Hermetic: no network or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local profiles = require "agent.profiles"
local syntax = require "agent.syntax"
local schema = require "agent.schema"
local settings = require("core.settings").agent

-- ── classes by name (pure) ───────────────────────────────────────────────────
eq("size: the biggest number before a b", profiles.size_b "qwen2.5-coder:7b", 7)
eq("size: decimals", profiles.size_b "llama3.2:3.5b", 3.5)
eq("size: a moe name takes the biggest", profiles.size_b "mixtral-8x22b", 22)
eq("size: none", profiles.size_b "gpt-oss", nil)
eq("by name: 7b local is small", profiles.by_name("ollama", "qwen2.5-coder:7b"), "small")
eq("by name: 32b local is medium", profiles.by_name("ollama", "qwen2.5-coder:32b"), "medium")
eq("by name: 70b local is strong", profiles.by_name("ollama", "llama3.1:70b"), "strong")
eq("by name: sonnet is strong", profiles.by_name("claude", "sonnet"), "strong")
eq("by name: haiku is medium", profiles.by_name("claude", "claude-haiku-5-5"), "medium")
eq("by name: an unknown local model is small", profiles.by_name("ollama", "mystery"), "small")
eq("by name: an unknown hosted one is medium", profiles.by_name("openai", "mystery"), "medium")
eq("by name: claude with no model is strong", profiles.by_name("claude", nil), "strong")

-- ── resolve (pure) ───────────────────────────────────────────────────────────
local cfg = { enabled = true, measured = true, models = {}, small = {}, medium = {}, strong = {} }
local small = profiles.resolve({ backend = "ollama", model = "q:7b" }, "fix", cfg, {})
eq("small: its limits", { small.name, small.max_target_lines, small.repairs, small.schema }, { "small", 60, 2, true })
local strong = profiles.resolve({ backend = "claude", model = "sonnet" }, "fix", cfg, {})
eq(
  "strong: no size limit, one repair, no schema",
  { strong.name, strong.max_target_lines, strong.repairs, strong.schema },
  { "strong", nil, 1, false }
)
cfg.small = { max_target_lines = 90 }
eq(
  "the class's settings override its defaults",
  profiles.resolve({ backend = "ollama", model = "q:7b" }, "fix", cfg, {}).max_target_lines,
  90
)
cfg.small = {}
cfg.models["ollama/q:7b"] = "medium"
eq(
  "the user's class wins over the name",
  profiles.resolve({ backend = "ollama", model = "q:7b" }, "fix", cfg, {}).name,
  "medium"
)
cfg.models["ollama/q:7b"] = { class = "small", repairs = 5 }
local custom = profiles.resolve({ backend = "ollama", model = "q:7b" }, "fix", cfg, {})
eq(
  "the user's table overrides single fields",
  { custom.name, custom.repairs, custom.max_target_lines },
  { "small", 5, 60 }
)
cfg.models = {}

-- ── from_results: what a measurement turns into ──────────────────────────────
local function g(action, model, pass1, cases)
  return { action = action, model = model, pass1 = pass1, cases = cases or 4, n = cases or 4 }
end
local measured = profiles.from_results {
  g("fix", "ollama/q:7b", 0.25),
  g("docs", "ollama/q:7b", 0.75),
  g("review", "ollama/q:7b", 1.0),
  g("refactor", "ollama/q:7b", 0.1, 2), -- two cases say nothing
  g("fix", "replay:golden", 1),
}
local m = measured["ollama/q:7b"]
ok("measured: replays are not a model", measured["replay:golden"] == nil)
eq("measured: fails below 40% is declined", m.declined.fix ~= nil and m.declined.fix:find("25%", 1, true) ~= nil, true)
eq("measured: shaky gets repairs", m.repairs.docs, 2)
eq("measured: solid gets nothing special", { m.repairs.review, m.declined.review }, { nil, nil })
eq("measured: too few cases say nothing", { m.repairs.refactor, m.declined.refactor }, { nil, nil })
eq("measured: the overall class (59% over every sample)", m.class, "medium")
local with = profiles.resolve({ backend = "ollama", model = "q:7b" }, "fix", cfg, measured)
ok("resolve: a declined action says why", with.declined ~= nil)
eq(
  "resolve: measured repairs per action",
  profiles.resolve({ backend = "ollama", model = "q:7b" }, "docs", cfg, measured).repairs,
  2
)
cfg.measured = false
eq(
  "resolve: measured off ignores it",
  profiles.resolve({ backend = "ollama", model = "q:7b" }, "fix", cfg, measured).declined,
  nil
)
cfg.measured = true

-- ── syntax ───────────────────────────────────────────────────────────────────
ok("go parser is installed here", syntax.lang "go" ~= nil)
eq("syntax: valid code has no errors", (syntax.errors("package p\n\nfunc A() int {\n\treturn 1\n}\n", "go")), 0)
ok("syntax: broken code has some", (syntax.errors("package p\n\nfunc A() int {\n\treturn (\n}\n", "go")) > 0)
local file = { "package p", "", "func A() int {", "\treturn 1", "}" }
eq(
  "after_replace: a good body adds nothing",
  syntax.after_replace(file, 3, 5, { "func A() int {", "\treturn 2", "}" }, "go").added,
  0
)
ok(
  "after_replace: a broken body adds errors",
  syntax.after_replace(file, 3, 5, { "func A() int {", "\treturn (", "}" }, "go").added > 0
)
eq(
  "after_replace: a file that already was broken is not blamed",
  syntax.after_replace({ "package p", "func (" }, 2, 2, { "func (" }, "go").added,
  0
)
eq("after_replace: no parser, no opinion", syntax.after_replace(file, 1, 1, { "x" }, "nosuchlang"), nil)

-- ── schema ───────────────────────────────────────────────────────────────────
eq(
  "schema kind",
  { schema.kind { output = "replace" }, schema.kind { output = "findings" }, schema.kind { output = "text" } },
  { "code", "findings", nil }
)
eq(
  "schema: code becomes a fenced block with its notes",
  schema.to_protocol("code", vim.json.encode { code = "x := 1\n", needs_import = "fmt", note = "assumed" }),
  "```\nx := 1\n```\nneeds-import: fmt\nnote: assumed"
)
eq(
  "schema: empty notes disappear",
  schema.to_protocol("code", vim.json.encode { code = "x := 1", needs_import = "", note = "" }),
  "```\nx := 1\n```"
)
eq(
  "schema: findings become protocol lines",
  schema.to_protocol(
    "findings",
    vim.json.encode { findings = { { line = 4, severity = "error", message = "bad\nthing" } } }
  ),
  "L4|error|bad thing"
)
eq("schema: no findings is OK", schema.to_protocol("findings", vim.json.encode { findings = {} }), "OK")
eq("schema: what is not JSON passes through", schema.to_protocol("code", "```\nplain\n```"), "```\nplain\n```")
local protocol = require "agent.protocol"
eq(
  "schema: the converted text is what the protocol reads",
  (protocol.extract_code(schema.to_protocol("code", vim.json.encode { code = "a\nb", needs_import = "", note = "" }))),
  { "a", "b" }
)
eq(
  "schema: findings the protocol reads",
  #protocol.parse_findings(
    schema.to_protocol("findings", vim.json.encode { findings = { { line = 1, severity = "warn", message = "m" } } })
  ),
  1
)
local wrapped = schema.wrap({
  feed = function() end,
  finish = function()
    return { ok = true, text = vim.json.encode { code = "z", needs_import = "", note = "" } }
  end,
}, "code")
eq("schema: the wrapper streams nothing", wrapped.feed "{", nil)
eq("schema: and finishes with protocol text", wrapped.finish(0, "").text, "```\nz\n```")
for _, kind in ipairs { "code", "findings" } do
  local j = schema.json(kind)
  ok("schema: " .. kind .. " is a closed object", j.type == "object" and j.additionalProperties == false)
end

-- the local backends ask the server for it
local ollama = require "agent.backends.ollama"
local body = vim.json.decode(ollama.build({ system = "S", prompt = "P", model = "m", schema = "code" }).stdin)
ok("ollama: schema goes in `format`", type(body.format) == "table" and body.format.required[1] == "code")
ok("ollama: and the system prompt says so", body.messages[1].content:find("FORMAT OVERRIDE", 1, true) ~= nil)
eq(
  "ollama: the spec says it is shaped",
  ollama.build({ system = "S", prompt = "P", model = "m", schema = "code" }).schema,
  "code"
)
body = vim.json.decode(ollama.build({ system = "S", prompt = "P", model = "m" }).stdin)
eq("ollama: nothing asked, nothing changed", { body.format, body.messages[1].content }, { nil, "S" })
local openai = require "agent.backends.openai"
body = vim.json.decode(openai.build({ system = "S", prompt = "P", model = "m", schema = "findings" }).stdin)
ok(
  "openai: schema goes in `response_format`",
  body.response_format
    and body.response_format.type == "json_schema"
    and body.response_format.json_schema.strict == true
)

-- ── a project and a fake model ───────────────────────────────────────────────
K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["a.go"] = {
    "package p",
    "",
    "func One() int {",
    "\treturn 1",
    "}",
    "",
    "func Big() int {",
    "\ta := 1",
    "\ta++",
    "\ta++",
    "\treturn a",
    "}",
  },
}
local FAKE = K.fake()
settings.verify.command = false
local replace = require "agent.output.replace"
local pipeline = require "agent.pipeline"
local buf = K.open "a.go"
local function code(body_)
  return "```go\n" .. body_ .. "\n```"
end
local GOOD = code "func One() int {\n\treturn 10\n}"
local BROKEN = code "func One() int {\n\treturn (\n}"

settings.capability.models["fakeagent/default"] = "small"
FAKE.input = "return 10"
K.at(4)

-- a model that answers right: one call, no repair
FAKE.text = GOOD
pipeline.run "refactor"
K.idle()
local job = require("agent.jobs").last()
eq("a good answer takes one call", { FAKE.calls, job.attempt or 1 }, { 1, 1 })
eq("the job carries its profile", job.profile.name, "small")
replace.discard_all()

-- prose instead of a block: asked again with the reason, then right
FAKE.calls, FAKE.reqs = 0, {}
FAKE.text = function(req)
  return req.prompt:find("<previous-answer>", 1, true) and GOOD or "Sure! You should return ten."
end
pipeline.run "refactor"
K.idle()
job = require("agent.jobs").last()
eq("no code block: it asked twice", { FAKE.calls, job.attempt }, { 2, 2 })
ok("the second prompt says what was wrong", FAKE.reqs[2].prompt:find("no code block", 1, true) ~= nil)
ok("and shows the answer it is about", FAKE.reqs[2].prompt:find("Sure! You should", 1, true) ~= nil)
ok("and keeps the original task", FAKE.reqs[2].prompt:find("Instruction: return 10", 1, true) ~= nil)
eq("the proposal is the repaired one", job.proposal and job.proposal.lines[2], "\treturn 10")
eq("usage adds up across attempts", job.result.usage.tokens_in, 200)
eq("and says how many tries", job.result.usage.attempts, 2)
replace.discard_all()

-- code that does not parse: same road
FAKE.calls, FAKE.reqs = 0, {}
FAKE.text = function(req)
  return req.prompt:find("<previous-answer>", 1, true) and GOOD or BROKEN
end
pipeline.run "refactor"
K.idle()
eq("a syntax error is repaired too", FAKE.calls, 2)
ok("with the reason in the prompt", FAKE.reqs[2].prompt:find("does not parse", 1, true) ~= nil)
replace.discard_all()

-- repairs are bounded; what is left is shown as before
FAKE.calls, FAKE.reqs = 0, {}
FAKE.text = "I cannot do that."
pipeline.run "refactor"
K.idle()
eq("a hopeless model is asked 1 + repairs times and then gives up", FAKE.calls, 3)
replace.discard_all()

-- a strong model: one repair
settings.capability.models["fakeagent/default"] = "strong"
FAKE.calls = 0
FAKE.text = "No."
pipeline.run "refactor"
K.idle()
eq("strong: one repair", FAKE.calls, 2)
replace.discard_all()

-- turned off: no repairs at all
settings.capability.enabled = false
FAKE.calls = 0
pipeline.run "refactor"
K.idle()
eq("capability off: one call, whatever it said", FAKE.calls, 1)
settings.capability.enabled = true
replace.discard_all()

-- ── findings: the format is checked too ──────────────────────────────────────
settings.capability.models["fakeagent/default"] = "small"
FAKE.calls = 0
FAKE.text = function(req)
  return req.prompt:find("<previous-answer>", 1, true) and "L4|warn|returns a constant" or "this function returns one"
end
pipeline.run "review"
K.idle()
eq("review: prose is asked again for the format", FAKE.calls, 2)
eq(
  "review: and the findings land",
  #vim.diagnostic.get(buf, { namespace = require("agent.output.findings").namespace() }),
  1
)
require("agent.output.findings").clear(buf)

-- ── the capability guard ─────────────────────────────────────────────────────
settings.capability.small = { max_target_lines = 3 }
FAKE.calls = 0
FAKE.text = GOOD
K.at(4)
pipeline.run "refactor"
K.idle()
eq("a target within the limit runs", FAKE.calls, 1)
replace.discard_all()
FAKE.calls = 0
K.at(9)
FAKE.input = "rename"
pipeline.run "refactor"
K.idle()
eq("a target over the limit is not sent", FAKE.calls, 0)
ok(
  "and the note says what to do",
  K.note(FAKE):find("held to 3 lines", 1, true) ~= nil and K.note(FAKE):find("<leader>am", 1, true) ~= nil
)
settings.capability.small = {}

-- measured to fail: declined
local state_dir = vim.fn.tempname()
vim.fn.mkdir(state_dir, "p")
local saved_path = profiles.path
profiles.path = function()
  return state_dir .. "/profiles.json"
end
profiles.save {
  ["fakeagent/default"] = {
    class = "small",
    repairs = {},
    declined = { refactor = "passed 10% of the refactor cases (make eval)" },
  },
}
FAKE.calls = 0
K.at(4)
pipeline.run "refactor"
K.idle()
eq("an action measured to fail is declined", FAKE.calls, 0)
ok("and says what was measured", K.note(FAKE):find("passed 10%", 1, true) ~= nil)

-- ── the cascade ──────────────────────────────────────────────────────────────
local MAIN = { text = GOOD, calls = 0, reqs = {} }
require("agent.backends").register("fakemain", {
  name = "fakemain",
  label = "Main",
  available = function()
    return true
  end,
  models = function(cb)
    cb {}
  end,
  build = function(req)
    MAIN.calls = MAIN.calls + 1
    MAIN.reqs[#MAIN.reqs + 1] = req
    return { cmd = { "printf", "%s", MAIN.text }, cwd = "/tmp" }
  end,
  parser = function()
    local chunks = {}
    return {
      feed = function(c)
        chunks[#chunks + 1] = c
        return c
      end,
      finish = function(c)
        return c == 0
            and {
              ok = true,
              text = table.concat(chunks),
              usage = { tokens_in = 500, tokens_out = 50, cost = 0.01 },
            }
          or { ok = false, err = "boom" }
      end,
    }
  end,
})
settings.cascade.enabled = true
settings.cascade.to = "fakemain/big"

-- the eval said this model fails the action: the main one takes it from the start
FAKE.calls, MAIN.calls = 0, 0
pipeline.run "refactor"
K.idle()
eq("cascade: a declined action goes straight to the main model", { FAKE.calls, MAIN.calls }, { 0, 1 })
job = require("agent.jobs").last()
ok("cascade: and the job remembers", job.escalated and job.from == "fakeagent/default")
replace.discard_all()
profiles.path = function()
  return state_dir .. "/none.json"
end

-- unusable after its repairs: the main model
FAKE.calls, MAIN.calls = 0, 0
FAKE.text = "Nope."
pipeline.run "refactor"
K.idle()
eq("cascade: repairs spent, then the main model", { FAKE.calls, MAIN.calls }, { 3, 1 })
job = require("agent.jobs").last()
eq("cascade: the proposal is the main model's", job.proposal and job.proposal.lines[2], "\treturn 10")
eq("cascade: the bill has every attempt", job.result.usage.tokens_in, 3 * 100 + 500)
ok(
  "cascade: and it said so",
  (function()
    for _, n in ipairs(FAKE.notes) do
      if n:find("trying fakemain/big", 1, true) then
        return true
      end
    end
    return false
  end)()
)
replace.discard_all()

-- a model that fails outright (the server is down)
FAKE.calls, MAIN.calls = 0, 0
FAKE.text = function()
  error "unused"
end
local real_build = require("agent.backends").get("fakeagent").build
require("agent.backends").get("fakeagent").build = function(req)
  FAKE.calls = FAKE.calls + 1
  return { cmd = { "sh", "-c", "echo down >&2; exit 7" }, cwd = "/tmp" }
end
pipeline.run "refactor"
K.idle()
eq("cascade: a dead server hands the job to the main model", { FAKE.calls, MAIN.calls }, { 1, 1 })
require("agent.backends").get("fakeagent").build = real_build
replace.discard_all()

-- no cascade: a dead server fails the job
settings.cascade.enabled = false
MAIN.calls = 0
require("agent.backends").get("fakeagent").build = function()
  return { cmd = { "sh", "-c", "echo down >&2; exit 7" }, cwd = "/tmp" }
end
pipeline.run "refactor"
K.idle()
eq("no cascade: nothing else is asked", MAIN.calls, 0)
require("agent.backends").get("fakeagent").build = real_build
profiles.path = saved_path

K.finish()
