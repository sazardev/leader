-- Tests of the build's scopes (nvim/lua/agent/kit/build/scope.lua, <leader>aSb + b/t/s/d): the whole project or one layer
-- from the document that describes it (foundation STACK.md, domain SPEC.md, design DESIGN.md). The pure parts (which
-- documents each reads and requires, the plan request's rules and <project>, needs on existing files, the file request
-- of a file that exists) and a domain build on a temp project with a fake model: it builds on the existing files, never
-- remembers or cleans the ones it only changed, keeps its own saved run, and skips the user phase. Hermetic.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-kit-scope.lua"
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
package.loaded["utils.modal"] = {
  hl = setmetatable({}, {
    __index = function(_, k)
      return k
    end,
  }),
  confirm = function(_, _, yes)
    yes()
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

local scope = require "agent.kit.build.scope"
local plan = require "agent.kit.build.plan"
local prompt = require "agent.kit.build.prompt"
local build = require "agent.kit.build"
local state = require "agent.kit.build.state"

-- ── the scopes ───────────────────────────────────────────────────────────────

eq("scope: nil and unknown names are the whole build", { scope.get().name, scope.get("nope").name }, { "all", "all" })
eq(
  "scope: every name has a definition",
  vim.tbl_map(function(n)
    return scope.SCOPES[n] ~= nil
  end, scope.NAMES),
  { true, true, true, true }
)
eq(
  "scope: each layer's key is its document's letter in <leader>aS",
  vim.tbl_map(scope.keys, scope.NAMES),
  { "<leader>aSbb", "<leader>aSbt", "<leader>aSbs", "<leader>aSbd" }
)
eq("scope: the title says the layer and its document", scope.title "domain", "domain · from SPEC.md")
eq("scope: the whole build has no title", scope.title "all", "")
eq(
  "scope: the user phase only where there is an interface",
  vim.tbl_map(function(n)
    return scope.get(n).use
  end, scope.NAMES),
  { true, false, false, true }
)
eq(
  "scope: the wiring check only where an interface calls the code",
  vim.tbl_map(function(n)
    return scope.get(n).wiring
  end, scope.NAMES),
  { true, false, false, true }
)

eq(
  "keep: documents, generated files, binaries and dot folders are not code to build on",
  vim.tbl_map(scope.keep, {
    "STACK.md",
    "CLAUDE.md",
    "go.sum",
    "assets/logo.png",
    ".github/workflows/ci.yml",
    ".gitignore",
    "internal/domain/note.go",
    "README.md",
  }),
  { false, false, false, false, false, true, true, true }
)

local existing = {
  ["go.mod"] = "module example.com/notes\n\ngo 1.23\n",
  ["internal/domain/note.go"] = "package domain\n\n// Note is one note\ntype Note struct{}\n\nfunc New(title string) Note {\n  return Note{}\n}\n",
}
local block = scope.project(existing)
ok(
  "project: every existing file listed",
  block:find("- go.mod", 1, true) and block:find("- internal/domain/note.go", 1, true)
)
ok("project: the manifest whole", block:find('<file path="go.mod">\nmodule example.com/notes', 1, true))
ok("project: the API the code declares", block:find("func New(title string) Note", 1, true))
ok("project: an empty project says so", scope.project({}):find("no files yet", 1, true))

-- ── the plan request ─────────────────────────────────────────────────────────

local docs = { stack = "# STACK", spec = "# SPEC", design = "# DESIGN" }
local whole = plan.request(docs)
ok(
  "plan all: no scope rules, no <project>",
  not whole.system:find("Scope of this build", 1, true) and not whole.prompt:find("<project>", 1, true)
)
ok("plan all: the original last line", whole.prompt:find "Plan the files to build this project.$")
local domain_req = plan.request({ stack = "# STACK", spec = "# SPEC" }, "domain", existing)
ok("plan domain: its rules in the system prompt", domain_req.system:find("ONLY the domain, from SPEC.md", 1, true))
ok(
  "plan domain: the project it builds on",
  domain_req.prompt:find("<project>", 1, true) and domain_req.prompt:find("internal/domain/note.go", 1, true)
)
ok("plan domain: its own last line", domain_req.prompt:find "Plan the files of the project's domain.$")
ok(
  "plan domain: the documents it was given",
  domain_req.prompt:find("<spec>", 1, true) and not domain_req.prompt:find("<design>", 1, true)
)
ok(
  "plan foundation: no domain, no screens",
  plan.request({ stack = "# S" }, "foundation", {}).system:find("No domain logic, no screens", 1, true)
)
ok(
  "plan design: calls the existing domain",
  plan.request(docs, "design", existing).system:find("never write it again", 1, true)
)

local answer = vim.json.encode {
  name = "notes",
  files = {
    { path = "internal/domain/tag.go", purpose = "tags", needs = { "internal/domain/note.go" } },
    { path = "go.mod", purpose = "add a dependency" },
  },
}
local parsed = plan.parse(answer, existing, "domain")
eq("parse: a need on an existing file is kept", parsed.files[1].needs, { "internal/domain/note.go" })
eq("parse: and is not a problem", parsed.problems, {})
eq("parse: the scope stays in the plan", parsed.scope, "domain")
local alone = plan.parse(answer)
ok("parse: without the project, the same need is a problem", #alone.problems == 1 and alone.scope == nil)

-- ── the file requests ────────────────────────────────────────────────────────

local sys = prompt.system(parsed, { spec = "S" })
ok("file system: the layer's line", sys:find("This build is the domain only", 1, true))
ok("file system: the whole build has none", not prompt.system(alone, { spec = "S" }):find("This build is the", 1, true))
local file_req = prompt.file(parsed.files[1], parsed, { spec = "S" }, existing)
ok("file: the existing file it needs, whole", file_req.prompt:find('<file path="internal/domain/note.go">', 1, true))
ok("file: the API of the existing code", file_req.prompt:find("func New(title string) Note", 1, true))
local mod_req = prompt.file(parsed.files[2], parsed, { spec = "S" }, existing)
ok(
  "file: one that exists is shown as it is, to be updated",
  mod_req.prompt:find('<current path="go.mod">\nmodule example.com/notes', 1, true)
    and mod_req.prompt:find("already exists", 1, true)
)
ok("file: a new one has no current version", not file_req.prompt:find("<current", 1, true))

-- ── documents and saved state per scope ──────────────────────────────────────

local proot = base .. "/notes"
write(proot .. "/SPEC.md", "# SPEC\n")
local _, missing = build.docs(proot, "domain")
eq("docs domain: STACK.md is required", missing, { "STACK.md" })
write(proot .. "/STACK.md", "# STACK\n")
local ddocs, dmissing = build.docs(proot, "domain")
eq("docs domain: STACK.md and SPEC.md are enough, DESIGN.md not read", { dmissing, ddocs.design }, { {}, nil })
eq("docs design: DESIGN.md is required", select(2, build.docs(proot, "design")), { "DESIGN.md" })
eq("docs foundation: STACK.md alone is enough", select(2, build.docs(proot, "foundation")), {})
eq("docs all: the four", select(2, build.docs(proot)), { "AGENTS.md", "DESIGN.md" })
eq(
  "doc sizes domain: only what it reads",
  vim.tbl_map(function(d)
    return d.file
  end, build.doc_sizes(ddocs, "domain")),
  { "STACK.md", "SPEC.md" }
)
ok(
  "paths: the whole build keeps its file names",
  not state.path(proot):find "%.all%." and not build.manifest_path(proot):find "all"
)
ok(
  "paths: each layer has its own run and list of files",
  state.path(proot, "domain") ~= state.path(proot)
    and build.manifest_path(proot, "domain") ~= build.manifest_path(proot)
)

-- ── a domain build on the files the project has ──────────────────────────────

write(proot .. "/src/base.txt", "base api\n")
write(proot .. "/logo.png", "\0png")
vim.system({ "git", "init", "-q" }, { cwd = proot }):wait()
local asked, requests = {}, {}
package.loaded["agent"] = {
  complete = function(r, cb)
    asked[#asked + 1] = r.action
    requests[#requests + 1] = r
    if r.action == "kit_build_plan" then
      return cb(
        true,
        vim.json.encode {
          name = "notes",
          files = {
            { path = "src/dom.txt", purpose = "the domain", docs = { "spec" }, needs = { "src/base.txt" } },
            { path = "src/base.txt", purpose = "base, extended", docs = { "stack" } },
          },
        },
        { tokens_in = 10, tokens_out = 5 }
      )
    end
    cb(true, "hello " .. r.prompt:match "Write `([^`]+)`" .. "\n", { tokens_in = 3, tokens_out = 2 })
  end,
}
vim.cmd.edit(vim.fn.fnameescape(proot .. "/SPEC.md"))
build.open "all"
ok(
  "open all: refused, naming what the whole build needs",
  notes[#notes]:find("missing AGENTS.md (<leader>aSa), DESIGN.md (<leader>aSd)", 1, true)
)
build.open "domain"
eq(
  "open domain: the pre-flight of a domain run",
  { state.run.phase, state.run.scope, #asked },
  { "ready", "domain", 0 }
)
eq(
  "open domain: the code pane says what it builds",
  vim.api.nvim_buf_get_lines(vim.fn.bufnr "build://code", 0, 1, false)[1],
  "# Build · domain"
)
build.go()
eq("domain: Enter plans, then the review", { state.run.phase, asked[1] }, { "review", "kit_build_plan" })
eq("domain: the existing text files it builds on (no binaries, no documents)", state.run.existing, { "src/base.txt" })
ok(
  "domain: the plan request carries <project>",
  requests[1].prompt:find("<project>", 1, true) and requests[1].prompt:find("- src/base.txt", 1, true)
)
eq(
  "domain: the file it changes comes first (the other needs it) and is marked as the project's",
  { state.run.files[1].path, state.run.files[1].existed, state.run.files[2].existed },
  { "src/base.txt", true, nil }
)
vim.wait(1600)
build.go()
vim.wait(2000, function()
  return state.run.phase == "done"
end)
eq(
  "domain: plan and one request per file, no user phase",
  asked,
  { "kit_build_plan", "kit_build_file", "kit_build_file" }
)
ok(
  "domain: the changed file is asked with its current version",
  requests[2].prompt:find('<current path="src/base.txt">\nbase api', 1, true)
)
ok(
  "domain: the new file sees the one it needs, as changed",
  requests[3].prompt:find('<file path="src/base.txt">\nhello src/base.txt', 1, true)
)
ok("domain: every file request has the layer's line", requests[2].system:find("This build is the domain only", 1, true))
ok("domain: no wiring check", not vim.tbl_contains(
  vim.tbl_map(function(c)
    return c.label
  end, state.run.checks),
  "the interface uses what the plan exports"
))
eq(
  "domain: files written",
  { read(proot .. "/src/dom.txt"), read(proot .. "/src/base.txt") },
  { "hello src/dom.txt\n", "hello src/base.txt\n" }
)
eq("domain: only the file it created is remembered as its own", build.previous(proot, "domain"), { "src/dom.txt" })
eq("domain: the whole build's list is untouched", build.previous(proot), {})
ok("domain: saved as the domain's run", state.load(proot, "domain") ~= nil and state.load(proot) == nil)
ok(
  "domain: the statusline names the layer",
  (function()
    state.run.running = true
    local line = state.statusline()
    state.run.running = false
    return line:find("build domain", 1, true)
  end)()
)

-- a replan builds again on the project, without its own old files (its new plan replaces them)
asked, requests = {}, {}
build.restart()
eq("replan: the domain's own file is not shown as existing", state.run.existing, { "src/base.txt" })
eq("replan: the old file it drops is stale, the changed one never", state.run.stale, {})

-- clean: the files it created go to the trash, the ones it changed stay
state.run.files[1].state, state.run.files[2].state = "done", "done"
build.clean()
eq(
  "clean: the created file to the trash, the changed one stays",
  { read(proot .. "/src/dom.txt"), read(proot .. "/src/base.txt") },
  { nil, "hello src/base.txt\n" }
)

vim.fn.delete(base, "rf")
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd "qa!"
