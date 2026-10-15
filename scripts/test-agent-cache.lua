-- Tests of the agent's answer cache: the pure core (key, eligibility, pruning), the file, and the whole flow with a fake
-- model: a repeated question is answered from disk with 0 tokens, any change misses, `replace` is never cached.
-- Hermetic: no network or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local core = require "agent.cache.core"
local cache = require "agent.cache"
local settings = require("core.settings").agent

-- ── core (pure) ─────────────────────────────────────────────────────────────
local base = { backend = "claude", model = "sonnet", effort = "low", system = "S", prompt = "P" }
local function with(field, value)
  return core.key(vim.tbl_extend("force", base, { [field] = value }))
end
eq("key: deterministic", core.key(base), core.key(vim.deepcopy(base)))
for _, f in ipairs { "backend", "model", "effort", "system", "prompt" } do
  ok("key: changes with the " .. f, with(f, "other") ~= core.key(base))
end
ok(
  "key: fields cannot bleed into each other",
  core.key { system = "ab", prompt = "c" } ~= core.key { system = "a", prompt = "bc" }
)

local cfg = { enabled = true, outputs = { "text", "findings" } }
eq("eligible: text by default", core.eligible({ output = "text" }, cfg), true)
eq("eligible: findings by default", core.eligible({ output = "findings" }, cfg), true)
eq("eligible: replace is not", core.eligible({ output = "replace" }, cfg), false)
eq("eligible: an action can opt in", core.eligible({ output = "replace", cache = true }, cfg), true)
eq("eligible: an action can opt out", core.eligible({ output = "text", cache = false }, cfg), false)
eq(
  "eligible: disabled turns it all off",
  core.eligible({ output = "text" }, { enabled = false, outputs = { "text" } }),
  false
)
eq("storable: empty is not", core.storable("  \n", {}), false)
eq("storable: too long is not", core.storable(("x"):rep(11), { max_chars = 10 }), false)
eq("storable: an answer is", core.storable("ok", {}), true)

local DAY = 86400
local entries = {
  old = { text = "a", ts = 0, used = 0 },
  a = { text = "a", ts = 100 * DAY, used = 100 * DAY + 1 },
  b = { text = "b", ts = 100 * DAY, used = 100 * DAY + 2 },
  c = { text = "c", ts = 100 * DAY, used = 100 * DAY + 3 },
  broken = "nope",
}
eq("prune: returns how many it dropped", core.prune(entries, 101 * DAY, { ttl_days = 30, max_entries = 2 }), 3)
local kept = vim.tbl_keys(entries)
table.sort(kept)
eq("prune: expired, broken and least recently used go", kept, { "b", "c" })

-- ── prefix order: stable first, volatile last ───────────────────────────────
local context = require "agent.context"
local rank = {
  rules = 1,
  types = 2,
  diagnostics = 3,
  around = 3,
}
local arranged = context.arrange({
  { name = "rules", text = "r" },
  { name = "diagnostics", text = "d" },
  { name = "around", text = "a" },
  { name = "types", text = "t" },
}, function(name)
  return rank[name]
end)
eq(
  "arrange: stable first, volatile last, declared order within a level",
  vim.tbl_map(function(x)
    return x.name
  end, arranged),
  { "rules", "types", "diagnostics", "around" }
)
eq(
  "arrange: a provider without a stability sits in the middle",
  vim.tbl_map(
    function(x)
      return x.name
    end,
    context.arrange({ { name = "a" }, { name = "b" }, { name = "c" } }, function(n)
      return n == "b" and 1 or n == "c" and 3 or 2
    end)
  ),
  { "b", "a", "c" }
)
for _, name in ipairs {
  "rules",
  "testing",
  "contracts",
  "schema",
  "ports",
  "ddd",
  "types",
  "outline",
  "testfile",
  "callees",
  "around",
  "callers",
  "gitlog",
  "changes",
  "findings",
  "diagnostics",
  "subject",
} do
  ok(
    "every provider declares its stability: " .. name,
    ({ [1] = 1, [2] = 1, [3] = 1 })[require("agent.context.providers." .. name).stability] == 1
  )
end
ok(
  "rules are the most stable of all",
  require("agent.context.providers.rules").stability < require("agent.context.providers.diagnostics").stability
)

-- the same call on the same file shares its beginning: only the tail (the volatile part and the target) differs
local http = require "agent.backends.http"
http.unstick()
eq("sticky: the first call sets the window", http.sticky("m", 4096), 4096)
eq("sticky: a bigger one widens it", http.sticky("m", 8192), 8192)
eq("sticky: a smaller one keeps the wide one (no model reload)", http.sticky("m", 4096), 8192)
eq("sticky: models are independent", http.sticky("other", 4096), 4096)
http.unstick()

-- ── a project and a fake model ──────────────────────────────────────────────
K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["store.go"] = {
    "package p", -- 1
    "", -- 2
    "func Rename(title string) string {", -- 3
    "\treturn title", -- 4
    "}", -- 5
  },
}
local FAKE = K.fake()
local file = vim.fn.tempname() .. ".json"
cache.use(file)
local pipeline = require "agent.pipeline"
local buf = K.open "store.go"
local runs = require "agent.runs.store"

local function ask(name)
  K.at(3)
  pipeline.run(name)
  K.idle()
end

FAKE.text = "It returns the title."
ask "explain"
eq("flow: the first question reaches the model", FAKE.calls, 1)
ask "explain"
eq("flow: the same question is answered from the cache", FAKE.calls, 1)
eq("flow: and the hit is not a run: the history only has the real call", #runs.read(), 1)
eq("flow: the cache counted it", { cache.stats().hits, cache.stats().tokens }, { 1, 120 })

vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "\treturn title + title" })
ask "explain"
eq("flow: changed code is a different question", FAKE.calls, 2)

vim.api.nvim_buf_set_lines(buf, 3, 4, false, { "\treturn title" })
ask "explain"
eq("flow: going back to the earlier code hits again", FAKE.calls, 2)

FAKE.input = "why?"
ask "ask"
ask "ask"
eq("flow: an instruction is part of the question", FAKE.calls, 3)
FAKE.input = "and now?"
ask "ask"
eq("flow: another instruction misses", FAKE.calls, 4)
FAKE.input = nil

local before = FAKE.calls
local replacing = require("agent.actions").get "docs"
ok("flow: docs is a replace action (never cached)", replacing.output == "replace")
FAKE.text = "```go\n// Rename returns the title.\nfunc Rename(title string) string {\n\treturn title\n}\n```"
ask "docs"
pcall(require("agent.output.replace").reject)
ask "docs"
pcall(require("agent.output.replace").reject)
eq("flow: a replace action asks the model every time", FAKE.calls, before + 2)

-- ── persistence and clearing ────────────────────────────────────────────────
cache.flush()
ok("file: the answers are written to disk", vim.uv.fs_stat(file) ~= nil)
cache.use(file) -- forget the memory: it is read back from the file
ok("file: and read back", cache.size() >= 2)
ask "explain"
eq("file: a reloaded cache still hits", FAKE.calls, before + 2)

settings.cache.enabled = false
ask "explain"
eq("settings: disabled, it asks the model", FAKE.calls, before + 3)
settings.cache.enabled = true

ok("stats: the counters survive a reload", cache.stats().hits >= 2)
local saved = cache.stats().hits

-- <leader>aAk: the stats in a modal, and a button to clear
FAKE.asked, FAKE.answer = {}, "no"
require("agent").cache()
local shown = FAKE.asked[1] and table.concat(vim.tbl_map(tostring, FAKE.asked[1].lines), "\n") or ""
eq("menu: it opens the cache modal", FAKE.asked[1] and FAKE.asked[1].title, "Agent cache")
ok("menu: with what is kept", shown:find "answers? kept" ~= nil)
ok("menu: and what it saved", shown:find("answered " .. saved, 1, true) ~= nil and shown:find("saved", 1, true) ~= nil)
ok("menu: saying no clears nothing", cache.size() >= 2)
FAKE.answer = "yes"
require("agent").cache()
eq("menu: saying yes clears it", (cache.size()), 0)
eq("menu: and the counters stay (they are what it saved you)", cache.stats().hits, saved)
eq("clear: an empty cache has nothing to forget", cache.clear(), 0)
ask "explain"
eq("clear: the question reaches the model again", FAKE.calls, before + 4)

K.finish()
