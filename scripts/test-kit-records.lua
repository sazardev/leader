-- Tests of what the builds record and the 0-token coverage report (nvim/lua/agent/kit): the ADRs from a plan's decisions
-- (adr.lua: only new decisions, numbered, indexed, linked), PROGRESS.md (progress.lua: fixed sections, the Done log kept,
-- what is open, what is next), the coverage of SPEC/STACK/DESIGN by the code (coverage.lua), AGENTS.md links for both,
-- and a whole build with a fake model that leaves them behind. Hermetic: temp projects, no network or tokens.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-kit-records.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if not vim.deep_equal(got, want) then
    fails = fails + 1
    print("FAIL " .. name)
    print("  got:  " .. vim.inspect(got))
    print("  want: " .. vim.inspect(want))
  end
end
local function ok(name, cond)
  eq(name, cond and true or false, true)
end

local notes = {}
package.loaded["utils.log"] = {
  info = function(m)
    notes[#notes + 1] = "info: " .. m
  end,
  warn = function(m)
    notes[#notes + 1] = "warn: " .. m
  end,
  error = function(m)
    notes[#notes + 1] = "error: " .. m
  end,
}
package.loaded["agent.selection"] = {
  current = function()
    return { backend = "fake", model = "m" }
  end,
  label = function()
    return "fake/m"
  end,
}

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

local adr = require "agent.kit.adr"
local progress = require "agent.kit.progress"
local coverage = require "agent.kit.coverage"
local compose = require "agent.kit.compose"

-- ── ADRs ─────────────────────────────────────────────────────────────────────

eq(
  "adr slug: words, at most six",
  adr.slug "Riverpod for state, one Notifier per screen!",
  "riverpod-for-state-one-notifier-per"
)
eq("adr number: one after the highest", adr.next_number { "0001-a.md", "0007-b.md", "README.md" }, 8)
eq("adr number: the first", adr.next_number {}, 1)
local recorded = adr.recorded {
  "# 0001. X\n\n## Decision\n\n- Riverpod for state.\n- go_router for navigation\n\n## Consequences\n\n- y\n",
}
ok(
  "adr recorded: the decisions of earlier ADRs, compared loosely",
  recorded["riverpod for state"] and recorded["go router for navigation"]
)

local run = {
  root = "/tmp/x",
  name = "notes",
  scope = "domain",
  plan = {
    name = "notes",
    summary = "A notes domain.",
    architecture = "domain <- app",
    decisions = { "Riverpod for state", "Sealed failures per feature" },
  },
  files = {
    { path = "lib/domain/note.dart", state = "pending" },
    { path = "pubspec.yaml", state = "pending", existed = true },
    { path = "README.md", state = "skipped" },
  },
}
local entry = adr.entry(run, recorded, "2026-10-19")
eq("adr entry: only what no ADR records", entry.decisions, { "Sealed failures per feature" })
eq(
  "adr entry: created and changed files apart, skipped ones out",
  { entry.created, entry.changed },
  { { "lib/domain/note.dart" }, { "pubspec.yaml" } }
)
ok(
  "adr entry: the title says the build and its first new decision",
  entry.title == "Domain: Sealed failures per feature"
)
eq(
  "adr entry: nothing new = no ADR",
  adr.entry(run, adr.recorded { "## Decision\n- Riverpod for state\n- sealed failures per feature\n## X\n" }, "d"),
  nil
)
local text = adr.render(3, entry)
ok("adr render: numbered title", text:find "^# 0003%. Domain: Sealed failures per feature\n")
eq(
  "adr render: the four sections in order",
  vim.tbl_map(function(h)
    return h
  end, vim.iter(text:gmatch "\n## (%w+)"):totable()),
  adr.SECTIONS
)
ok("adr render: the decision listed and recorded next time", adr.recorded({ text })["sealed failures per feature"])
ok(
  "adr index: a row per ADR",
  adr.index({ { file = "0003-x.md", title = "T", date = "d" } }):find("| [0003](0003-x.md) | T | d |", 1, true)
)

-- ── decisions the next plans follow ──────────────────────────────────────────

eq(
  "supersedes: the ADR numbers a decision reverses",
  adr.supersedes { "Supersedes ADR 0002: Bloc instead of Riverpod", "x", "supersedes ADR 3 and ADR 0002" },
  { 2, 3 }
)
local files = {
  ["0001-a.md"] = "# 0001. Domain: Riverpod for state\n\n## Status\n\nAccepted · d\n\n## Decision\n\nArchitecture: domain <- ui\n\n- Riverpod for state\n\n## Consequences\n",
  ["0002-b.md"] = "# 0002. Feature: go_router\n\n## Decision\n\n- go_router for navigation\n\n## Consequences\n",
  ["0003-c.md"] = "# 0003. Design: Bloc\n\n## Decision\n\n- Supersedes ADR 0001: Bloc for state because of X\n\n## Consequences\n",
}
eq("superseded: the old one, by the file of the new one", adr.superseded(files), { [1] = "0003-c.md" })
local summary = adr.summary(files)
ok("summary: a block for the plan", summary:find "^<decisions>\n" and summary:find "</decisions>$")
ok(
  "summary: what is in force, with its architecture",
  summary:find("ADR 0002 · Feature: go_router\n  - go_router for navigation", 1, true)
    and summary:find("Supersedes ADR 0001", 1, true)
)
ok(
  "summary: not what was superseded",
  not summary:find("ADR 0001 ·", 1, true) and not summary:find("Riverpod for state", 1, true)
)
eq("summary: none = nothing", adr.summary {}, "")
adr.SUMMARY_MAX = 80
local cut = adr.summary(files)
ok("summary: the newest kept when they do not fit", cut:find("ADR 0003", 1, true) and not cut:find("ADR 0002", 1, true))
adr.SUMMARY_MAX = 4000
local superseding = adr.render(4, {
  title = "Design: Bloc",
  date = "2026-10-20",
  context = "c",
  decisions = { "Supersedes ADR 0001: Bloc for state" },
  created = {},
  changed = {},
})
ok(
  "render: a superseding ADR says it in its Status",
  superseding:find("## Status\n\nAccepted · 2026-10-20 · supersedes ADR 0001\n", 1, true)
)
local index = adr.index {
  { file = "0001-a.md", title = "A", date = "d", superseded = "0003-c.md" },
  { file = "0003-c.md", title = "C", date = "d" },
}
ok(
  "index: the old one points to the new one",
  index:find("| [0001](0001-a.md) | A | d | superseded by [0003](0003-c.md) |", 1, true)
    and index:find("| [0003](0003-c.md) | C | d | accepted |", 1, true)
)
local bplan = require "agent.kit.build.plan"
local with = bplan.request({ stack = "S" }, nil, nil, nil, summary)
ok(
  "plan: the decisions in the request and the rule to follow them",
  with.prompt:find("<decisions>", 1, true) and with.system:find("Supersedes ADR NNNN", 1, true)
)
local without = bplan.request { stack = "S" }
ok(
  "plan: no ADRs = no block, no rule",
  not without.prompt:find("<decisions>", 1, true) and not without.system:find("Supersedes ADR", 1, true)
)
ok(
  "plan: a layer keeps its scope rules with the decisions",
  bplan.request({ stack = "S", spec = "P" }, "domain", {}, nil, summary).system:find("ONLY the domain", 1, true)
)

-- ── PROGRESS.md ──────────────────────────────────────────────────────────────

local done_run = {
  root = "/tmp/x",
  name = "notes",
  scope = "feature",
  task = { id = "FR-2", title = "Export notes", text = "x" },
  phase = "done",
  outcome = "✓ built · 3 files · checks pass",
  totals = { cost = 0.042 },
  plan = { name = "notes", summary = "Export to Markdown." },
  files = { { path = "a", state = "done", purpose = "" }, { path = "b", state = "fixed", purpose = "" } },
  checks = {},
}
local facts =
  { date = "2026-10-19", questions = 2, next = { { id = "FR-3", title = "Share", tests = {} } }, keys = "<leader>aSbf" }
local p1 = progress.render(nil, done_run, facts)
eq("progress: the four sections in order", vim.iter(p1:gmatch "\n## (%w+)"):totable(), progress.SECTIONS)
ok("progress now: the build, how it ended", p1:find("- Last build: feature FR-2 · Export notes · ✓ built", 1, true))
ok(
  "progress done: a log line",
  p1:find("- 2026-10-19 · feature FR-2 · Export notes · ✓ built · 3 files · checks pass · $0.042", 1, true)
)
ok("progress open: SPEC.md's questions", p1:find("SPEC.md has 2 open questions", 1, true))
ok("progress next: what no test proves", p1:find("- FR-3 Share: no test proves it yet", 1, true))
ok("progress: a done run says nothing about resuming", not p1:find("To resume", 1, true))
local p2 = progress.render(p1, done_run, facts)
eq(
  "progress done: the same build again the same day replaces its line",
  select(2, p2:gsub("\n%- 2026%-10%-19 · feature FR%-2", "")),
  1
)
local stopped = vim.tbl_extend("force", done_run, {
  phase = "stopped",
  outcome = "■ stopped",
  task = { id = "FR-3", title = "Share", text = "x" },
  files = {
    { path = "c.dart", state = "failed", purpose = "share sheet" },
    { path = "d", state = "skipped", purpose = "" },
  },
  checks = { { label = "flutter analyze", state = "failed" } },
})
local p3 = progress.render(p2, stopped, facts)
ok("progress: the log of earlier builds is kept", p3:find("- 2026-10-19 · feature FR-2", 1, true))
ok("progress: a stopped build is not logged as done", not p3:find("- 2026-10-19 · feature FR-3", 1, true))
ok("progress now: how to resume", p3:find("To resume: <leader>aSbf", 1, true))
ok(
  "progress open: the unwritten file, the skipped one, the failing check",
  p3:find("`c.dart`: not written yet (share sheet)", 1, true)
    and p3:find("`d`: left out in the review", 1, true)
    and p3:find("the check `flutter analyze` fails", 1, true)
)
eq(
  "progress questions: the items of Open questions",
  progress.questions "# S\n\n## Open questions\n\n- Q1 a?\n- Q2 b?\n\n## Milestones\n",
  2
)

-- ── coverage ─────────────────────────────────────────────────────────────────

local spec = table.concat({
  "# SPEC.md: Notes",
  "",
  "## Summary",
  "",
  "Mentions FR-9 before the requirements.",
  "",
  "## Requirements",
  "",
  "### FR-1: Create a note",
  "",
  "The system must…",
  "",
  "- **FR-2** Export: The system must export.",
  "  - Given a note, when export, then a file",
  "**FR-10.** Search notes",
  "",
  "## Edge cases",
  "",
  "- (FR-2) empty note",
}, "\n")
local reqs = coverage.requirements(spec)
eq(
  "coverage requirements: every style, only in Requirements, with titles and lines",
  vim.tbl_map(function(r)
    return { r.id, r.title, r.line }
  end, reqs),
  { { "FR-1", "Create a note", 9 }, { "FR-2", "Export: The system must export.", 13 }, { "FR-10", "Search notes", 15 } }
)
coverage.cover(
  reqs,
  { ["test/a_test.dart"] = "// FR-1 creates\n", ["test/b_test.dart"] = "FR-100" },
  { { path = "test/c_test.dart", text = "FR-10 search" } }
)
eq(
  "coverage cover: a test that names it or a plan's verifies; FR-1 is not FR-10/FR-100",
  vim.tbl_map(function(r)
    return r.tests
  end, reqs),
  { { "test/a_test.dart" }, {}, { "test/c_test.dart" } }
)
local stack =
  "# S\n\n## Stack\n\n| Area | Choice |\n|---|---|\n| State | Riverpod (`flutter_riverpod`) |\n| Routing | `go_router` |\n| HTTP | `github.com/go-chi/chi/v5` |\n| Test | `flutter test` |\n\n## Project layout\n"
eq(
  "coverage tools: pub names the pubspec lacks (commands and present ones not)",
  coverage.missing_tools(stack, { ["pubspec.yaml"] = "dependencies:\n  flutter_riverpod: ^2.0.0\n" }),
  { { name = "go_router", manifest = "pubspec.yaml" } }
)
eq(
  "coverage tools: Go modules the go.mod lacks",
  coverage.missing_tools(stack, { ["go.mod"] = "module x\n" }),
  { { name = "github.com/go-chi/chi/v5", manifest = "go.mod" } }
)
local design =
  "# D\n\n## Color\n\n| Token | Light | Dark | Use |\n|---|---|---|---|\n| `surface` | #fff | #000 | x |\n| text-muted | #555 | #aaa | x |\n| primary | #00f | #0af | x |\n\nUse `--focus-ring`.\n\n## Typography\n"
eq(
  "coverage tokens: the Color table's first column and CSS variables",
  coverage.tokens(design),
  { "surface", "text-muted", "primary", "--focus-ring" }
)
eq(
  "coverage tokens: unused in every spelling (textMuted counts, --focus-ring as focus_ring counts)",
  coverage.unused_tokens(
    coverage.tokens(design),
    { ["lib/theme.dart"] = "final textMuted = 1; final focus_ring = 2; Color surface;" }
  ),
  { "primary" }
)
eq(
  "coverage folders: top-level and layout folders no document names",
  coverage.unmentioned({
    "lib/main.dart",
    "lib/features/notes/a.dart",
    "lib/legacy/b.dart",
    "tool/gen.dart",
    ".github/x.yml",
    "test/a_test.dart",
  }, "## Project layout\n\nlib/\n  features/   one folder per feature\n"),
  { "lib/legacy/", "tool/" }
)
local report = {
  requirements = reqs,
  tools = { { name = "go_router", manifest = "pubspec.yaml" } },
  tokens = { "primary" },
  folders = { "tool/" },
}
local lines, actions = coverage.render(report, "notes")
ok("coverage render: the count of tested requirements", vim.tbl_contains(lines, "## Requirements · 2/3 with a test"))
local feature_line
for i, l in ipairs(lines) do
  if l:find("○ FR-2", 1, true) then
    feature_line = i
  end
end
eq(
  "coverage render: ⏎ on an untested requirement builds it",
  actions[feature_line] and actions[feature_line].kind,
  "feature"
)
eq(
  "coverage uncovered: the ones with no test",
  vim.tbl_map(function(r)
    return r.id
  end, coverage.uncovered(report)),
  { "FR-2" }
)

-- ── AGENTS.md links ──────────────────────────────────────────────────────────

local agents = "# AGENTS.md: x\n\nIntro.\n\n## Read first\n\n- [STACK.md](STACK.md): the stack.\n\n## Commands\n"
local linked = compose.link_file(agents, "PROGRESS.md", "where the work stands")
ok(
  "link: added at the end of Read first",
  linked:find(
    "- [STACK.md](STACK.md): the stack.\n- [PROGRESS.md](PROGRESS.md): where the work stands.\n\n## Commands",
    1,
    true
  )
)
eq("link: never twice", compose.link_file(linked, "PROGRESS.md", "x"), nil)

-- ── a build leaves its records ───────────────────────────────────────────────

local proot = base .. "/notes"
write(proot .. "/AGENTS.md", "# AGENTS.md: notes\n\n## Read first\n\n- [SPEC.md](SPEC.md): x.\n\n## Commands\n")
write(proot .. "/STACK.md", "# STACK\n")
write(
  proot .. "/SPEC.md",
  "# SPEC\n\n## Requirements\n\n### FR-1: Create\n\n### FR-2: Export\n\n## Open questions\n\n- Q1 how?\n"
)
write(proot .. "/test/create_test.txt", "FR-1\n")
vim.system({ "git", "init", "-q" }, { cwd = proot }):wait()
local plans = {}
package.loaded["agent"] = {
  complete = function(r, cb)
    if r.action == "kit_build_plan" then
      plans[#plans + 1] = r
      return cb(
        true,
        vim.json.encode {
          name = "notes",
          summary = "The domain.",
          decisions = { "Plain Dart classes for entities", "Repositories behind interfaces" },
          files = { { path = "lib/note.txt", purpose = "note", docs = { "spec" } } },
        },
        { tokens_in = 10, tokens_out = 5 }
      )
    end
    cb(true, "hello\n", { tokens_in = 3, tokens_out = 2 })
  end,
}
local build = require "agent.kit.build"
local state = require "agent.kit.build.state"
vim.cmd.edit(vim.fn.fnameescape(proot .. "/SPEC.md"))
build.open "domain"
build.go()
vim.wait(1600)
build.go()
vim.wait(2000, function()
  return state.run.phase == "done"
end)
eq("build: done", state.run.phase, "done")
ok("build adr: the decisions recorded", read(proot .. "/docs/adr/0001-domain-plain-dart-classes-for-entities.md"))
ok(
  "build adr: the index",
  (read(proot .. "/docs/adr/README.md") or ""):find("[0001](0001-domain-plain-dart-classes-for-entities.md)", 1, true)
)
local pmd = read(proot .. "/PROGRESS.md") or ""
ok("build progress: written, the build logged", pmd:find("· domain · ✓ built", 1, true))
ok(
  "build progress: next = FR-2 (FR-1 has a test)",
  pmd:find("- FR-2 Export: no test proves it yet", 1, true) and not pmd:find("- FR-1 ", 1, true)
)
ok("build progress: SPEC.md's question", pmd:find("SPEC.md has 1 open question:", 1, true))
local agents_md = read(proot .. "/AGENTS.md")
ok(
  "build: both linked from AGENTS.md's Read first",
  agents_md:find("[docs/adr/README.md](docs/adr/README.md)", 1, true)
    and agents_md:find("[PROGRESS.md](PROGRESS.md)", 1, true)
)
ok(
  "build: the records are not code a layer builds on",
  not require("agent.kit.build.scope").keep "PROGRESS.md"
    and not require("agent.kit.build.scope").keep "docs/adr/0001-x.md"
)
-- a second build of the same decisions writes no second ADR
build.restart()
vim.wait(1600)
build.go()
vim.wait(2000, function()
  return state.run.phase == "done"
end)
eq("build adr: the same decisions again = no new ADR", vim.tbl_count(adr.read(proot)), 1)
ok("build: the first plan had no decisions to follow", not plans[1].prompt:find("<decisions>", 1, true))
ok(
  "build: the next plan follows the first one's ADR",
  plans[2].prompt:find("<decisions>", 1, true) and plans[2].prompt:find("- Plain Dart classes for entities", 1, true)
)
ok(
  "build: the feed says so",
  vim.iter(state.run.feed):any(function(f)
    return (f.meta or ""):find("follows 1 ADR", 1, true) ~= nil
  end)
)

vim.fn.delete(base, "rf")
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd "qa!"
