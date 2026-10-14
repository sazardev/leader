-- Tests of the staged review (diff parsing, free checks, the model pass and where findings land) and of the one-shot calls
-- showing up in the history. Hermetic: a temporary git repo with staged changes, a fake model.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local diff = require "agent.review.diff"
local static = require "agent.review.static"
local protocol = require "agent.protocol"

-- ── diff parsing (pure) ─────────────────────────────────────────────────────
local RAW = table.concat({
  "diff --git a/svc.go b/svc.go",
  "index 111..222 100644",
  "--- a/svc.go",
  "+++ b/svc.go",
  "@@ -10,3 +10,5 @@ func Get() {",
  " \tn := load()",
  "-\treturn n",
  "+\tif n == nil {",
  "+\t\treturn nil",
  "+\t}",
  " }",
  "diff --git a/go.sum b/go.sum",
  "new file mode 100644",
  "--- /dev/null",
  "+++ b/go.sum",
  "@@ -0,0 +1,1 @@",
  "+abc",
  "diff --git a/old.go b/old.go",
  "deleted file mode 100644",
  "--- a/old.go",
  "+++ /dev/null",
  "@@ -1,1 +0,0 @@",
  "-package old",
}, "\n")
local files = diff.parse(RAW)
eq(
  "diff: three files with their status",
  vim.tbl_map(function(f)
    return f.path .. ":" .. f.status
  end, files),
  { "svc.go:modified", "go.sum:new", "old.go:deleted" }
)
local added = diff.added(files[1])
eq(
  "diff: added lines carry their NEW line numbers",
  vim.tbl_map(function(a)
    return a.n
  end, added),
  { 11, 12, 13 }
)
local text, stats = diff.render(files, 10000, function(p)
  return p:find "sum$" ~= nil
end)
ok(
  "diff: rendered with `+L<n>` for added and ` L<n>` for context",
  text:find("+L11 \tif n == nil {", 1, true) ~= nil and text:find(" L10 \tn := load()", 1, true) ~= nil
)
ok("diff: removed lines have no number", text:find("-    \treturn n", 1, true) ~= nil)
eq("diff: noise and deleted files are skipped, not sent", { stats.files, stats.skipped }, { 1, { "go.sum", "old.go" } })
local capped, cs = diff.render(
  {
    {
      path = "a.go",
      status = "modified",
      hunks = { { start = 1, lines = { { k = "+", n = 1, text = string.rep("x", 5000) } } } },
    },
  },
  1000,
  function()
    return false
  end
)
ok("diff: a huge file is cut to its share", #capped < 1500 and cs.truncated)

-- ── free checks (pure) ──────────────────────────────────────────────────────
local function file(path, lines, status)
  local hunk = { start = 1, lines = {} }
  for i, t in ipairs(lines) do
    hunk.lines[#hunk.lines + 1] = { k = "+", n = i, text = t }
  end
  return { path = path, status = status or "modified", hunks = { hunk } }
end
local function msgs(f, sens)
  return vim.tbl_map(function(x)
    return x.line .. ":" .. x.message
  end, static.check({ f }, sens))
end
eq("static: an AWS key", msgs(file("a.go", { 'k := "AKIAIOSFODNN7EXAMPLE"' })), { "1:looks like an AWS access key" })
eq("static: a conflict marker", msgs(file("a.go", { "ok", "<<<<<<< HEAD" })), { "2:a merge conflict marker is staged" })
eq("static: a password literal", #static.check { file("a.py", { 'password = "hunter2hunter2"' }) }, 1)
eq(
  "static: a validation message is not a secret",
  #static.check { file("a.js", { 'password: "Password is required."' }) },
  0
)
eq(
  "static: a placeholder is not a secret",
  #static.check { file("a.py", { 'password = "changeme-please"', 'token = "$TOKEN_VALUE"' }) },
  0
)
eq(
  "static: console.log in js is a warning",
  static.check({ file("a.js", { "console.log(x)" }) })[1].severity,
  vim.diagnostic.severity.WARN
)
eq("static: but not in a test file", #static.check { file("a.test.js", { "console.log(x)" }) }, 0)
eq(
  "static: a sensitive path",
  msgs(file(".env.local", { "A=1" }), { "^%.env" }),
  { "1:a sensitive file is staged (secrets, keys): unstage it" }
)
eq("static: deleted files are not judged", #static.check { file("a.js", { "console.log(1)" }, "deleted") }, 0)

-- ── the protocol ────────────────────────────────────────────────────────────
local parsed =
  protocol.parse_file_findings "svc.go:12|warn|nil is returned silently\nnot a finding\nsub/dir/x.go:3|error|panics when empty"
eq(
  "protocol: path:line|sev|message",
  vim.tbl_map(function(f)
    return f.path .. "@" .. f.line .. "/" .. f.severity
  end, parsed),
  { "svc.go@12/2", "sub/dir/x.go@3/1" }
)

-- ── the whole review on a real repo ─────────────────────────────────────────
local dir = K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["svc.go"] = { "package p", "", "func Get() int {", "\treturn 1", "}" },
}
local FAKE = K.fake()
local git = require "commit.git"
local review = require "agent.review"
-- stage: a changed file, a secret in a new file, a lockfile
vim.fn.writefile({ "package p", "", "func Get() int {", "\tx := load()", "\treturn x.N", "}" }, dir .. "/svc.go")
vim.fn.writefile({ "package p", "", 'const key = "AKIAIOSFODNN7EXAMPLE"' }, dir .. "/keys.go")
vim.fn.writefile({ "x" }, dir .. "/yarn.lock")
vim.fn.system { "git", "-C", dir, "add", "-A" }
FAKE.text =
  "svc.go:5|warn|x may be nil: dereferenced without a check\nghost.go:1|error|a file that is not in the diff\nsvc.go:99|info|a line far away"
local result
review.run(dir, function(r)
  result = r
end)
K.wait(function()
  return result ~= nil
end, 6000)
ok("review: one model call", FAKE.calls == 1)
ok(
  "review: the prompt has the numbered diff and only reviewable files",
  FAKE.req.prompt:find("## svc.go", 1, true) ~= nil
    and FAKE.req.prompt:find("+L5", 1, true) ~= nil
    and not FAKE.req.prompt:find("yarn.lock", 1, true)
)
ok("review: the system prompt is the review framing", FAKE.req.system:find("BEFORE it is committed", 1, true) ~= nil)
local paths = vim.tbl_map(function(f)
  return f.path .. ":" .. f.line
end, result.findings)
table.sort(paths)
eq("review: free + model findings; an invented path or line is dropped", paths, { "keys.go:3", "svc.go:5" })
eq("review: how many came free", result.static, 1)
eq("review: the lockfile was skipped, not sent", result.skipped, { "yarn.lock" })
eq("review: the quickfix has them", #vim.fn.getqflist(), 2)
-- an open file gets diagnostics now
local buf = K.open "svc.go"
require("agent.persist").restore(buf)
local diags = vim.diagnostic.get(buf, { namespace = require("agent.output.findings").namespace() })
eq(
  "review: opening the file shows its finding as a diagnostic",
  { #diags, diags[1] and diags[1].lnum, diags[1] and diags[1].source },
  { 1, 4, "staged review" }
)
-- one-shot calls are in the history (the budget sees them)
local hist = require("agent.runs.store").read()
local last = hist[#hist]
eq(
  "history: the review call is recorded as a one-shot",
  { last.action, last.output, last.status },
  { "review_staged", "oneshot", "done" }
)
eq("history: and shows as its own name, not a file:line", require("agent.runs.format").target(last), "review_staged")

-- nothing but noise → 0 tokens
vim.fn.system { "git", "-C", dir, "reset", "-q" }
vim.fn.system { "git", "-C", dir, "add", "yarn.lock" }
FAKE.calls = 0
local noise_result
review.run(dir, function(r)
  noise_result = r
end)
K.wait(function()
  return noise_result ~= nil
end, 4000)
eq("review: only a lockfile staged → no model call", { FAKE.calls, noise_result.sent }, { 0, false })
vim.fn.system { "git", "-C", dir, "reset", "-q" }
local none, why
review.run(dir, function(r, e)
  none, why = r, e
end)
eq("review: nothing staged is said and costs nothing", { FAKE.calls, why }, { 0, "nothing is staged" })

-- the guard can stop it
vim.fn.system { "git", "-C", dir, "add", "svc.go" }
require("core.settings").agent.budget.day_usd = 0.000001
local denied
review.run(dir, function(r)
  denied = r
end)
K.wait(function()
  return denied ~= nil
end, 4000)
eq(
  "review: a used-up budget stops the model pass (the free checks still ran)",
  { denied.sent, FAKE.calls },
  { false, 0 }
)
require("core.settings").agent.budget.day_usd = nil

-- ── context providers: callers and the history of the lines ─────────────────
local gitlog = require "agent.context.providers.gitlog"
eq(
  "gitlog: keeps only commit lines, newest first, up to the limit",
  gitlog.parse(
    "b74e818 2026-10-14 fix(a): right value\nnoise\nf3aa6ce 2026-10-13 feat(a): first\nabc1234 2026-10-01 old",
    2
  ),
  { "b74e818 2026-10-14 fix(a): right value", "f3aa6ce 2026-10-13 feat(a): first" }
)
local gdir = K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["a.go"] = { "package p", "", "func A() int {", "	return 1", "}" },
}
vim.fn.writefile({ "package p", "", "func A() int {", "	return 2", "}" }, gdir .. "/a.go")
vim.fn.system {
  "git",
  "-C",
  gdir,
  "-c",
  "user.email=t@t",
  "-c",
  "user.name=t",
  "commit",
  "-qam",
  "fix(a): return the right value",
}
local gbuf = K.open "a.go"
local target = require("agent.context.target").of_range(gbuf, "function", 3, 5, "A")
local history
gitlog.collect(target, function(text)
  history = text
end)
K.wait(function()
  return history ~= nil
end, 4000)
ok(
  "gitlog: the commits that touched the function, with the framing",
  history
    and history:find("Recent commits that touched these lines", 1, true) ~= nil
    and history:find("fix(a): return the right value", 1, true) ~= nil
    and history:find("base", 1, true) ~= nil
)
vim.fn.writefile({ "package p", "", "func New() int {", "	return 3", "}" }, gdir .. "/new.go")
local nbuf = K.open "new.go"
local nothing = "unset"
gitlog.collect(require("agent.context.target").of_range(nbuf, "function", 3, 5, "New"), function(text)
  nothing = text
end)
K.wait(function()
  return nothing ~= "unset"
end, 4000)
eq("gitlog: a file with no history adds nothing", nothing, nil)

local callers = require "agent.context.providers.callers"
local function loc(path, line)
  return {
    uri = vim.uri_from_fname(path),
    range = { start = { line = line - 1, character = 1 }, ["end"] = { line = line - 1, character = 4 } },
  }
end
vim.fn.writefile(
  { "package p", "", "func Use() int {", "	return A() + A()", "}", "", "func Use2() int {", "	return A()", "}" },
  gdir .. "/use.go"
)
local abuf = K.open "a.go"
local atarget = require("agent.context.target").of_range(abuf, "function", 3, 5, "A")
local lines = callers.format({
  loc(gdir .. "/use.go", 4),
  loc(gdir .. "/use.go", 8),
  loc(gdir .. "/use.go", 9),
  loc(gdir .. "/a.go", 4),
  loc(gdir .. "/new.go", 4),
}, atarget, 6)
eq(
  "callers: a call from inside the target itself is dropped",
  vim.tbl_filter(function(l)
    return l:find("a.go:4", 1, true)
  end, lines),
  {}
)
eq("callers: at most two per file", #vim.tbl_filter(function(l)
  return l:find("use.go", 1, true)
end, lines), 2)
ok("callers: path, line and the code", #vim.tbl_filter(function(l)
  return l:find("use.go:4  return A() + A()", 1, true)
end, lines) == 1)
eq("callers: other files in path order", { lines[1]:match "^(%S+):", lines[2]:match "^(%S+):" }, { "new.go", "use.go" })
eq(
  "callers: the limit is respected",
  #callers.format({ loc(gdir .. "/use.go", 4), loc(gdir .. "/new.go", 4) }, atarget, 1),
  1
)
eq(
  "callers: no name, no LSP: nothing to ask",
  (function()
    local r = "unset"
    callers.collect({ buf = abuf, first = 3, last = 5 }, function(t)
      r = t
    end)
    return r
  end)(),
  nil
)
local actions = require "agent.actions"
ok(
  "actions: refactor asks for callers and history, fix does not",
  vim.tbl_contains(actions.get("refactor").context, "callers")
    and vim.tbl_contains(actions.get("refactor").context, "gitlog")
    and not vim.tbl_contains(actions.get("fix").context, "callers")
)

K.finish()
