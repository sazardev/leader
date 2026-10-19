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

-- the hints that align a module with the rest of the library: STACK.md add-on axes and DESIGN.md patterns
local presets = require "agent.kit.presets"
local axes, patterns = {}, {}
for _, a in ipairs(presets.AXES) do
  axes[a.id] = true
end
for _, a in ipairs(presets.list "design-addons/patterns") do
  patterns[a.id] = true
end
for _, m in ipairs(all) do
  for _, t in ipairs(m.tech) do
    ok(m.id .. ": tech names a STACK.md add-on axis (" .. t .. ")", axes[t])
  end
  for _, d in ipairs(m.design) do
    ok(m.id .. ": design names a screen pattern (" .. d .. ")", patterns[d])
  end
end
ok("modules: a catalog worth browsing", #all >= 50)

-- every group has its label and every module sits in a known group
local labelled = {}
for _, g in ipairs(sm.GROUPS) do
  labelled[g.id] = true
end
for _, m in ipairs(all) do
  ok(m.id .. ": its group has a label", labelled[m.group])
end

-- starter kits: a product type as a set of modules
local kits = sm.kits()
ok("kits: several product types", #kits >= 8)
for _, k in ipairs(kits) do
  ok(k.id .. ": desc <= 110", #k.desc <= 110)
  ok(k.id .. ": picks at least four modules", #k.modules >= 4)
  for _, key in ipairs(k.modules) do
    ok(k.id .. ": its module exists (" .. key .. ")", keys[key])
  end
  for _, t in ipairs(k.tech) do
    ok(k.id .. ": tech names an axis (" .. t .. ")", axes[t])
  end
  for _, d in ipairs(k.design) do
    ok(k.id .. ": design names a pattern (" .. d .. ")", patterns[d])
  end
  local list = sm.resolve(k.modules, all, {})
  local spec_text = "# SPEC.md: X\n\n## Requirements\n\n## Edge cases\n\n## Open questions\n"
  local out = sm.apply_all(spec_text, list)
  ok(k.id .. ": it applies to a SPEC.md", out:find("FR%-1") ~= nil)
  eq(k.id .. ": applying it twice adds nothing", (sm.apply_all(out, list)), out)
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

-- the marketplace's windows: a keypress is the mapping of the buffer it happens in
local function press(buf, key)
  local lhs = vim.api.nvim_replace_termcodes(key, true, true, true)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if vim.api.nvim_replace_termcodes(map.lhs, true, true, true) == lhs then
      return map.callback()
    end
  end
  error("no mapping " .. key)
end
local function goto_module(st, name)
  for i, r in ipairs(st.rows) do
    if r.module and r.module.name == name then
      vim.api.nvim_win_set_cursor(st.wins.list, { i, 0 })
      st.view = "pane"
      require("agent.kit.specmarket").render(st)
      return
    end
  end
  error("no module " .. name)
end
local function text_of(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local st = sm.open()
ok("open: three windows, the list focused", st and vim.api.nvim_get_current_win() == st.wins.list)
ok(
  "open: the list is grouped, every module in its group",
  text_of(st.bufs.list):find("EVERY APP", 1, true) and text_of(st.bufs.list):find("Roles and permissions", 1, true)
)
ok("open: more than the first dozen modules", #all >= 30)
goto_module(st, "Roles and permissions")
ok(
  "open: the pane reads the module under the cursor, with its questions",
  text_of(st.bufs.pane):find("ROLES AND PERMISSIONS", 1, true)
    and text_of(st.bufs.pane):find("QUESTIONS THAT ARE YOURS", 1, true)
    and text_of(st.bufs.pane):find("builds on accounts", 1, true)
)
ok("open: nothing picked says how to pick", text_of(st.bufs.summary):find("Nothing picked yet", 1, true))
press(st.bufs.list, "<Space>")
ok("open: Space picks it", st.chosen.roles == true)
ok(
  "open: the strip says what a choice pulled in and the FR range",
  text_of(st.bufs.summary):find("with what they need: accounts", 1, true)
    and text_of(st.bufs.summary):find("FR%-%d+–FR%-%d+")
)
-- reading and customizing: leave one requirement out
press(st.bufs.list, "<CR>")
ok("read: the pane takes the focus", vim.api.nvim_get_current_win() == st.wins.pane)
local lines = vim.api.nvim_buf_get_lines(st.bufs.pane, 0, -1, false)
local row
for i, l in ipairs(lines) do
  if l:find("Ownership", 1, true) and l:find("■", 1, true) then
    row = i
  end
end
vim.api.nvim_win_set_cursor(st.wins.pane, { row, 0 })
press(st.bufs.pane, "<Space>")
ok("read: Space leaves the requirement out", st.left_out.roles and st.left_out.roles["Ownership"])
ok(
  "read: and it shows as left out",
  vim.iter(vim.api.nvim_buf_get_lines(st.bufs.pane, 0, -1, false)):any(function(l)
    return l:find("□ Ownership", 1, true) ~= nil
  end)
)
-- the result view: what SPEC.md gets, and back
press(st.bufs.pane, "p")
ok(
  "result: the text that would be added, without what was left out",
  text_of(st.bufs.pane):find("Roles", 1, true) and not text_of(st.bufs.pane):find("Ownership", 1, true)
)
press(st.bufs.pane, "<Esc>")
ok("result: Esc goes back to the list", vim.api.nvim_get_current_win() == st.wins.list and st.view == "pane")
-- the filter
st.filter = "payment"
st.rows = require("agent.kit.specmarket").rows(st)
ok(
  "filter: narrows by name, description and key",
  #vim.tbl_filter(function(r)
    return r.module
  end, st.rows) >= 1 and not vim.iter(st.rows):any(function(r)
    return r.module and r.module.name == "Roles and permissions"
  end)
)
st.filter = ""
st.rows = require("agent.kit.specmarket").rows(st)
-- add: confirmed before SPEC.md changes; the windows close once it is written
goto_module(st, "Roles and permissions")
press(st.bufs.list, "A")
eq("add: confirmed before SPEC.md changes", confirms[#confirms].title, "Add to SPEC.md")
ok(
  "add: the confirmation says what a choice pulled in",
  vim.iter(confirms[#confirms].lines):any(function(l)
    return type(l) == "table" and l[1][1]:find("with what they need: accounts", 1, true) ~= nil
  end)
)
local written = table.concat(vim.fn.readfile(base .. "/app/SPEC.md"), "\n")
ok(
  "add: SPEC.md has both modules",
  written:find("<!-- module: accounts -->", 1, true) and written:find("<!-- module: roles -->", 1, true)
)
ok("add: what was left out is not there", not written:find("### FR%-%d+: Ownership"))
ok("add: the notice points to building them", notes[#notes]:find("<leader>aSbf builds them one by one", 1, true))
ok("add: the marketplace is closed", not vim.api.nvim_win_is_valid(st.wins.list))

-- open again: what SPEC.md has says so and cannot be picked
local st2 = sm.open()
vim.api.nvim_set_current_win(st2.wins.list)
goto_module(st2, "Accounts and sign-in")
ok("open again: a module SPEC.md has says so", text_of(st2.bufs.pane):find("already in SPEC.md", 1, true))
press(st2.bufs.list, "<Space>")
ok("open again: it cannot be picked twice", not st2.chosen.accounts)
require("agent.kit.specmarket").close(st2)

-- starter kits: a row that picks all its modules; the pane says what it brings and what it goes with
local st3 = sm.open()
vim.api.nvim_set_current_win(st3.wins.list)
local kit_at
for i, r in ipairs(st3.rows) do
  if r.kit and not kit_at then
    kit_at = i
  end
end
ok("kits: the list opens with starter kits", kit_at ~= nil and text_of(st3.bufs.list):find("STARTER KITS", 1, true))
vim.api.nvim_win_set_cursor(st3.wins.list, { kit_at, 0 })
require("agent.kit.specmarket").render(st3)
local kit = st3.rows[kit_at].kit
ok(
  "kits: the pane reads the kit with its modules and what it goes with",
  text_of(st3.bufs.pane):find(("MODULES (%d)"):format(#kit.modules), 1, true)
    and text_of(st3.bufs.pane):find("GOES WITH", 1, true)
)
press(st3.bufs.list, "<Space>")
local all_in = true
for _, key in ipairs(kit.modules) do
  all_in = all_in and (st3.chosen[key] == true or st3.applied[key] == true)
end
ok("kits: Space picks every module of the kit", all_in)
eq("kits: and the kit says so", require("agent.kit.specmarket").kit_state(st3, kit), "chosen")
press(st3.bufs.list, "<Space>")
eq("kits: Space again picks none", vim.tbl_count(st3.chosen), 0)
-- the filter looks at requirement titles and what a module goes with
st3.filter = "refund"
st3.rows = require("agent.kit.specmarket").rows(st3)
ok(
  "filter: finds a module by a requirement it has (refund → payments)",
  vim.iter(st3.rows):any(function(r)
    return r.module and sm.key(r.module) == "payments"
  end)
)
st3.filter = "search"
st3.rows = require("agent.kit.specmarket").rows(st3)
ok(
  "filter: and by the add-on it goes with (search)",
  #vim.tbl_filter(function(r)
    return r.module and vim.tbl_contains(r.module.tech, "search")
  end, st3.rows) >= 1
)
require("agent.kit.specmarket").close(st3)

-- the pure pieces
local plan = sm.plan(spec, all, { "roles" }, { roles = { Ownership = true } })
ok("plan: pulls what a module needs", #plan.pulled == 1 and plan.pulled[1] == "accounts")
ok("plan: a requirement left out is not added", not plan.spec:find("Ownership", 1, true))
ok(
  "plan: the other requirements of the module are",
  plan.spec:find("Changing roles", 1, true) and plan.spec:find("Roles", 1, true)
)
local only = sm.restrict(find "roles", { Roles = true, Ownership = true, ["Changing roles"] = true })
eq("restrict: leaving everything out leaves no requirement", #only.requirements, 0)
local added = sm.added_lines(spec, plan.spec)
ok("added_lines: the new text only", #added > 0 and not vim.tbl_contains(added, "# SPEC.md: Notes"))
local market = require "agent.kit.specmarket"
eq("wrap: lines fit the width", vim.iter(market.wrap(("word "):rep(40), 30)):all(function(l)
  return #l <= 30
end), true)

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
