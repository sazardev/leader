-- Tests of the git sync actions (nvim/lua/gitsync, <leader>GP push, <leader>Gu pull, <leader>GF fetch): the exact
-- commands (pure), the guards and a real push/pull/fetch against a local bare repository. Hermetic: temporary
-- repositories, no network, no credentials.
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
local sync = require "gitsync"

-- ── commands (pure) ──────────────────────────────────────────────────────────

eq("push: with upstream, plain push", sync.command("push", { name = "main", upstream = "origin/main" }), "git push")
eq(
  "push: the first one sets the upstream",
  sync.command("push", { name = "feature/x" }),
  "git push -u origin " .. vim.fn.shellescape "feature/x"
)
eq("pull: only fast-forwards", sync.command("pull", { name = "main", upstream = "origin/main" }), "git pull --ff-only")
eq(
  "pull: without upstream it goes to origin for the same branch",
  sync.command("pull", { name = "main" }),
  "git pull --ff-only origin " .. vim.fn.shellescape "main"
)
eq("fetch: every remote, pruned", sync.command("fetch", { name = "" }), "git fetch --all --prune")

-- ── guards and the terminal ──────────────────────────────────────────────────

local term_calls = {}
package.loaded["utils.terminal"] = {
  run = function(cmd, dir)
    term_calls[#term_calls + 1] = { cmd, dir }
  end,
}
local real_git = require "commit.git"
local git_stub = {}
package.loaded["commit.git"] = git_stub

git_stub.root = function()
  return nil
end
eq("run: outside a repository warns", { sync.push(), notes[#notes] }, { false, "warn: Git: not inside a repository" })

git_stub.root = function()
  return "/p"
end
git_stub.branch = function()
  return { name = "HEAD", ahead = 0, behind = 0 }
end
eq(
  "run: a detached HEAD is not pushed",
  { sync.push(), notes[#notes] },
  { false, "warn: Git: no branch to push (detached HEAD or no commits yet)" }
)

git_stub.branch = function()
  return { name = "main", upstream = "origin/main", ahead = 0, behind = 0 }
end
eq("run: push in the terminal from the repository root", { sync.push(), term_calls[1] }, { true, { "git push", "/p" } })
eq(
  "run: pull in the terminal from the repository root",
  { sync.pull(), term_calls[2] },
  { true, { "git pull --ff-only", "/p" } }
)
git_stub.branch = function()
  return { name = "HEAD" }
end
eq(
  "run: fetch still works from a detached HEAD",
  { sync.fetch(), term_calls[3] },
  { true, { "git fetch --all --prune", "/p" } }
)
package.loaded["commit.git"] = real_git

-- ── real push / pull / fetch against a local bare origin ─────────────────────

local base = vim.fn.tempname()
vim.fn.mkdir(base, "p")
local function git(cwd, ...)
  local res = vim.system(vim.list_extend({ "git" }, { ... }), { cwd = cwd, text = true }):wait()
  return vim.trim(res.stdout or ""), res.code
end
local function shell(cmd, cwd)
  local res = vim.system({ "sh", "-c", cmd }, { cwd = cwd, text = true }):wait()
  return res.code, vim.trim((res.stdout or "") .. (res.stderr or ""))
end
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end
local function configure(dir)
  git(dir, "config", "user.name", "Test")
  git(dir, "config", "user.email", "test@example.com")
end

local origin, work, clone = base .. "/origin.git", base .. "/work", base .. "/clone"
git(base, "init", "--bare", "-b", "main", origin)
git(base, "init", "-b", "main", work)
configure(work)
git(work, "remote", "add", "origin", origin)
write(work .. "/main.go", { "package main", "", "func main() {}", "" })
git(work, "add", "-A")
git(work, "commit", "-q", "-m", "feat: first")
local first = git(work, "rev-parse", "HEAD")
eq("repo: a new branch has no upstream", real_git.branch(work).upstream, nil)

local code = shell(sync.command("push", real_git.branch(work)), work)
eq("push: the first push succeeds", code, 0)
eq("push: the upstream is tracked afterwards", real_git.branch(work).upstream, "origin/main")
eq("push: the remote has the commit", git(work, "rev-parse", "origin/main"), first)

git(base, "clone", "-q", origin, clone)
configure(clone)
write(clone .. "/main.go", { "package main", "", "func main() { println(\"x\") }", "" })
git(clone, "commit", "-q", "-am", "feat: second")
git(clone, "push", "-q")
local second = git(clone, "rev-parse", "HEAD")
code = select(1, shell(sync.command("pull", real_git.branch(work)), work))
local pulled = git(work, "rev-parse", "HEAD")
eq("pull: fast-forwards to the new commit", { code, pulled }, { 0, second })

git(clone, "checkout", "-q", "-b", "feature")
git(clone, "push", "-q", "-u", "origin", "feature")
code = select(1, shell(sync.command("fetch", real_git.branch(work)), work))
local fetched = git(work, "rev-parse", "origin/feature")
eq("fetch: brings the new remote branch", { code, fetched }, { 0, second })

vim.fn.delete(base, "rf")
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd(fails == 0 and "qa!" or "cquit 1")
