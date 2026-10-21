-- What the build may claim and what it may throw away (nvim/lua/agent/kit/decls.lua, build/proof.lua, build/loss.lua, the plan's
-- risks and deferred requirements, the checks every project gets): "checks pass" is not "SPEC.md is delivered". Hermetic:
-- temp projects, a fake model, no network or tokens.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-kit-honesty.lua"
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

local decls = require "agent.kit.decls"
local proof = require "agent.kit.build.proof"
local loss = require "agent.kit.build.loss"
local verify = require "agent.kit.build.verify"
local plan_mod = require "agent.kit.build.plan"
local plancheck = require "agent.kit.build.plancheck"

local function names(list)
  return vim.tbl_map(function(d)
    return d.name
  end, list)
end

-- ── what a file declares ─────────────────────────────────────────────────────
eq(
  "dart: public types at column 0 only",
  names(
    decls.of(
      "lib/a.dart",
      "abstract class Port {\n}\nclass _Private {}\nclass Impl extends Port {\n  class Nested {}\n}\nenum Mode { a }\nmixin Logs {}\nfinal x = 1;\n"
    )
  ),
  { "Port", "Impl", "Mode", "Logs" }
)
eq("dart: line numbers", decls.of("a.dart", "\n\nclass Foo {}")[1].line, 3)
eq(
  "ts: exports, types and values",
  vim.tbl_map(
    function(d)
      return d.name .. ":" .. d.kind
    end,
    decls.of(
      "a.ts",
      "export interface User {}\nexport type Id = string\nexport function make() {}\nexport const KEY = 1\nconst hidden = 2\n"
    )
  ),
  { "User:type", "Id:type", "make:value", "KEY:value" }
)
eq(
  "go: exported only",
  names(
    decls.of(
      "a.go",
      "type Server struct{}\ntype helper struct{}\nfunc New() {}\nfunc (s *Server) Run() {}\nfunc private() {}\n"
    )
  ),
  { "Server", "New" }
)
eq(
  "rust: pub items",
  names(decls.of("a.rs", "pub struct Engine;\nstruct Hidden;\npub fn run() {}\npub(crate) fn x() {}\n")),
  { "Engine", "run" }
)
eq(
  "python: public classes and functions",
  names(decls.of("a.py", "class Foo:\n    def method(self): pass\ndef helper(): pass\ndef _private(): pass\n")),
  { "Foo", "helper" }
)
eq(
  "kotlin: classes and objects",
  names(decls.of("A.kt", "data class User(val id: Int)\nobject Registry\nclass Impl\n")),
  { "User", "Registry", "Impl" }
)
eq("no pattern, no declarations", decls.of("README.md", "class Foo"), {})
ok(
  "sources: tests are not",
  not decls.is_source "test/a_test.dart" and not decls.is_source "src/a.test.ts" and not decls.is_source "pkg/a_test.go"
)
ok(
  "sources: generated code is not",
  not decls.is_source "lib/a.g.dart" and not decls.is_source "lib/l10n/app_localizations_en.dart"
)
ok(
  "sources: a tool's scaffold is not",
  not decls.is_source "rust_builder/cargokit/build_tool/lib/a.dart" and not decls.is_source "build/x.dart"
)
ok(
  "sources: examples, vendored code, docs and scripts are not",
  not decls.is_source "example/lib/main.dart"
    and not decls.is_source "packages/x/example/a.dart"
    and not decls.is_source "vendor/lib/a.go"
    and not decls.is_source "scripts/gen.py"
    and not decls.is_source "docs/site/a.ts"
)
ok(
  "sources: the project's code is",
  decls.is_source "lib/features/editor/a.dart" and decls.is_source "internal/store/store.go"
)

-- ── the same type declared twice ─────────────────────────────────────────────
local dups = decls.duplicates {
  ["lib/domain/editor_ports.dart"] = "abstract class ProjectRepository {\n}\nclass EditorResult {}\n",
  ["lib/domain/project_repository.dart"] = "abstract class ProjectRepository {\n}\n",
  ["lib/presentation/timeline_view.dart"] = "class TimelineView {}\n",
  ["lib/presentation/widgets/timeline_view.dart"] = "class TimelineView {}\n",
  ["lib/data/state.dart"] = "class State {}\n",
  ["lib/ui/state.dart"] = "class State {}\n", -- generic: leave it
  ["lib/a.dart"] = "class Abc {}\n",
  ["lib/b.dart"] = "class Abc {}\n", -- short: leave it
  ["test/x_test.dart"] = "class ProjectRepository {}\n", -- tests never count
}
eq("duplicates: the two ports and the two views", names(dups), { "ProjectRepository", "TimelineView" })
eq(
  "duplicates: where each is",
  vim.tbl_map(function(w)
    return w.path .. ":" .. w.line
  end, dups[1].where),
  { "lib/domain/editor_ports.dart:1", "lib/domain/project_repository.dart:1" }
)
eq(
  "duplicates: Go packages are separate namespaces",
  names(decls.duplicates { ["a/store.go"] = "type Server struct{}", ["b/store.go"] = "type Server struct{}" }),
  {}
)
eq(
  "duplicates: but one package is one",
  names(decls.duplicates { ["a/one.go"] = "type Server struct{}", ["a/two.go"] = "type Server struct{}" }),
  { "Server" }
)
eq(
  "duplicates: one file declaring twice is not two files",
  #decls.duplicates { ["a.dart"] = "class Widget1 {}\nclass Widget1 {}" },
  0
)
local ok_dup, msg = verify.duplicate_types {
  ["lib/a.dart"] = "class ProjectRepository {}",
  ["lib/b.dart"] = "class ProjectRepository {}",
}
ok(
  "check: it fails and says what to do",
  not ok_dup
    and msg:find("ProjectRepository is declared in 2 files", 1, true)
    and msg:find("delete the duplicate", 1, true)
)
eq(
  "check: clean sources pass",
  { verify.duplicate_types { ["lib/a.dart"] = "class Alpha {}", ["lib/b.dart"] = "class Beta {}" } },
  { true, "" }
)
eq(
  "lost: names that are gone",
  decls.lost(decls.of("a.dart", "class A {}\nclass B {}"), decls.of("a.dart", "class B {}")),
  { "A" }
)
eq(
  "users: whole words only",
  decls.users("Foo", { ["a"] = "Foo()", ["b"] = "FooBar()", ["c"] = "x.Foo" }, "c"),
  { "a" }
)

-- ── the checks every project gets ────────────────────────────────────────────
local base = vim.fn.tempname()
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text or "")
  f:close()
end
local function labels(list)
  return vim.tbl_map(function(c)
    return c.label
  end, list)
end
write(base .. "/flutter/pubspec.yaml", "name: x\n")
write(base .. "/flutter/lib/main.dart", "void main() {}\n")
write(base .. "/flutter/test/a_test.dart", "void main() {}\n")
eq(
  "flutter: analyze AND test, then the duplicate check",
  labels(verify.checks(base .. "/flutter")),
  { "flutter pub get", "flutter analyze", "flutter test", "no type is declared twice" }
)
write(base .. "/notest/pubspec.yaml", "name: x\n")
write(base .. "/notest/lib/main.dart", "void main() {}\n")
eq(
  "flutter without tests: no test check",
  labels(verify.checks(base .. "/notest")),
  { "flutter pub get", "flutter analyze", "no type is declared twice" }
)
write(base .. "/rust/Cargo.toml", "[package]\nname='x'\n")
write(base .. "/rust/tests/a.rs", "")
eq("rust with tests: cargo test too", labels(verify.checks(base .. "/rust"))[2], "cargo test")
write(base .. "/dup/pubspec.yaml", "name: x\n")
write(base .. "/dup/lib/a.dart", "class ProjectRepository {}\n")
write(base .. "/dup/lib/b.dart", "class ProjectRepository {}\n")
vim.system({ "git", "init", "-q" }, { cwd = base .. "/dup" }):wait()
local dup_checks = verify.checks(base .. "/dup")
local dup_ok, dup_msg = dup_checks[#dup_checks].fn()
ok("the check on a real project finds them", not dup_ok and dup_msg:find("ProjectRepository", 1, true))
eq("no manifest, no checks (as before)", verify.checks(base .. "/nothing"), {})

-- ── placeholders ─────────────────────────────────────────────────────────────
local ph = proof.placeholders {
  ["lib/editor_page.dart"] = "Widget build() {\n  return Text(l10n.previewPlaceholder);\n}\n// TODO: wire the engine\n",
  ["lib/engine.dart"] = "Future<void> decode() => throw UnimplementedError();\n",
  ["lib/search.dart"] = "TextField(decoration: InputDecoration(hintText: 'x'), placeholder: 'Search')\n",
  ["src/Input.tsx"] = '<input placeholder="Search" />\n',
  ["src/engine.rs"] = "pub fn decode() { todo!() }\n",
  ["test/a_test.dart"] = "// TODO later\n",
  ["lib/l10n/app_localizations_en.dart"] = "String get previewPlaceholder => 'Preview';\n",
  ["lib/clean.dart"] = "class Clean {}\n",
}
eq(
  "placeholders: stand-ins found, a toolkit's own placeholder and tests left alone",
  vim.tbl_map(function(p)
    return p.path .. ":" .. p.line
  end, ph),
  { "lib/editor_page.dart:2", "lib/editor_page.dart:4", "lib/engine.dart:1", "src/engine.rs:1" }
)
eq("placeholders: capped", #proof.placeholders({ ["a.go"] = string.rep("// TODO x\n", 100) }, 5), 5)

-- ── core requirements ────────────────────────────────────────────────────────
local spec = table.concat({
  "# SPEC",
  "## Goals",
  "- G1: speed (see NFR-1).",
  "- G2: all work in the engine (see FR-16, NFR-2).",
  "- G3: the full surface (FR-1 to FR-3).",
  "## Requirements",
  "**FR-1 — Timeline.** x",
  "**FR-2 — Import.** x",
  "**FR-3 — Music.** x",
  "**FR-4 — Extra (core).** x",
  "**FR-5 — Nice.** x",
  "**FR-16 — Engine.** x",
  "## Open questions",
}, "\n")
local core = proof.core_ids(spec)
local ids = vim.tbl_keys(core)
table.sort(ids)
eq("core: cited by the goals, ranges expanded, or marked", ids, { "FR-1", "FR-16", "FR-2", "FR-3", "FR-4" })
eq("core: nothing cited, nothing core", proof.core_ids "# SPEC\n**FR-1** x", {})

-- ── the summary and the line ─────────────────────────────────────────────────
local reqs = {
  { id = "FR-1", tests = { "t1" } },
  { id = "FR-2", tests = {} },
  { id = "FR-3", tests = { "t3" } },
  { id = "FR-16", tests = {} },
}
local sum = proof.summary(reqs, core, { "FR-1", "FR-2" }, { { path = "a", line = 1, text = "x" } }, { "Gone (a.dart)" })
eq("summary: counts", { sum.total, sum.proven }, { 4, 2 })
eq("summary: unproven and core", { sum.unproven, sum.core_unproven }, { { "FR-2", "FR-16" }, { "FR-2", "FR-16" } })
eq("summary: a requirement that lost its test", sum.regressions, { "FR-2" })
eq(
  "line: what is proven and what is not",
  proof.line(sum),
  " · 2/4 requirements have a test · core without one: FR-2, FR-16 · 1 placeholder · lost the test of FR-2 · removed 1 public declaration"
)
ok(
  "outcome: partial, with the icon that says so",
  proof.outcome(23, sum, nil):find "^◐ built · 23 files · checks pass · 2/4"
)
eq("verdict: a layer only reports", proof.verdict(sum, "design"), "ok")
eq("verdict: the whole project is judged", proof.verdict(sum, "all"), "partial")
eq("verdict: a feature too", proof.verdict(sum, "feature"), "partial")
local full = proof.summary({ { id = "FR-1", tests = { "t" } } }, {}, nil, {}, {})
eq("verdict: all proven, nothing open", proof.verdict(full, nil), "ok")
eq(
  "outcome: and the plain line",
  proof.outcome(5, full, nil),
  "✓ built · 5 files · checks pass · 1/1 requirements have a test"
)
eq(
  "outcome: no requirements, nothing to say",
  proof.outcome(5, proof.summary({}, {}, nil, {}, {}), nil),
  "✓ built · 5 files · checks pass"
)
ok(
  "open lines: placeholders, lost proof, removed API",
  (function()
    local text = table.concat(proof.open_lines(sum), "\n")
    return text:find("core requirements no test names yet: FR-2, FR-16", 1, true)
      and text:find("not real yet: `a:1` x", 1, true)
      and text:find("lost their test in this build: FR-2", 1, true)
      and text:find("removed by this build: Gone (a.dart)", 1, true)
  end)()
)
eq(
  "removed API: what the rewritten and deleted files declared",
  proof.removed_api({
    ["lib/a.dart"] = "class Keep {}\nclass Dropped {}",
    ["lib/b.dart"] = "class Whole {}",
    ["lib/c.dart"] = "class Same {}",
  }, { ["lib/a.dart"] = "class Keep {}", ["lib/b.dart"] = nil, ["lib/c.dart"] = "class Same {}" }),
  { "Dropped (lib/a.dart)", "Whole (lib/b.dart)" }
)

-- ── what a replan would throw away ───────────────────────────────────────────
local l = loss.describe({
  ["lib/widgets/preview_canvas.dart"] = "class PreviewCanvas {}\n" .. string.rep("// body\n", 30),
  ["test/editor_page_test.dart"] = "// FR-5 FR-4\nvoid main() {}\n",
}, { ["lib/editor_page.dart"] = "PreviewCanvas()\n" })
eq("loss: lines and types", { l.lines >= 30, l.types }, { true, 1 })
ok("loss: a real declaration is significant", l.significant)
eq("loss: who still uses it", l.files[1].used_by, { "lib/editor_page.dart" })
eq("loss: the requirements its tests name", l.files[2].tests, { "FR-4", "FR-5" })
ok(
  "loss: said in words",
  (function()
    local text = table.concat(loss.lines(l), "\n")
    return text:find("2 files", 1, true)
      and text:find("PreviewCanvas", 1, true)
      and text:find("still used by lib/editor_page.dart", 1, true)
  end)()
)
local small = loss.describe({ ["notes.txt"] = "x\n" }, {})
ok("loss: a little text is not significant", not small.significant)
ok("loss: a lot of lines is", loss.describe({ ["big.txt"] = string.rep("x\n", 80) }, {}).significant)
eq("loss: nothing to read, nothing to say", loss.read("/nonexistent", {}), nil)

-- ── the plan: it sees the code, names the risk, defers honestly ──────────────
local docs = { agents = "# A", stack = "# S", design = "# D", spec = spec }
local fresh = plan_mod.request(docs, nil, {}, nil, nil)
ok(
  "plan: a fresh project is planned as before",
  not fresh.prompt:find("<project>", 1, true) and not fresh.system:find("The project already has code", 1, true)
)
local seen = plan_mod.request(
  docs,
  nil,
  { ["lib/domain/ports.dart"] = "abstract class ProjectRepository {}\n", ["pubspec.yaml"] = "name: x\n" },
  nil,
  nil
)
ok(
  "plan: a project with code is shown to a whole-project plan",
  seen.prompt:find("<project>", 1, true) and seen.prompt:find("ProjectRepository", 1, true)
)
ok(
  "plan: and told to use only what exists",
  seen.system:find("Use exactly the names <api> shows", 1, true)
    and seen.system:find("Never plan a second version", 1, true)
)
ok("plan: a manifest alone is not code", not plan_mod.has_code { ["pubspec.yaml"] = "x", ["README.md"] = "x" })
ok(
  "plan: the system prompt asks for risks, deferral and no silent stand-ins",
  (function()
    return fresh.system:find('"risks"', 1, true)
      and fresh.system:find('"deferred"', 1, true)
      and fresh.system:find("Never plan a placeholder", 1, true)
  end)()
)
local parsed = plan_mod.parse(
  vim.json.encode {
    name = "x",
    summary = "s",
    architecture = "a",
    risks = { { req = "FR-16", why = "native decode" }, { req = "FR-2" }, "bad" },
    deferred = { { req = "FR-5", why = "needs the camera plugin" } },
    wiring = { { req = "FR-1", action = "a", code = "c", shows = "s" } },
    files = {
      { path = "lib/engine.dart", purpose = "the real decode path", verifies = "FR-16", docs = { "spec" } },
      {
        path = "lib/preview.dart",
        purpose = "placeholder preview until the engine exists",
        verifies = "FR-2",
        docs = { "spec" },
      },
      { path = "test/a_test.dart", purpose = "tests", verifies = "FR-1, FR-3", docs = { "spec" } },
    },
  },
  {},
  nil
)
eq("plan: risks keep the complete rows", parsed.risks, { { req = "FR-16", why = "native decode" } })
eq("plan: so do the deferred", parsed.deferred, { { req = "FR-5", why = "needs the camera plugin" } })
local warnings = plancheck.warnings(parsed, spec, nil)
ok("warnings: a deferral is stated", vim.tbl_contains(warnings, "FR-5 is deferred: needs the camera plugin"))
ok(
  "warnings: a stand-in for a core requirement is named",
  (function()
    for _, w in ipairs(warnings) do
      if w:find("lib/preview.dart is a stand-in", 1, true) and w:find("core requirement FR-2", 1, true) then
        return true
      end
    end
    return false
  end)()
)
ok(
  "warnings: a requirement neither built nor deferred is named",
  (function()
    for _, w in ipairs(warnings) do
      if w:find("not built, not wired and not deferred", 1, true) and not w:find("FR-16", 1, true) then
        return true
      end
    end
    return false
  end)()
)
local with_test = plan_mod.parse(
  vim.json.encode {
    name = "x",
    summary = "s",
    architecture = "a",
    risks = { { req = "FR-1", why = "w" } },
    files = {
      {
        path = "tests/test_store.py",
        purpose = "tests with a fake clock and a temporary directory",
        verifies = "FR-1",
        docs = { "spec" },
      },
      { path = "lib/engine.py", purpose = "a stub of the engine for now", verifies = "FR-2", docs = { "spec" } },
    },
  },
  {},
  nil
)
local stand_ins = vim.tbl_filter(function(w)
  return w:find("is a stand-in", 1, true)
end, plancheck.warnings(with_test, spec, nil))
eq("warnings: a test using a fake is not a stand-in, a stub of the engine is", #stand_ins, 1)
ok("warnings: and it names the engine", stand_ins[1] and stand_ins[1]:find("lib/engine.py", 1, true))
eq("warnings: a layer is not asked for every requirement", plancheck.warnings(parsed, spec, "design"), {})
parsed.risks = {}
ok(
  "warnings: no risk named is said",
  vim.tbl_contains(
    plancheck.warnings(parsed, spec, nil),
    "the plan names no risky requirement, so nothing says the hard part is built first"
  )
)

-- ── PROGRESS.md carries the proof ────────────────────────────────────────────
local progress = require "agent.kit.progress"
local md = progress.render(nil, {
  name = "x",
  root = "/tmp/x",
  phase = "done",
  outcome = proof.outcome(3, sum, nil),
  files = {},
  totals = { cost = 0.1 },
  plan = { name = "x", summary = "S" },
}, { date = "2026-10-21", questions = 0, next = {}, keys = "bb", proof = sum })
ok("progress: the proof is in Now", md:find("- Proof: 2/4 requirements have a test · core without one", 1, true))
ok(
  "progress: what is open comes from it",
  md:find("- not real yet: `a:1` x", 1, true) and md:find("lost their test in this build: FR-2", 1, true)
)
ok("progress: the log says the build was not proven", md:find("◐ built", 1, true))

-- ── a whole-project build says what it did not prove ─────────────────────────
local proot = base .. "/notes"
write(proot .. "/AGENTS.md", "# AGENTS.md: notes\n\n## Read first\n\n- [SPEC.md](SPEC.md): x.\n\n## Commands\n")
write(proot .. "/STACK.md", "# STACK\n")
write(proot .. "/DESIGN.md", "# DESIGN\n")
write(
  proot .. "/SPEC.md",
  "# SPEC\n\n## Goals\n\n- G1: everything (FR-1 to FR-2).\n\n## Requirements\n\n### FR-1: Create\n\n### FR-2: Export\n"
)
write(proot .. "/lib/ports.dart", "abstract class ProjectRepository {\n  Future<void> save();\n}\n")
vim.system({ "git", "init", "-q" }, { cwd = proot }):wait()
local plan_prompt
package.loaded["agent"] = {
  complete = function(r, cb)
    if r.action == "kit_build_plan" then
      plan_prompt = r.prompt
      return cb(
        true,
        vim.json.encode {
          name = "notes",
          summary = "The app.",
          decisions = { "Plain classes" },
          risks = { { req = "FR-2", why = "export is the unknown" } },
          files = {
            { path = "lib/note.txt", purpose = "note", verifies = "FR-1", docs = { "spec" } },
            { path = "lib/export.txt", purpose = "placeholder export", docs = { "spec" } },
          },
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
build.open()
build.go()
vim.wait(1600)
build.go()
vim.wait(3000, function()
  return state.run.phase == "done"
end)
eq("whole build: it finishes", state.run.phase, "done")
ok(
  "whole build: the plan was shown the code earlier builds left (it used to see only the ADRs)",
  plan_prompt
    and plan_prompt:find("lib/ports.dart", 1, true)
    and plan_prompt:find("abstract class ProjectRepository", 1, true)
)
ok(
  "whole build: that file is the build's existing code, not something it writes",
  vim.tbl_contains(state.run.existing or {}, "lib/ports.dart")
)
ok(
  "whole build: the line says it is not proven, and why",
  state.run.outcome:find "^◐ built" and state.run.outcome:find("requirements have a test", 1, true) ~= nil
)
ok("whole build: the plan's warnings are kept", #(state.run.plan.warnings or {}) > 0)
local progress_md = (function()
  local f = io.open(proot .. "/PROGRESS.md", "r")
  local t = f and f:read "*a" or ""
  if f then
    f:close()
  end
  return t
end)()
ok("whole build: PROGRESS.md has the proof line", progress_md:find("- Proof:", 1, true) ~= nil)
ok("whole build: and what is open", progress_md:find("core requirements no test names yet", 1, true) ~= nil)

print(fails == 0 and ("\nALL OK (" .. total .. " checks)") or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
