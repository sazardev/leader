-- Tests of multi-file plans: locating the sites (pure and on a real project, by text), the plan prompt (signatures only),
-- validation against invented files and symbols, the plan panel, and the chained steps (each sees what the ones before it
-- proposed). Hermetic: a temporary Go project, a fake model.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local locate = require "agent.plan.locate"
local prompt = require "agent.plan.prompt"
local protocol = require "agent.protocol"

-- ── sites (pure) ────────────────────────────────────────────────────────────
local DECLS = {
  ["/p/a.go"] = {
    { name = "A", kind = "function", first = 1, last = 5, signature = "func A()" },
    { name = "B", kind = "function", first = 7, last = 12, signature = "func B()" },
  },
  ["/p/b_test.go"] = {
    { name = "TestB", kind = "function", first = 1, last = 9, signature = "func TestB(t *testing.T)" },
  },
  ["/p/c.go"] = { { name = "C", kind = "function", first = 1, last = 4, signature = "func C()" } },
}
local hits = {
  { abs = "/p/a.go", lnum = 2 },
  { abs = "/p/a.go", lnum = 3 },
  { abs = "/p/a.go", lnum = 9 },
  { abs = "/p/b_test.go", lnum = 4 },
  { abs = "/p/c.go", lnum = 1 },
  { abs = "/p/c.go", lnum = 99 },
}
local sites = locate.collapse(hits, function(abs)
  return DECLS[abs] or {}
end, "/p")
eq(
  "sites: hits collapse to the declaration that holds them",
  vim.tbl_map(function(s)
    return s.path .. ":" .. s.name .. "x" .. s.hits
  end, sites),
  { "a.go:Ax2", "a.go:Bx1", "b_test.go:TestBx1", "c.go:Cx1" }
)
eq("sites: a hit outside any declaration is dropped", #sites, 4)
eq("sites: tests are recognized", { sites[3].test, sites[1].test }, { true, false })
local ranked = locate.rank(sites, { max_files = 10, max_sites = 10 }, "/p/c.go")
eq(
  "rank: the seed's file first, tests last",
  vim.tbl_map(function(s)
    return s.path
  end, ranked),
  { "c.go", "a.go", "a.go", "b_test.go" }
)
eq("rank: capped by files", #locate.rank(sites, { max_files = 1, max_sites = 10 }, "/p/a.go"), 2)
eq("rank: capped by sites", #locate.rank(sites, { max_files = 10, max_sites = 3 }, "/p/a.go"), 3)

-- ── protocol and validation (pure) ──────────────────────────────────────────
local parsed =
  protocol.parse_plan "1|a.go|A|add the field\nnot a step\n2|a.go|B|use it\n3|ghost.go|Ghost|invented\n4|a.go|A|again"
eq("plan: n|path|symbol|what per line", #parsed, 4)
local valid = prompt.validate(parsed, sites)
eq(
  "validate: an invented file and a repeated step are dropped, the rest renumbered",
  vim.tbl_map(function(s)
    return s.n .. s.symbol
  end, valid),
  { "1A", "2B" }
)
local text = prompt.build(
  "add Done",
  { name = "A", kind = "function", path = "a.go" },
  { vim.tbl_extend("force", sites[1], { seed = true }), sites[2] }
)
ok(
  "prompt: instruction, seed and signatures",
  text:find("<instruction>\nadd Done", 1, true)
    and text:find("<seed>function A in a.go</seed>", 1, true)
    and text:find("L1 func A()   <- starts here", 1, true)
)
ok("prompt: the format rules are in the system prompt", prompt.SYSTEM:find("<n>|<path>|<symbol>", 1, true) ~= nil)

-- ── a real project ──────────────────────────────────────────────────────────
local dir = K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["internal/domain/note.go"] = {
    "package domain", -- 1
    "", -- 2
    "type Note struct {", -- 3
    "\tID    string", -- 4
    "\tTitle string", -- 5
    "}", -- 6
    "", -- 7
    "func NewNote(title string) *Note {", -- 8
    "\treturn &Note{Title: title}", -- 9
    "}", -- 10
  },
  ["internal/transport/dto.go"] = {
    "package transport",
    "",
    'import "example.com/p/internal/domain"',
    "",
    "type NoteResponse struct {",
    "\tID    string",
    "\tTitle string",
    "}",
    "",
    "func toNoteResponse(n *domain.Note) NoteResponse {",
    "\treturn NoteResponse{ID: n.ID, Title: n.Title}",
    "}",
  },
  ["internal/infrastructure/repo.go"] = {
    "package infrastructure",
    "",
    'import "example.com/p/internal/domain"',
    "",
    "func scan(id, title string) *domain.Note {",
    "\treturn &domain.Note{ID: id, Title: title}",
    "}",
  },
}
local FAKE = K.fake()
local settings = require("core.settings").agent
settings.verify.enabled = false
local replace = require "agent.output.replace"
local plan = require "agent.plan"

local buf = K.open "internal/domain/note.go"
K.at(3)
local seed = require("agent.context.target").resolve(buf, "type")
eq("seed: the type under the cursor", { seed.name, seed.kind }, { "Note", "class" })
local found, how
locate.sites(seed, dir, { max_files = 10, max_sites = 40 }, function(s, h)
  found, how = s, h
end)
K.wait(function()
  return found ~= nil
end, 6000)
eq("locate: without an LSP it greps", how, "grep")
local names = vim.tbl_map(function(s)
  return s.path:match "[^/]+$" .. ":" .. s.name
end, found)
table.sort(names)
eq(
  "locate: the declarations that mention Note, across layers",
  names,
  { "dto.go:toNoteResponse", "note.go:NewNote", "note.go:Note", "repo.go:scan" }
)
eq(
  "locate: the seed is marked and its file comes first",
  { found[1].seed, found[1].path },
  { true, "internal/domain/note.go" }
)

-- the plan call → panel → run (the panel is captured here, and exercised for real below)
local PLAN = table.concat({
  "1|internal/domain/note.go|Note|add the Done bool field",
  "2|internal/domain/note.go|NewNote|set Done explicitly to false",
  "3|internal/transport/dto.go|toNoteResponse|copy Done into the response",
  "4|internal/ghost.go|Ghost|a file that does not exist",
}, "\n")
local function target_of(prompt_text)
  return prompt_text:match "<target[^>]*>\n(.-)\n</target>"
end
FAKE.text = function(req)
  if req.system:find("Plan a code change", 1, true) then
    return PLAN
  end
  return "```go\n// changed by this step\n" .. (target_of(req.prompt) or "") .. "\n```"
end
local captured
require("agent.plan.ui").open = function(o)
  captured = o
end
local sel = require("agent.selection").current { name = "plan", tier = "main" }
plan.run(seed, "add a Done flag to notes", sel)
K.wait(function()
  return captured ~= nil
end, 8000)
eq("plan: one request for the plan", FAKE.calls, 1)
local pp = FAKE.req.prompt
ok(
  "plan: the prompt lists signatures, not bodies",
  pp:find("func NewNote(title string) *Note {", 1, true) ~= nil and not pp:find("return &Note{Title: title}", 1, true)
)
ok("plan: and the seed is marked", pp:find("L3 type Note struct {   <- starts here", 1, true) ~= nil)
ok(
  "plan: each site is its signature once (no repeated keyword)",
  pp:find("type type", 1, true) == nil and pp:find("func func", 1, true) == nil
)
eq("plan: three valid steps, the invented file dropped", #captured.steps, 3)
eq("plan: each step knows its declaration", captured.steps[3].site.name, "toNoteResponse")
ok(
  "plan: the panel's status line has the estimate",
  captured.status(captured.steps):find("3 steps", 1, true) ~= nil
    and captured.status(captured.steps):find("tokens", 1, true) ~= nil
)
eq("plan: unchecking a step changes the count", captured.status({ captured.steps[1] }):match "^(%d+ steps?)", "1 step")

-- run: steps become chained proposals
FAKE.calls, FAKE.reqs = 0, {}
captured.on_run(captured.steps)
K.wait(function()
  return #replace.pending() >= 3
end, 10000)
eq("run: three requests, one per step", FAKE.calls, 3)
eq("run: three proposals waiting", #replace.pending(), 3)
local labels = vim.tbl_map(function(p)
  return p.job.action.label
end, replace.pending())
eq("run: progress in the label", labels, { "plan 1/3", "plan 2/3", "plan 3/3" })
local r1, r2, r3 = FAKE.reqs[1].prompt, FAKE.reqs[2].prompt, FAKE.reqs[3].prompt
ok(
  "step 1: the plan marks it as THIS STEP",
  r1:find("1. internal/domain/note.go · Note — add the Done bool field   <- THIS STEP", 1, true) ~= nil
)
ok("step 1: nothing came before it", not r1:find("<earlier_steps>", 1, true))
ok(
  "step 2: it sees what step 1 proposed",
  r2:find("<earlier_steps>", 1, true) ~= nil
    and r2:find("Step 1 (internal/domain/note.go · Note), as proposed:", 1, true) ~= nil
    and r2:find("// changed by this step", 1, true) ~= nil
)
ok(
  "step 2: and the plan marks step 2",
  r2:find("2. internal/domain/note.go · NewNote — set Done explicitly to false   <- THIS STEP", 1, true) ~= nil
)
ok("step 3: sees steps 1 and 2", r3:find("Step 1 (", 1, true) ~= nil and r3:find("Step 2 (", 1, true) ~= nil)
ok("step 3: and the step's own text is the instruction", r3:find("copy Done into the response", 1, true) ~= nil)
ok("steps: framed as ONE step of a plan", FAKE.reqs[1].system:find("TASK apply ONE step", 1, true) ~= nil)
ok(
  "steps: a snapshot was announced",
  vim.tbl_contains(
    vim.tbl_map(function(n)
      return n:find("snapshot", 1, true) ~= nil
    end, FAKE.notes),
    true
  )
)
local files = {}
for _, p in ipairs(replace.pending()) do
  files[vim.fn.fnamemodify(p.job.target.path, ":t")] = true
end
eq("run: proposals in two files", vim.tbl_count(files), 2)

-- one queue, one accept: both files change
FAKE.answer = "yes"
require("agent.batch.queue").accept_all()
eq("accept all: no proposal left", #replace.pending(), 0)
local note_lines = vim.fn.getbufinfo({ bufname = dir .. "/internal/domain/note.go" })[1]
ok(
  "accept all: the domain file changed",
  note_lines ~= nil
    and table
        .concat(vim.api.nvim_buf_get_lines(vim.fn.bufnr(dir .. "/internal/domain/note.go"), 0, -1, false), "\n")
        :find("// changed by this step", 1, true)
      ~= nil
)

-- ── the plan panel, for real ────────────────────────────────────────────────
vim.cmd "silent! %bwipeout!"
package.loaded["agent.plan.ui"] = nil
local ui = require "agent.plan.ui"
local steps = {
  { n = 1, path = "a.go", symbol = "A", what = "add it", on = true },
  { n = 2, path = "b.go", symbol = "B", what = "use it", on = true },
}
local ran
ui.open {
  instruction = "add Done",
  steps = steps,
  status = function(chosen)
    return #chosen .. " chosen"
  end,
  on_run = function(chosen)
    ran = chosen
  end,
}
local pbuf = vim.api.nvim_get_current_buf()
local function press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
end
local lines = vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)
ok(
  "panel: a checkbox line per step",
  vim.tbl_contains(lines, "- [x] 1. `a.go` · **A** — add it")
    and vim.tbl_contains(lines, "- [x] 2. `b.go` · **B** — use it")
)
eq("panel: the status line", lines[3], "_2 chosen_")
local first_row
for i, l in ipairs(lines) do
  if l:find "%- %[x%] 1%." then
    first_row = i
  end
end
vim.api.nvim_win_set_cursor(0, { first_row + 1, 0 })
press "<Space>"
lines = vim.api.nvim_buf_get_lines(pbuf, 0, -1, false)
ok(
  "panel: Space unchecks the step under the cursor and updates the estimate",
  vim.tbl_contains(lines, "- [ ] 2. `b.go` · **B** — use it") and lines[3] == "_1 chosen_"
)
press "a"
ok("panel: a toggles all (some were off → all on)", #vim.tbl_filter(function(s)
  return s.on
end, steps) == 2)
press "a"
ok("panel: and again → none", #vim.tbl_filter(function(s)
  return s.on
end, steps) == 0)
press "<CR>"
eq("panel: Enter with nothing checked does not run", ran, nil)
press "a"
press "<CR>"
eq(
  "panel: Enter runs the checked steps and closes",
  { ran and #ran, vim.api.nvim_get_current_buf() ~= pbuf },
  { 2, true }
)

-- the guard can stop the plan call
settings.budget.day_usd = 0.000001
FAKE.calls = 0
local before = #FAKE.notes
local pl_buf = K.open "internal/domain/note.go"
K.at(3)
plan.propose(seed, "x", found, dir, sel)
K.wait(function()
  return #FAKE.notes > before
end, 3000)
eq("plan: a used-up budget stops the plan call", FAKE.calls, 0)
settings.budget.day_usd = nil

K.finish()
