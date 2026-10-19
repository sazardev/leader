-- Tests of the merge conflict assistant (agent/conflict): the markers and the free resolutions (pure), the files and the
-- story git tells (a REAL merge in a temporary repository), and the flows with a fake model: trivial, one conflict, all of
-- them (asked once, one proposal each, accepted from the queue), the file marked resolved. No network, no tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local parse = require "agent.conflict.parse"

-- ── pure: markers and free resolutions ──────────────────────────────────────
local text = {
  "keep",
  "<<<<<<< HEAD",
  "a",
  "=======",
  "b",
  ">>>>>>> feature",
  "middle",
  "<<<<<<< HEAD",
  "same",
  "||||||| base",
  "old",
  "=======",
  "same",
  ">>>>>>> feature",
  "<<<<<<< HEAD",
  "old",
  "||||||| base",
  "old",
  "=======",
  "new",
  ">>>>>>> feature",
}
local hunks = parse.parse(text)
eq("parse: three conflicts", #hunks, 3)
eq("parse: lines and labels", { hunks[1].first, hunks[1].last, hunks[1].ours_label, hunks[1].theirs_label }, { 2, 6, "HEAD", "feature" })
eq("parse: both sides", { hunks[1].ours, hunks[1].theirs }, { { "a" }, { "b" } })
eq("parse: diff3 keeps the ancestor", hunks[2].base, { "old" })
eq("parse: and no ancestor without it", hunks[1].base, nil)
eq("trivial: two different changes are not trivial", parse.trivial(hunks[1]), nil)
eq("trivial: the same change on both sides", { parse.trivial(hunks[2]) }, { { "same" }, "both sides made the same change" })
eq("trivial: only theirs changed", { parse.trivial(hunks[3]) }, { { "new" }, "only theirs changed it" })
eq("trivial: whitespace at the end does not count", (parse.trivial { ours = { "x " }, theirs = { "x" } }) ~= nil, true)
local out, resolved, left = parse.resolve_trivial(text)
eq("resolve_trivial: two of three, bottom up", { resolved, left }, { 2, 1 })
eq("resolve_trivial: what is left is the real conflict", #parse.parse(out), 1)
eq("resolve_trivial: the text around is intact", { out[1], out[#out - 1] or out[#out] }, { "keep", out[#out - 1] or out[#out] })
ok("has_markers", parse.has_markers(text) and not parse.has_markers { "a", "b" })

-- ── a real merge conflict ───────────────────────────────────────────────────
local FAKE = K.fake()
local settings = require("core.settings").agent
settings.verify.enabled = false
local dir = K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["calc.go"] = {
    "package p",
    "",
    "func Total(a, b int) int {",
    "\treturn a + b",
    "}",
    "",
    "func Name() string {",
    "\treturn \"calc\"",
    "}",
  },
}
local function git(...)
  local res = vim.system({ "git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false", ... }, { text = true }):wait()
  return res.code, res.stdout .. res.stderr
end
local function write(name, lines)
  vim.fn.writefile(lines, dir .. "/" .. name)
end
local base_lines = vim.fn.readfile(dir .. "/calc.go")
git("branch", "-M", "main")
git("checkout", "-qb", "feature")
local feature = vim.deepcopy(base_lines)
feature[4] = "\treturn (a + b) * 2"
feature[8] = "\treturn \"calculator\""
write("calc.go", feature)
git("commit", "-qam", "feature: double the total and rename")
git("checkout", "-q", "main")
local main = vim.deepcopy(base_lines)
main[4] = "\treturn a + b + 1"
main[8] = "\treturn \"calc v2\""
write("calc.go", main)
git("commit", "-qam", "main: add a fee and bump the name")
local code = git("merge", "feature")
eq("setup: the merge conflicts", code, 1)

local cgit = require "agent.conflict.git"
local files
cgit.files(dir, function(f)
  files = f
end)
K.wait(function()
  return files ~= nil
end, 4000)
eq("git: the unmerged file", vim.tbl_map(function(f)
  return f.path
end, files), { "calc.go" })
eq("git: the other side of the operation", select(2, cgit.theirs(dir)), "merge")
local story
cgit.context(dir, "calc.go", function(t)
  story = t
end)
K.wait(function()
  return story ~= nil
end, 4000)
ok("context: names the operation and the branch", story:find("merge is in progress on main", 1, true) ~= nil)
ok("context: what ours did", story:find("main: add a fee", 1, true) ~= nil)
ok("context: what theirs did", story:find("feature: double the total", 1, true) ~= nil)
ok("context: what each changed against the ancestor", story:find("What ours changed", 1, true) and story:find("What theirs changed", 1, true))
ok("context: with the changes themselves", story:find("a + b + 1", 1, true) ~= nil and story:find("(a + b) * 2", 1, true) ~= nil)

-- ── the flows ───────────────────────────────────────────────────────────────
local conflict = require "agent.conflict"
local replace = require "agent.output.replace"
local buf = K.open "calc.go"
eq("hunks: both conflicts are there", #conflict.hunks(buf), 2)
K.at(1)
eq("near: from outside, the next one below", conflict.near(conflict.hunks(buf), 1).first, conflict.hunks(buf)[1].first)

-- nothing trivial here: the two sides changed the same lines differently
conflict.trivial()
ok("trivial: says there is nothing trivial", K.note(FAKE):find("none trivial", 1, true) ~= nil)
eq("trivial: and changes nothing", #conflict.hunks(buf), 2)

-- one conflict, asked once, one proposal
FAKE.answer = "yes"
FAKE.text = function()
  return "```go\nfunc Total(a, b int) int {\n\treturn (a+b)*2 + 1\n}\n```"
end
K.at(conflict.hunks(buf)[1].first)
conflict.resolve "here"
K.wait(function()
  return FAKE.calls > 0 -- the story is read from git first (asynchronously)
end, 4000)
K.idle()
ok("resolve: one request", FAKE.calls == 1)
local req = FAKE.req
ok("resolve: the target is the conflict with its markers", req.prompt:find("<<<<<<<", 1, true) ~= nil and req.prompt:find(">>>>>>>", 1, true) ~= nil)
ok("resolve: <merge> tells the story", req.prompt:find("<merge>", 1, true) and req.prompt:find("main: add a fee", 1, true) and req.prompt:find("feature: double", 1, true))
ok("resolve: and which side is which", req.prompt:find("ours is `HEAD`", 1, true) ~= nil)
ok("resolve: the task asks for no markers", req.system:find("NO conflict markers", 1, true) ~= nil)
eq("resolve: one proposal waits", #replace.pending(), 1)
ok("resolve: the buffer is untouched until it is accepted", #conflict.hunks(buf) == 2)
replace.accept()
eq("resolve: accepting leaves one conflict", #conflict.hunks(buf), 1)
ok("resolve: the merged code is in", table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("(a+b)*2 + 1", 1, true) ~= nil)

-- all of them: the free ones first, the rest as a batch
FAKE.calls = 0
FAKE.text = function()
  return "```go\nfunc Name() string {\n\treturn \"calculator v2\"\n}\n```"
end
conflict.resolve "all"
K.wait(function()
  return #require("agent.batch").active() == 0 and #replace.pending() > 0
end, 6000)
eq("all: one request for the one conflict left", FAKE.calls, 1)
ok("all: the proposal is waiting in the queue", #replace.pending() == 1)
replace.accept()
eq("all: no conflict left", #conflict.hunks(buf), 0)
ok("all: the file is clean", not parse.has_markers(vim.api.nvim_buf_get_lines(buf, 0, -1, false)))

-- marked resolved: git add, after asking
vim.cmd "silent write"
FAKE.answer = "yes"
conflict.stage()
K.wait(function()
  return select(2, git("diff", "--name-only", "--diff-filter=U")):gsub("%s", "") == ""
end, 4000)
eq("stage: git no longer lists it as unmerged", (select(2, git("diff", "--name-only", "--diff-filter=U")):gsub("%s", "")), "")
FAKE.answer = "no"

-- a file with markers cannot be marked
local b2 = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(b2, dir .. "/other.txt")
vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "<<<<<<< a", "x", "=======", "y", ">>>>>>> b" })
vim.api.nvim_set_current_buf(b2)
vim.bo[b2].modified = false
conflict.stage()
ok("stage: refuses while markers are left", K.note(FAKE):find("markers are still", 1, true) ~= nil)

-- trivial on a buffer where both sides agree
vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "top", "<<<<<<< a", "same", "=======", "same", ">>>>>>> b", "end" })
conflict.trivial()
eq("trivial: resolved with no model", vim.api.nvim_buf_get_lines(b2, 0, -1, false), { "top", "same", "end" })
ok("trivial: and says so", K.note(FAKE):find("resolved with no model", 1, true) ~= nil)

K.finish()
