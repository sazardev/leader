-- Tests of the SPEC.md modules (nvim/lua/agent/kit/specmodules.lua, <leader>aSm): every module file (parses, has
-- requirements with criteria, tags that name its own requirements, needs that exist, questions), merging into SPEC.md
-- (next ids, the document's style, edge cases and questions tagged, a requirement already there kept and given the
-- extras, a mark that makes it idempotent), what a choice needs, and the flow with canned modal answers.
-- Hermetic: temp projects, no network or tokens.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-kit-specmodules.lua"
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
local confirms, checked = {}, {}
package.loaded["utils.modal"] = {
  hl = setmetatable({}, {
    __index = function(_, k)
      return k
    end,
  }),
  confirm = function(lines, opts, yes)
    confirms[#confirms + 1] = { title = opts.title, lines = lines }
    yes()
  end,
  checklist = function(items, _, done)
    checked.items = items
    local out = {}
    for i, item in ipairs(items) do
      if vim.tbl_contains(checked.pick or {}, item.label) then
        out[#out + 1] = i
      end
    end
    done(out)
  end,
}

local sm = require "agent.kit.specmodules"
local coverage = require "agent.kit.coverage"
local feature = require "agent.kit.feature"

-- ── every module file ────────────────────────────────────────────────────────

local all = sm.all()
ok("modules: there are some, every group used", #all >= 10)
local keys = {}
for _, m in ipairs(all) do
  keys[sm.key(m)] = true
end
for _, m in ipairs(all) do
  local titles = {}
  for _, r in ipairs(m.requirements) do
    titles[r.title] = true
  end
  ok(m.id .. ": at least two requirements", #m.requirements >= 2)
  for _, r in ipairs(m.requirements) do
    ok(
      m.id .. " " .. r.title .. ": a statement that says what the system must do",
      r.statement:find "^The system must" ~= nil
    )
    ok(m.id .. " " .. r.title .. ": Given/when/then criteria", #r.criteria >= 1 and vim.iter(r.criteria):all(function(c)
      return c:find "^Given " and c:find ", when " and c:find ", then "
    end))
  end
  for _, x in ipairs(vim.list_extend(vim.deepcopy(m.edge_cases), m.questions)) do
    ok(m.id .. ": a tag names one of its requirements (" .. (x.req or "-") .. ")", x.req == nil or titles[x.req])
  end
  ok(m.id .. ": asks something (the answers are yours)", #m.questions >= 1)
  for _, n in ipairs(m.needs) do
    ok(m.id .. ": needs a module that exists (" .. n .. ")", keys[n])
  end
end

-- ── merging ──────────────────────────────────────────────────────────────────

local function find(key)
  for _, m in ipairs(all) do
    if sm.key(m) == key then
      return m
    end
  end
end
local accounts, roles, subs = find "accounts", find "roles", find "subscriptions"
local spec = table.concat({
  "# SPEC.md: Notes",
  "",
  "## Requirements",
  "",
  "### FR-1: Create a note",
  "",
  "The system must create notes.",
  "",
  "### FR-2: Sign in",
  "",
  "The system must let me sign in with my company account.",
  "",
  "## Edge cases",
  "",
  "- (FR-1) empty note",
  "",
  "## Open questions",
  "",
  "- Q1: sync?",
}, "\n") .. "\n"
local new, r = sm.apply(spec, accounts)
eq(
  "apply: the next ids, the requirement already there skipped",
  { r.ids, r.skipped },
  { { "FR-3", "FR-4", "FR-5" }, { "Sign in" } }
)
ok(
  "apply: in SPEC.md's heading style, marked where it went in",
  new:find("<!-- module: accounts -->\n### FR-3: Sign up\n\nThe system must let a person create an account", 1, true)
)
ok(
  "apply: criteria under each requirement",
  new:find("- Given a new email and a password that meets the rules", 1, true)
)
ok(
  "apply: your Sign in kept as you wrote it",
  new:find("### FR-2: Sign in\n\nThe system must let me sign in with my company account.", 1, true)
    and not new:find "### FR%-%d+: Sign in\n\nThe system must let a person"
)
ok(
  "apply: its extras go to YOUR requirement",
  new:find("- (FR-2) Many failed attempts on one account", 1, true)
    and new:find("(FR-2): How many failed attempts lock an account", 1, true)
)
ok("apply: questions numbered on from Q1", new:find("- Q2 (FR-3): Which sign-in methods", 1, true))
eq(
  "apply: coverage sees the new requirements",
  vim.tbl_map(function(x)
    return x.id
  end, coverage.requirements(new)),
  { "FR-1", "FR-2", "FR-3", "FR-4", "FR-5" }
)
ok("apply: the block before the mark does not take it", not feature.block(new, "FR-2"):find("module", 1, true))
local again, r2 = sm.apply(new, accounts)
eq("apply twice: nothing changes", { again, #r2.ids }, { new, 0 })
eq("applied: by its mark", sm.applied(new, all).accounts, true)
local by_hand = { "# S", "", "## Requirements", "" }
for i, x in ipairs(accounts.requirements) do
  vim.list_extend(by_hand, { ("### FR-%d: %s"):format(i, x.title:upper()), "" }) -- titles compared loosely
end
by_hand = table.concat(by_hand, "\n")
eq("applied: or when SPEC.md has all of its requirements", sm.applied(by_hand, all).accounts, true)

local list_spec =
  "# S\n\n## Requirements\n\n- **FR-1** Create: The system must create.\n  - Given x, when y, then z\n\n## Data\n"
local list_new = sm.apply(list_spec, roles)
ok(
  "apply list style: bullets with indented criteria",
  list_new:find("- **FR-2** Roles: The system must give every account a role", 1, true)
    and list_new:find("\n  - Given a new account, when it is created, then it has the default role", 1, true)
)
ok(
  "apply: sections SPEC.md lacks are added",
  list_new:find("\n## Edge cases\n", 1, true) and list_new:find("\n## Open questions\n", 1, true)
)

local chosen, pulled = sm.resolve({ "subscriptions" }, all, {})
eq("resolve: what a module needs comes first", vim.tbl_map(sm.key, chosen), { "accounts", "payments", "subscriptions" })
eq("resolve: and is said", pulled, { "accounts", "payments" })
eq(
  "resolve: not what SPEC.md has",
  vim.tbl_map(sm.key, (sm.resolve({ "subscriptions" }, all, { accounts = true }))),
  { "payments", "subscriptions" }
)
local _, tot = sm.apply_all(spec, chosen)
eq(
  "apply_all: every requirement of the three",
  #tot.ids,
  #accounts.requirements - 1 + #find("payments").requirements + #subs.requirements
)

-- ── the flow ─────────────────────────────────────────────────────────────────

local base = vim.fn.tempname()
vim.fn.mkdir(base .. "/app", "p")
local f = assert(io.open(base .. "/app/SPEC.md", "w"))
f:write(spec)
f:close()
vim.system({ "git", "init", "-q" }, { cwd = base .. "/app" }):wait()
vim.cmd.edit(vim.fn.fnameescape(base .. "/app/SPEC.md"))
checked.pick = { "Roles and permissions" }
sm.open()
local roles_item = vim.tbl_filter(function(i)
  return i.label == "Roles and permissions"
end, checked.items)[1]
ok(
  "open: grouped, with what each adds and what it needs",
  roles_item.group == "Every app" and roles_item.desc:find("needs accounts", 1, true)
)
eq("open: confirmed before SPEC.md changes", confirms[#confirms].title, "Add to SPEC.md")
ok(
  "open: the confirmation says what a choice pulled in",
  vim.iter(confirms[#confirms].lines):any(function(l)
    return type(l) == "table" and l[1][1]:find("with what they need: accounts", 1, true) ~= nil
  end)
)
local written = table.concat(vim.fn.readfile(base .. "/app/SPEC.md"), "\n")
ok(
  "open: SPEC.md has both modules",
  written:find("<!-- module: accounts -->", 1, true) and written:find("<!-- module: roles -->", 1, true)
)
ok("open: the notice points to building them", notes[#notes]:find("<leader>aSbf builds them one by one", 1, true))
checked.pick = {}
sm.open()
local accounts_item = vim.tbl_filter(function(i)
  return i.label == "Accounts and sign-in"
end, checked.items)[1]
eq("open again: a module SPEC.md has says so", accounts_item.desc, "in SPEC.md")
vim.cmd.edit(vim.fn.fnameescape(base .. "/nothing.txt"))
sm.open()
ok("open: without SPEC.md it says to write it first", notes[#notes]:find("write yours first (<leader>aSs)", 1, true))

vim.fn.delete(base, "rf")
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd "qa!"
