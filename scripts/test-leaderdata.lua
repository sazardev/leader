-- `.leader/` (nvim/lua/agent/leaderdata): what is recorded about how Leader worked on a project, and, above all, what is NOT: no code,
-- prompts, answers, file names, document or error text, ever, and nothing leaves the machine. Hermetic: temp projects, a fake model.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-leaderdata.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name)
    print("  got:  " .. vim.inspect(got))
    print("  want: " .. vim.inspect(want))
  end
end
local function ok(name, cond)
  eq(name, cond and true or false, true)
end

package.loaded["utils.log"] = {
  info = function() end,
  warn = function() end,
  error = function() end,
}
package.loaded["agent.selection"] = {
  current = function()
    return { backend = "fake", model = "m" }
  end,
  label = function()
    return "fake/m"
  end,
}

local schema = require "agent.leaderdata.schema"
local redact = require "agent.leaderdata.redact"
local store = require "agent.leaderdata.store"
local report = require "agent.leaderdata.report"
local leader = require "agent.leaderdata"

local base = vim.fn.tempname()
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text or "")
  f:close()
end
local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return text
end

-- ── the schema lets through numbers and words it knows, nothing else ─────────
local clean = schema.sanitize("build.finish", {
  build = "0a1b2c3d",
  scope = "domain",
  outcome = "done",
  files = 12,
  cost = 0.123456789,
  fix_rounds = "two", -- wrong type
  secret_note = "my password is hunter2", -- not a field
  project_name = "acme-billing", -- not a field
  tier_files = "sonnet-4", -- not an allowed word
})
eq(
  "schema: known fields, cleaned",
  { clean.build, clean.scope, clean.outcome, clean.files, clean.cost },
  { "0a1b2c3d", "domain", "done", 12, 0.12346 }
)
eq("schema: a wrong type is dropped", clean.fix_rounds, nil)
eq("schema: a field it does not name is dropped", { clean.secret_note, clean.project_name }, { nil, nil })
eq("schema: a word that is not allowed becomes `other`", clean.tier_files, "other")
eq("schema: an unknown kind is nothing", schema.sanitize("build.secret", { a = 1 }), nil)
eq("schema: an id is 8 hex digits, never a name", {
  schema.sanitize("agent.decision", { run = "acme-billing" }).run,
  schema.sanitize("agent.decision", { run = "0a1b2c3d" }).run,
}, { nil, "0a1b2c3d" })
eq("schema: a model has no spaces or code", {
  schema.sanitize("agent.run", { model = "claude/haiku" }).model,
  schema.sanitize("agent.run", { model = "rm -rf /; x" }).model,
}, { "claude/haiku", nil })
eq("schema: a long model name is dropped", schema.sanitize("agent.run", { model = string.rep("a", 80) }).model, nil)
eq(
  "schema: NaN and infinity are not numbers",
  { schema.sanitize("build.finish", { cost = 0 / 0 }).cost, schema.sanitize("build.finish", { cost = math.huge }).cost },
  { nil, nil }
)
local listed = schema.sanitize("build.finish", {
  checks = {
    { label = "flutter analyze", ok = true },
    { label = "npm run deploy-to-prod-secret", ok = false },
    { label = "pnpm run test", ok = true },
    "not a record",
  },
  per_file = { { id = "deadbeef", ext = "dart", lines = "<200", path = "lib/secret.dart", model = "claude/haiku" } },
})
eq(
  "schema: a project's own script is `custom`",
  vim.tbl_map(function(c)
    return c.label
  end, listed.checks),
  { "flutter analyze", "custom", "pnpm run test" }
)
eq(
  "schema: a record keeps only its fields",
  listed.per_file,
  { { id = "deadbeef", ext = "dart", lines = "<200", model = "claude/haiku" } }
)
eq("schema: lists are capped", #schema.sanitize("build.finish", {
  per_file = (function()
    local t = {}
    for i = 1, 100 do
      t[i] = { ext = "go" }
    end
    return t
  end)(),
}).per_file, 60)
ok("schema: the README list names every kind", #schema.describe() == 3)

-- ── redaction ────────────────────────────────────────────────────────────────
eq("hash: stable with the same salt", redact.hash("s", "lib/a.dart"), redact.hash("s", "lib/a.dart"))
ok("hash: another salt, another hash", redact.hash("s", "lib/a.dart") ~= redact.hash("t", "lib/a.dart"))
ok("hash: 8 hex digits, no trace of the path", redact.hash("s", "lib/secret.dart"):match "^%x%x%x%x%x%x%x%x$")
eq(
  "buckets",
  { redact.bucket(10), redact.bucket(50), redact.bucket(300), redact.bucket(900), redact.bucket(nil) },
  { "<50", "<200", "<500", "500+", "<50" }
)
eq("ext", { redact.ext "lib/Main.DART", redact.ext "Makefile" }, { "dart", "" })
eq("lang", { redact.lang "typescriptreact", redact.lang "python", redact.lang "brainfuck" }, { "ts", "py", "other" })

ok("redact: a model of a shipped backend is kept", redact.model_label "claude/haiku" == "claude/haiku")
eq(
  "redact: a custom backend's model is not recorded",
  { redact.model_label "acme-internal/llm", redact.model_label "haiku", redact.model_label(nil) },
  { nil, nil, nil }
)
eq(
  "redact: which backends are Leader's",
  { redact.known_backend "ollama", redact.known_backend "hermes", redact.known_backend(nil) },
  { true, false, false }
)

-- ── the folder ───────────────────────────────────────────────────────────────
local proj = base .. "/p1"
vim.fn.mkdir(proj, "p")
ok("a project has no folder until something is recorded", not store.exists(proj))
local dir, salt = store.ensure(proj)
ok("ensure: the folder", store.exists(proj) and dir == proj .. "/.leader")
ok("ensure: gitignore ignores everything", read(dir .. "/.gitignore") == "*\n")
ok("ensure: a random salt that stays", #salt == 32 and select(2, store.ensure(proj)) == salt)
local readme = read(dir .. "/README.md")
ok("readme: says nothing leaves the machine", readme:find("Nothing here is ever sent anywhere", 1, true))
ok(
  "readme: lists what is never recorded",
  readme:find("Your code, your documents", 1, true) and readme:find("file or folder names", 1, true)
)
ok(
  "readme: lists the recorded fields from the schema",
  readme:find("`build.finish`: ", 1, true) and readme:find("`agent.run`: ", 1, true)
)
ok(
  "readme: says how to switch off and delete",
  readme:find("LEADER_NO_DATA=1", 1, true) and readme:find("remove this folder", 1, true)
)
ok("readme: says the salt is not to be shared", readme:find("Do not share it", 1, true))

ok(
  "record: an event is written",
  leader.record(proj, "build.finish", { build = "0a1b2c3d", outcome = "done", files = 3 })
)
local events = store.read(proj)
eq(
  "record: read back with its kind and version",
  { events[1].kind, events[1].v, events[1].files, events[1].ts ~= nil },
  { "build.finish", 1, 3, true }
)
eq(
  "record: a field the schema does not know never reaches the disk",
  (function()
    leader.record(proj, "build.finish", { build = "0a1b2c3d", my_source_code = "func secret() {}" })
    return (read(dir .. "/events.jsonl") or ""):find("secret", 1, true)
  end)(),
  nil
)
eq(
  "record: an unknown kind writes nothing",
  (function()
    local before = #store.read(proj)
    leader.record(proj, "something.else", { a = 1 })
    return #store.read(proj) - before
  end)(),
  0
)

-- the cap
local proj2 = base .. "/p2"
vim.fn.mkdir(proj2, "p")
require("core.settings").agent.leader_data.max_kb = 1
for i = 1, 60 do
  leader.record(proj2, "build.finish", { build = "0a1b2c3d", files = i, cost = 0.1 })
end
local kept = store.read(proj2)
ok(
  "cap: the file stays small and the newest events stay",
  (vim.uv.fs_stat(proj2 .. "/.leader/events.jsonl").size < 2048) and kept[#kept].files == 60 and #kept < 60
)
require("core.settings").agent.leader_data.max_kb = 2048

-- off
local proj3 = base .. "/p3"
vim.fn.mkdir(proj3, "p")
require("core.settings").agent.leader_data.enabled = false
eq(
  "off: nothing is recorded and no folder appears",
  { leader.record(proj3, "build.finish", { files = 1 }), store.exists(proj3) },
  { false, false }
)
require("core.settings").agent.leader_data.enabled = true
vim.env.LEADER_NO_DATA = "1"
eq(
  "env: LEADER_NO_DATA switches it off",
  { leader.record(proj3, "build.finish", { files = 1 }), store.exists(proj3) },
  { false, false }
)
vim.env.LEADER_NO_DATA = nil

-- ── no network, ever ─────────────────────────────────────────────────────────
local offline = true
for _, file in ipairs(vim.fn.glob(root .. "/nvim/lua/agent/leaderdata/*.lua", false, true)) do
  local text = read(file) or ""
  -- (the README text and comments may say these words; the code may not call them)
  local code = text:gsub("%-%-[^\n]*", ""):gsub('"[^"\n]*"', '""')
  for _, banned in ipairs {
    "curl",
    "vim.system",
    "jobstart",
    "new_tcp",
    "new_udp",
    "socket",
    "http",
    "wget",
    "fetch",
    "require%s*%(?%s*[\"']agent%.backends",
  } do
    if code:find(banned) then
      offline = false
      print("  network-ish call in " .. file .. ": " .. banned)
    end
  end
end
ok("offline: no module of the folder touches the network or a process", offline)

-- ── the report ───────────────────────────────────────────────────────────────
local lines = report.render({}, "x")
ok("report: empty says so, and where things stay", table.concat(lines, "\n"):find("Nothing recorded yet", 1, true))
local rep = table.concat(
  report.render({
    {
      kind = "build.finish",
      ts = 1790000000,
      outcome = "done",
      cost = 0.4,
      seconds = 100,
      fix_rounds = 0,
      req_total = 4,
      req_proven = 4,
      placeholders = 0,
      checks = { { label = "flutter analyze", ok = true }, { label = "flutter test", ok = true } },
      per_file = {
        { ext = "dart", state = "done", tokens_in = 1000, tokens_out = 200, cost = 0.01, model = "claude/sonnet" },
      },
    },
    {
      kind = "build.finish",
      ts = 1790100000,
      outcome = "partial",
      cost = 0.6,
      seconds = 200,
      fix_rounds = 2,
      req_total = 4,
      req_proven = 1,
      placeholders = 3,
      regressions = 1,
      checks = { { label = "flutter analyze", ok = false }, { label = "flutter test", ok = true } },
      per_file = {
        { ext = "dart", state = "failed", tokens_in = 3000, tokens_out = 600, cost = 0.03, model = "claude/sonnet" },
      },
    },
    { kind = "agent.run", action = "fix", outcome = "done", cost = 0.001, calls = 2 },
    { kind = "agent.run", action = "fix", outcome = "error", cost = 0, calls = 1 },
    { kind = "agent.decision", action = "fix", decision = "accepted" },
    { kind = "agent.decision", action = "fix", decision = "rejected" },
  }, "acme"),
  "\n"
)
ok(
  "report: builds and outcomes",
  rep:find("2 builds: 1 done, 1 partial", 1, true) or rep:find("2 builds: 1 partial, 1 done", 1, true)
)
ok(
  "report: cost and fix rounds",
  rep:find("$1.00 in total, $0.50 a build", 1, true)
    and rep:find("50% needed fix rounds (2.0 on average when they did)", 1, true)
)
ok(
  "report: requirements with a test",
  rep:find("requirements with a test: 62%", 1, true) or rep:find("requirements with a test: 63%", 1, true)
)
ok(
  "report: what fails, ranked",
  rep:find("`flutter analyze` failed in 1 of 2 builds", 1, true) and not rep:find("`flutter test` failed", 1, true)
)
ok(
  "report: files by kind and models",
  rep:find("`.dart`: 2 files · 1 failed", 1, true) and rep:find("`claude/sonnet`: 2 files · 50% failed", 1, true)
)
ok(
  "report: agent actions with accept rate",
  rep:find("`fix`: 2 runs · 50% errors · 50% accepted of 2 decided", 1, true)
)
ok("report: says where it is and how to clear it", rep:find("Delete it to clear everything", 1, true))

-- ── a whole build over a project full of secrets leaves none of them ─────────
local proot = base .. "/acme-billing"
write(proot .. "/AGENTS.md", "# AGENTS.md: acme-billing\n\n## Read first\n\n- [SPEC.md](SPEC.md): x.\n\n## Commands\n")
write(proot .. "/STACK.md", "# STACK\nCANARY_STACK_TEXT\n")
write(proot .. "/DESIGN.md", "# DESIGN\nCANARY_DESIGN_TEXT\n")
write(
  proot .. "/SPEC.md",
  "# SPEC\n\n## Goals\n\n- G1: CANARY_SPEC_GOAL (FR-1 to FR-2).\n\n## Requirements\n\n### FR-1: Invoice customers\n\n### FR-2: Refund CANARY_REFUND\n"
)
write(
  proot .. "/lib/canary_existing_module.dart",
  "abstract class CanaryExistingPort {\n  void canaryExistingMethod();\n}\n"
)
vim.system({ "git", "init", "-q" }, { cwd = proot }):wait()
package.loaded["agent"] = {
  complete = function(r, cb)
    if r.action == "kit_build_plan" then
      return cb(
        true,
        vim.json.encode {
          name = "acme-billing",
          summary = "CANARY_PLAN_SUMMARY",
          decisions = { "CANARY_DECISION" },
          risks = { { req = "FR-2", why = "CANARY_RISK" } },
          files = {
            {
              path = "lib/canary_secret_module.dart",
              purpose = "CANARY_PURPOSE",
              verifies = "FR-1",
              docs = { "spec" },
            },
            { path = "lib/features/billing/canary_invoice_page.dart", purpose = "CANARY_PURPOSE_2", docs = { "spec" } },
          },
        },
        { tokens_in = 10, tokens_out = 5 }
      )
    end
    cb(true, "class CanaryCode {} // CANARY_CODE_BODY\n", { tokens_in = 30, tokens_out = 20, cost = 0.002 })
  end,
}
local build = require "agent.kit.build"
local state = require "agent.kit.build.state"
vim.cmd.edit(vim.fn.fnameescape(proot .. "/SPEC.md"))
vim.cmd.cd(proot)
build.open()
build.go()
vim.wait(1600)
build.go()
vim.wait(3000, function()
  return state.run.phase == "done"
end)
eq("whole build: it finishes", state.run.phase, "done")
ok("whole build: it left a .leader folder", store.exists(proot))
local built = store.read(proot)
local finish
for _, e in ipairs(built) do
  if e.kind == "build.finish" then
    finish = e
  end
end
ok(
  "whole build: a build.finish event with its numbers",
  finish and finish.files == 2 and finish.outcome == "partial" and finish.req_total == 2 and finish.requests ~= nil
)
ok(
  "whole build: a hash per file, with its kind and size bucket",
  finish
    and #finish.per_file == 2
    and finish.per_file[1].id:match "^%x%x%x%x%x%x%x%x$"
    and finish.per_file[1].ext == "dart"
    and finish.per_file[1].lines == "<50"
)
ok("whole build: the plan's counts", finish and finish.risks == 1 and finish.existing >= 1)
local leaked = {}
for _, file in ipairs(vim.fn.glob(proot .. "/.leader/*", false, true)) do
  local text = read(file) or ""
  for _, canary in ipairs {
    "CANARY",
    "canary",
    "acme",
    "billing",
    "Invoice",
    "Refund",
    "invoice",
    "refund",
    "FR-1",
    "FR-2",
    "lib/",
    "features",
    ".dart:",
    proot,
  } do
    -- the README may name the fields and explain the rules; only events and the salt are checked for content
    if not file:match "README%.md$" and text:find(canary, 1, true) then
      leaked[#leaked + 1] = vim.fs.basename(file) .. " has " .. canary
    end
  end
end
eq("whole build: not one canary of the project's code, names or documents is in the folder", leaked, {})

-- ── the inline agent writes only where the folder exists ─────────────────────
local events_bus = require "agent.events"
leader.setup()
local function fake_job(id)
  return {
    id = id,
    record_id = "run-" .. id,
    t0 = vim.uv.hrtime(),
    action = { name = "fix" },
    selection = { backend = "claude", model = "haiku", tier = "light" },
    profile = { name = "medium" },
    result = { usage = { tokens_in = 100, tokens_out = 20, cost = 0.001 } },
    target = { lang = "go", lines = { "func CanarySecret() {}" } },
  }
end
local bare = base .. "/bare"
vim.fn.mkdir(bare, "p")
vim.system({ "git", "init", "-q" }, { cwd = bare }):wait()
vim.cmd.cd(bare)
events_bus.emit("job.settled", { job = fake_job(1), outcome = "done" })
ok("inline: a project with no folder is not given one by an action", not store.exists(bare))
vim.cmd.cd(proot)
local before = #store.read(proot)
local job = fake_job(2)
events_bus.emit("job.settled", { job = job, outcome = "done" })
events_bus.emit("proposal.accepted", { job = job, buf = 0, first = 1, last = 1, lines = {} })
events_bus.emit("proposal.dropped", { job = fake_job(3), how = "rejected" })
local after = store.read(proot)
local run_event, decisions = nil, {}
for i = before + 1, #after do
  if after[i].kind == "agent.run" then
    run_event = after[i]
  elseif after[i].kind == "agent.decision" then
    decisions[#decisions + 1] = after[i].decision
  end
end
ok(
  "inline: where the folder exists the run is recorded",
  run_event
    and run_event.action == "fix"
    and run_event.backend == "claude"
    and run_event.model == "haiku"
    and run_event.profile == "medium"
    and run_event.lang == "go"
    and run_event.tokens_in == 100
)
eq("inline: and the decisions about its proposals", decisions, { "accepted", "rejected" })
local custom_job = fake_job(4)
custom_job.selection = { backend = "acme-internal", model = "llm-v3", tier = "main" }
local n_before = #store.read(proot)
events_bus.emit("job.settled", { job = custom_job, outcome = "done" })
local custom_event = store.read(proot)[n_before + 1]
ok(
  "inline: a custom backend is `other` and its model is not recorded",
  custom_event
    and custom_event.backend == "other"
    and custom_event.model == nil
    and not vim.json.encode(custom_event):find("acme", 1, true)
)
ok("inline: nothing of the target's code is in the event", not vim.json.encode(run_event):find("Canary", 1, true))

print(fails == 0 and ("\nALL OK (" .. total .. " checks)") or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
