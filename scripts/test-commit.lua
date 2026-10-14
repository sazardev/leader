-- Tests for the commit panel (lua/commit): Conventional Commits parsing, git reads/actions on a temporary
-- repo, and the whole panel (list, stage/unstage, AI draft with a fake backend, commit and amend).
-- Hermetic: repo in a temporary directory, in-memory agent state, no network or tokens.
local fails = 0
local function print(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), "\t"), "\n")
end
local function eq(name, got, want)
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. "\n  got:  " .. vim.inspect(got) .. "\n  want: " .. vim.inspect(want))
  end
end

vim.o.columns, vim.o.lines = 130, 40
local conv = require "commit.conventional"

-- ── Conventional Commits (pure) ──────────────────────────────────────────────
eq(
  "split: type, scope, breaking and subject",
  conv.split "feat(api)!: add x",
  { type = "feat", scope = "api", breaking = true, subject = "add x" }
)
eq("split: no scope", conv.split "fix: bug", { type = "fix", scope = nil, breaking = false, subject = "bug" })
eq("split: missing space after the colon", conv.split "fix:bug", nil)
eq("split: not conventional", conv.split "Update stuff", nil)
eq("parse_header: valid", (conv.parse_header "feat(commit): new panel").scope, "commit")
eq("parse_header: unknown type", select(2, conv.parse_header "wip: something"), "unknown type `wip`")
eq("parse_header: empty subject", select(2, conv.parse_header "feat: ") ~= nil, true)
eq(
  "parse_header: too long",
  select(2, conv.parse_header("feat: " .. ("x"):rep(80))):find("max 72", 1, true) ~= nil,
  true
)
eq("check: empty", conv.check("").state, "empty")
eq("check: type without subject", conv.check("feat(x): ").state, "incomplete")
eq(
  "check: ok",
  { conv.check("fix(ui): fix border edges").state, conv.check("fix(ui): fix border edges").len },
  { "ok", 25 }
)
eq("check: type error", conv.check("nope: x").state, "error")
eq(
  "rewrite: changes the type and keeps scope and subject",
  conv.rewrite("feat(ui): border", { type = "fix" }),
  "fix(ui): border"
)
eq("rewrite: changes the scope", conv.rewrite("feat(ui): border", { scope = "core" }), "feat(core): border")
eq("rewrite: removes the scope", conv.rewrite("feat(ui): border", { scope = false }), "feat: border")
eq("rewrite: template from scratch", conv.rewrite("", { type = "docs" }), "docs: ")
eq("suggest_type: docs only", conv.suggest_type { "README.md", "docs/a.md" }, "docs")
eq("suggest_type: mix → nil", conv.suggest_type { "README.md", "src/a.go" }, nil)
eq(
  "history_scopes: from most to least used",
  conv.history_scopes "feat(a): x\nfix(b): y\nfeat(a): z\nchore: q",
  { "a", "b" }
)
eq("clean_message: no fences or quotes", conv.clean_message "```\nfeat: x\n```", { "feat: x" })

-- ── temporary repo ────────────────────────────────────────────────────────────
local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")
local function sh(...)
  local res = vim.system(vim.list_extend({ "git" }, { ... }), { cwd = repo, text = true }):wait()
  return vim.trim(res.stdout or "")
end
local function write(name, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(repo .. "/" .. name, ":h"), "p")
  vim.fn.writefile(lines, repo .. "/" .. name)
end
sh("init", "-q", "-b", "main")
sh("config", "user.email", "t@t")
sh("config", "user.name", "t")
sh("config", "commit.gpgsign", "false")
write("a.lua", { "one", "two" })
write("b.lua", { "x" })
sh("add", "-A")
sh("commit", "-q", "-m", "chore: base")
write("a.lua", { "one", "TWO", "three" }) -- will be staged
write("b.lua", { "x", "y" }) -- will stay unstaged
write("docs/c.md", { "new" }) -- untracked
sh("add", "a.lua")

local git = require "commit.git"
local entries = git.status(repo)
eq(
  "status: staged first, then unstaged, then new",
  vim.tbl_map(function(e)
    return e.path .. ":" .. e.letter .. ":" .. tostring(e.staged)
  end, entries),
  { "a.lua:M:true", "b.lua:M:false", "docs/:?:false" }
)
eq("status: +/− of what is staged", { entries[1].adds, entries[1].dels }, { 2, 1 })
eq("status: +/− of what is unstaged", { entries[2].adds, entries[2].dels }, { 1, 0 })
eq("branch: no upstream", { git.branch(repo).name, git.branch(repo).upstream }, { "main", nil })
git.stage(repo, { "b.lua" })
eq("stage: b.lua becomes staged", git.status(repo)[2].staged, true)
git.unstage(repo, { "b.lua" })
eq("unstage: goes back to unstaged", git.status(repo)[2].staged, false)
write("a.lua", { "one", "TWO", "three", "four" })
eq("status: staged with more unstaged changes = partial", git.status(repo)[1].partial, true)
sh("add", "a.lua")

-- ── the panel ─────────────────────────────────────────────────────────────────
local notes = {}
vim.notify = function(msg, level)
  notes[#notes + 1] = { msg = msg, level = level }
end
local function last_note()
  return notes[#notes] and notes[#notes].msg or ""
end

-- fake backend for the draft (in-memory state: does not touch your agent.json)
local state = require "agent.state"
local real_get, real_set = state.get, state.set
local store = { backend = "fakecommit" }
state.get = function(k)
  return store[k]
end
state.set = function(k, v)
  store[k] = v
end
local FAKE = { cmd = { "printf", "%s", "feat(editor): add the commit panel\n\n- shows what is committed" } }
require("agent.backends").register("fakecommit", {
  name = "fakecommit",
  label = "Fake",
  available = function()
    return true
  end,
  models = function(cb)
    cb {}
  end,
  build = function(req)
    FAKE.req = req
    return { cmd = FAKE.cmd, cwd = vim.fn.tempname():match "^(.*)/" or "/tmp" }
  end,
  parser = function()
    local buf = {}
    return {
      feed = function(chunk)
        buf[#buf + 1] = chunk
        return chunk
      end,
      finish = function(code)
        if code ~= 0 then
          return { ok = false, err = "boom" }
        end
        return { ok = true, text = table.concat(buf), usage = { tokens_in = 100, tokens_out = 20, cost = 0.0004 } }
      end,
    }
  end,
})

vim.cmd("cd " .. vim.fn.fnameescape(repo))
local panel = require "commit.panel"

local function wins_open()
  local n = 0
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      n = n + 1
    end
  end
  return n
end
local function float_bufs()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      out[vim.bo[vim.api.nvim_win_get_buf(w)].filetype] = vim.api.nvim_win_get_buf(w)
    end
  end
  return out
end
local function title_of(buf)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      local t = vim.api.nvim_win_get_config(w).title
      local parts = {}
      for _, c in ipairs(type(t) == "table" and t or {}) do
        parts[#parts + 1] = c[1]
      end
      return table.concat(parts)
    end
  end
end
local function press(buf, lhs, mode)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode or "n")) do
    local function key(x)
      return vim.api.nvim_replace_termcodes(x, true, true, true):lower()
    end
    if key(m.lhs) == key(lhs) then
      return m.callback()
    end
  end
  error("no mapping " .. lhs)
end
local function wait(cond, ms)
  return vim.wait(ms or 5000, cond, 25)
end

panel.open()
local fb = float_bufs()
eq("panel: three floats (files, message and agent line)", wins_open(), 3)
local lines = vim.api.nvim_buf_get_lines(fb.commitfiles, 0, -1, false)
eq(
  "panel: header for what DOES get committed",
  lines[1]:find("Staged · 1 file — goes in the commit", 1, true) ~= nil,
  true
)
eq(
  "panel: header for what does NOT get committed",
  lines[3]:find("Not staged · 2 — NOT included", 1, true) ~= nil,
  true
)
eq("panel: file rows with mark and letter", {
  lines[2]:find("● M", 1, true) ~= nil,
  lines[4]:find("○ M", 1, true) ~= nil,
  lines[5]:find("○ ?", 1, true) ~= nil,
}, { true, true, true })
eq("panel: title with the branch", title_of(fb.commitfiles):find("main", 1, true) ~= nil, true)
eq(
  "panel: with something staged the focus goes to the message",
  vim.bo[vim.api.nvim_get_current_buf()].filetype,
  "gitcommit"
)
eq(
  "panel: empty message → title with the expected format",
  title_of(fb.gitcommit):find("type(scope): subject", 1, true) ~= nil,
  true
)

-- agent line: announces what it will read and with which model BEFORE spending anything
local function ai_text()
  return vim.api.nvim_buf_get_lines(fb.commitstatus, 0, 1, false)[1] or ""
end
local before = ai_text()
eq("panel: the agent announces the model and the files it will read", {
  before:find("fakecommit", 1, true) ~= nil,
  before:find("reads 1 file", 1, true) ~= nil,
  before:find("Ctrl-g to draft", 1, true) ~= nil,
}, { true, true, true })

-- stage from the list
vim.api.nvim_set_current_win(vim.fn.bufwinid(fb.commitfiles))
vim.api.nvim_win_set_cursor(0, { 4, 0 })
press(fb.commitfiles, "<Space>")
lines = vim.api.nvim_buf_get_lines(fb.commitfiles, 0, -1, false)
eq("panel: ⎵ stages the file under the cursor", lines[1]:find("Staged · 2 files", 1, true) ~= nil, true)
eq("panel: after staging, the AI announcement counts 2 files", ai_text():find("reads 2 files", 1, true) ~= nil, true)
press(fb.commitfiles, "u")
eq(
  "panel: u unstages everything",
  vim.api.nvim_buf_get_lines(fb.commitfiles, 0, -1, false)[1]:find("Staged · 0 files", 1, true) ~= nil,
  true
)
eq(
  "panel: with nothing staged the list explains it",
  vim.api.nvim_buf_get_lines(fb.commitfiles, 0, -1, false)[2]:find("nothing staged yet", 1, true) ~= nil,
  true
)
press(fb.commitfiles, "a")
eq(
  "panel: a stages everything",
  vim.api.nvim_buf_get_lines(fb.commitfiles, 0, -1, false)[1]:find("Staged · 3 files", 1, true) ~= nil,
  true
)
press(fb.commitfiles, "u")
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
press(fb.commitfiles, "a")
press(fb.commitfiles, "u")
vim.api.nvim_win_set_cursor(0, { 3, 0 })
git.stage(repo, { "a.lua" })
panel.close()
eq("panel: close closes the windows", wins_open(), 0)

-- AI draft
panel.open { ai = true }
fb = float_bufs()
eq(
  "panel: <leader>Gm starts the draft",
  wait(function()
    return ai_text():find("drafted by", 1, true) ~= nil
  end),
  true
)
eq(
  "AI: the agent's message fills the window",
  vim.api.nvim_buf_get_lines(fb.gitcommit, 0, -1, false),
  { "feat(editor): add the commit panel" } -- header only: the model returns a body and it is ignored
)
eq(
  "AI: the title validates the draft (✔ type(scope) and length)",
  title_of(fb.gitcommit):find("✔ feat(editor)", 1, true) ~= nil,
  true
)
eq(
  "AI: after the draft the model, tokens and cost are shown",
  { ai_text():find("100→20 tok", 1, true) ~= nil, ai_text():find("$0.0004", 1, true) ~= nil },
  { true, true }
)
eq("AI: what is sent carries branch, files, compact diff and the type list", {
  FAKE.req.prompt:find("<branch>", 1, true) ~= nil,
  FAKE.req.prompt:find("<files>", 1, true) ~= nil,
  FAKE.req.prompt:find("<diff>\n## ", 1, true) ~= nil,
  FAKE.req.prompt:find("diff --git", 1, true) == nil,
  FAKE.req.system:find("feat | fix", 1, true) ~= nil,
}, { true, true, true, true, true })
eq("AI: instructions in English, a single line and always in English", {
  FAKE.req.system:find("ALWAYS English", 1, true) ~= nil,
  FAKE.req.system:find("header line only", 1, true) ~= nil,
  FAKE.req.system:find("Spanish", 1, true) == nil,
}, { true, true, true })
eq(
  "AI: the draft uses the light tier (commit)",
  require("agent.selection").current({ name = "commit", tier = "light" }).tier,
  "light"
)

-- type and scope from the panel
local picks = { { "fix" }, { "ui" } }
local real_select = vim.ui.select
vim.ui.select = function(items, opts, cb)
  local want = table.remove(picks, 1)[1]
  for i, it in ipairs(items) do
    if it == want or (type(it) == "table" and it[1] == want) then
      return cb(it, i)
    end
  end
  cb(nil)
end
press(fb.gitcommit, "<C-t>")
eq(
  "type: Ctrl-t changes the type and keeps the rest",
  vim.api.nvim_buf_get_lines(fb.gitcommit, 0, 1, false)[1],
  "fix(editor): add the commit panel"
)
vim.ui.select = real_select

-- the body you write yourself travels with the commit
local msg_lines = vim.api.nvim_buf_get_lines(fb.gitcommit, 0, -1, false)
vim.api.nvim_buf_set_lines(fb.gitcommit, 0, -1, false, vim.list_extend(msg_lines, { "", "- shows what is committed" }))

-- commit
eq("before committing, HEAD is the base commit", sh("log", "-1", "--format=%s"), "chore: base")
vim.cmd "stopinsert"
press(fb.gitcommit, "<C-s>", "n")
eq(
  "commit: the commit is made and the panel closes",
  wait(function()
    return wins_open() == 0
  end),
  true
)
eq("commit: commit subject", sh("log", "-1", "--format=%s"), "fix(editor): add the commit panel")
eq("commit: the body travels", sh("log", "-1", "--format=%b"), "- shows what is committed")
eq("commit: only what is staged (b.lua and docs/ stay out)", sh("show", "--name-only", "--format=", "HEAD"), "a.lua")
eq(
  "commit: notice with hash, files and +/−",
  last_note():find("Committed", 1, true) ~= nil and last_note():find("1 file +", 1, true) ~= nil,
  true
)

-- validations: an invalid subject and nothing staged do NOT commit
git.stage(repo, { "b.lua" })
panel.open()
fb = float_bufs()
vim.api.nvim_buf_set_lines(fb.gitcommit, 0, -1, false, { "wip: nope" })
press(fb.gitcommit, "<C-s>")
eq(
  "validation: an unknown type does not commit",
  { sh("log", "-1", "--format=%s"), last_note():find("unknown type", 1, true) ~= nil },
  { "fix(editor): add the commit panel", true }
)
vim.api.nvim_buf_set_lines(fb.gitcommit, 0, -1, false, { "feat(x): ok" })
press(fb.gitcommit, "<C-s>")
eq(
  "commit 2: b.lua",
  wait(function()
    return sh("log", "-1", "--format=%s") == "feat(x): ok" and wins_open() == 0
  end),
  true
)

-- AI with an error: the panel shows it and stays usable
write("a.lua", { "again" })
sh("add", "a.lua")
FAKE.cmd = { "sh", "-c", "exit 3" }
panel.open { ai = true }
fb = float_bufs()
eq(
  "AI with error: announced on the agent line",
  wait(function()
    return ai_text():find("AI failed", 1, true) ~= nil
  end),
  true
)
eq(
  "AI with error: the message stays empty and the panel open",
  { vim.api.nvim_buf_get_lines(fb.gitcommit, 0, -1, false), wins_open() },
  { { "" }, 3 }
)
panel.close()

-- nothing staged
sh("reset", "-q")
panel.open()
fb = float_bufs()
eq("nothing staged: focus on the list", vim.bo[vim.api.nvim_get_current_buf()].filetype, "commitfiles")
vim.api.nvim_buf_set_lines(fb.gitcommit, 0, -1, false, { "feat(x): nothing" })
press(fb.gitcommit, "<C-s>")
eq(
  "nothing staged: does not commit and warns",
  { sh("log", "-1", "--format=%s"), last_note():find("Nothing staged", 1, true) ~= nil },
  { "feat(x): ok", true }
)
panel.close()

-- amend: the last commit's message arrives preloaded
require("commit").amend()
fb = float_bufs()
eq(
  "amend: preloaded message and title",
  { vim.api.nvim_buf_get_lines(fb.gitcommit, 0, 1, false)[1], title_of(fb.commitfiles):find("Amend", 1, true) ~= nil },
  { "feat(x): ok", true }
)
vim.api.nvim_buf_set_lines(fb.gitcommit, 0, 1, false, { "feat(x): ok again" })
press(fb.gitcommit, "<C-s>")
eq(
  "amend: rewrites the last commit",
  wait(function()
    return sh("log", "-1", "--format=%s") == "feat(x): ok again" and wins_open() == 0
  end),
  true
)
eq("amend: does not create a new commit", sh("rev-list", "--count", "HEAD"), "3")

-- clean tree
sh("reset", "-q", "--hard")
sh("clean", "-fdq")
panel.open()
eq("clean tree: opens nothing", { wins_open(), last_note():find("Nothing to commit", 1, true) ~= nil }, { 0, true })

-- ── compact diff for the model ─────────────────────────────────────────────
write("pkg/big.lua", vim.fn.map(vim.fn.range(1, 400), "'line ' . v:val . ' of a very long file'"))
write("pkg/small.lua", { "local x = 1" })
write("deps.lock", { "a", "b" })
sh("add", "-A")
local compact, total, cut = git.diff_for_ai(repo, 1500)
eq("compact diff: no git headers, one `## path` per file", {
  compact:find("diff --git", 1, true) == nil and compact:find("\nindex ", 1, true) == nil,
  compact:find("## pkg/small.lua (new)", 1, true) ~= nil,
  compact:find("## pkg/big.lua (new)", 1, true) ~= nil,
}, { true, true, true })
eq(
  "compact diff: lockfile listed but without its diff",
  compact:find("## deps.lock (new) (generated, diff omitted)", 1, true) ~= nil,
  true
)
eq(
  "compact diff: the huge file is cut and flagged",
  { cut, total > 1500, compact:find("[… cut]", 1, true) ~= nil },
  { true, true, true }
)
eq(
  "compact diff: the small one fits whole even if the big one is cut",
  compact:find("+local x = 1", 1, true) ~= nil,
  true
)
eq("compact diff: respects the cap (with the headers)", #compact < 1500 + 400, true)
eq("numstat: one line per file with +/−", git.staged_numstat(repo):find("pkg/small.lua +1 -0", 1, true) ~= nil, true)
sh("reset", "-q", "--hard")
sh("clean", "-fdq")

-- ── automatic commit (<leader>GM) ───────────────────────────────────────────
local auto = require "commit.auto"
local function head()
  return sh("log", "-1", "--format=%s")
end
-- launches the automatic commit and waits for its final notice (the commit and the notice come after the AI)
local function run_auto(final)
  notes = {}
  auto.run()
  return wait(function()
    return last_note():find(final, 1, true) ~= nil
  end)
end
eq("auto: clean tree, does nothing", run_auto "nothing to commit", true)

-- nothing staged: stages everything except sensitive files, and ONLY the message header
FAKE.cmd = { "printf", "%s", "feat(core): add x\n\nbody that must be ignored" }
write("a.lua", { "one", "TWO" })
write("x.lua", { "new" })
write(".env", { "SECRET=1" })
eq(
  "auto: commits in the background with the agent's message",
  run_auto "Committed" and head() == "feat(core): add x",
  true
)
eq("auto: sensitive files stay out, the rest goes in", {
  sh("show", "--name-only", "--format=", "HEAD"),
  sh("status", "--porcelain"),
}, { "a.lua\nx.lua", "?? .env" })
eq("auto: header only (the model's body is ignored)", sh("log", "-1", "--format=%b"), "")
eq("auto: the notice carries hash, message, files, model and cost, and what it left out", {
  last_note():find("Committed", 1, true) ~= nil,
  last_note():find("feat(core): add x · 2 files", 1, true) ~= nil,
  last_note():find("fakecommit", 1, true) ~= nil,
  last_note():find("$0.0004", 1, true) ~= nil,
  last_note():find("left out: .env", 1, true) ~= nil,
}, { true, true, true, true, true })
eq("auto: the prompt carries the branch and the rules in English", {
  FAKE.req.prompt:find("<branch>main</branch>", 1, true) ~= nil,
  FAKE.req.system:find("ALWAYS English", 1, true) ~= nil,
}, { true, true })

-- with something staged: only that
FAKE.cmd = { "printf", "%s", "fix(core): staged only" }
write("a.lua", { "one", "THREE" })
write("x.lua", { "new", "more" })
sh("add", "a.lua")
eq("auto: with staged files it commits only those", run_auto "Committed" and head() == "fix(core): staged only", true)
eq(
  "auto: what was unstaged stays unstaged",
  { sh("show", "--name-only", "--format=", "HEAD"), sh("status", "--porcelain") },
  {
    "a.lua",
    "M x.lua\n?? .env",
  }
)

-- invalid header: does not commit and gives the index back as it was
FAKE.cmd = { "printf", "%s", "wip: nope" }
eq("auto: invalid header, nothing committed and files unstaged again", run_auto "is not valid", true)
eq(
  "auto: after failing, the index is left empty",
  { head(), sh("diff", "--cached", "--name-only") },
  { "fix(core): staged only", "" }
)

-- the AI fails
FAKE.cmd = { "sh", "-c", "exit 3" }
auto.run()
eq("auto: if the AI fails, it warns and leaves everything as it was", wait(function()
  return last_note():find("AI failed", 1, true) ~= nil
end) and sh("diff", "--cached", "--name-only") == "", true)

-- a hook rejects the commit
FAKE.cmd = { "printf", "%s", "feat(core): hook says no" }
vim.fn.writefile({ "#!/bin/sh", "echo rejected by hook >&2", "exit 1" }, repo .. "/.git/hooks/pre-commit")
vim.fn.setfperm(repo .. "/.git/hooks/pre-commit", "rwxr-xr-x")
auto.run()
eq("auto: if a hook rejects, it warns and undoes what it staged", wait(function()
  return last_note():find("rejected by hook", 1, true) ~= nil
end) and sh("diff", "--cached", "--name-only") == "" and head() == "fix(core): staged only", true)
os.remove(repo .. "/.git/hooks/pre-commit")

-- only sensitive files
sh("checkout", "-q", "--", "x.lua")
eq(
  "auto: only sensitive, warns and touches nothing",
  { run_auto "only sensitive files changed", sh("diff", "--cached", "--name-only") },
  { true, "" }
)

state.get, state.set = real_get, real_set
vim.fn.delete(repo, "rf")
print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
