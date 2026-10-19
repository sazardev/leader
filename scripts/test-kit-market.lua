-- Tests of the full-screen marketplace (nvim/lua/utils/market.lua) and its two users: the STACK.md / DESIGN.md customize
-- step (agent/kit/addonmarket.lua) and the SPEC.md modules (agent/kit/specmarket.lua): windows, keys, exclusive groups,
-- folding, help, the narrow-terminal layout, hiding what is there, suggestions from SPEC.md. Real windows, no network.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-kit-market.lua"
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
    notes[#notes + 1] = m
  end,
  warn = function(m)
    notes[#notes + 1] = m
  end,
  error = function(m)
    notes[#notes + 1] = m
  end,
}

local market = require "utils.market"
local addons = require "agent.kit.addonmarket"
local specmarket = require "agent.kit.specmarket"
local sm = require "agent.kit.specmodules"
local presets = require "agent.kit.presets"
local compose = require "agent.kit.compose"

local function press(buf, key)
  local lhs = vim.api.nvim_replace_termcodes(key, true, true, true)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if vim.api.nvim_replace_termcodes(map.lhs, true, true, true) == lhs then
      return map.callback()
    end
  end
  error("no mapping " .. key)
end
local function text_of(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end
local function hidden(win)
  return vim.api.nvim_win_get_config(win).hide == true
end
local function cursor_on(m, pred)
  for i, r in ipairs(m.rows) do
    if pred(r) then
      vim.api.nvim_win_set_cursor(m.wins.list, { i, 0 })
      market.refresh(m)
      return true
    end
  end
  return false
end

-- ── the STACK.md customize step ──────────────────────────────────────────────

local nextjs
for _, p in ipairs(presets.list "stack/web") do
  if p.id == "nextjs" then
    nextjs = p
  end
end
local list = {}
for _, a in ipairs(presets.addons(presets.tags(nextjs, "web"))) do
  list[#list + 1] = { key = a.axis .. "/" .. a.id, name = a.name, group = a.group, addon = a }
end
ok("customize: a stack has several groups to choose from", #list > 10)

eq(
  "rows_of: the Stack rows an add-on sets",
  addons.rows_of "## Stack\n\n| Auth | Better Auth | why |\n| Sessions | cookies | x |\n\n## Conventions\n\n| Not | this |\n",
  { "Auth", "Sessions" }
)

local function apply(text, choices, picked)
  for _, c in ipairs(choices) do
    if picked[c.key] and c.addon then
      text = compose.merge(text, c.addon.body)
    end
  end
  return text
end

vim.o.columns, vim.o.lines = 140, 40
local done_with, went_back = nil, false
local m = addons.open {
  title = "Next.js",
  doc = "STACK.md",
  list = list,
  checked = {},
  base = nextjs.body,
  apply = apply,
  done = function(c)
    done_with = c
  end,
  back = function()
    went_back = true
  end,
}
ok("customize: three windows, the list focused", vim.api.nvim_get_current_win() == m.wins.list)
ok(
  "customize: the list has its title and the groups",
  text_of(m.bufs.list):find("STACK.md ADD-ONS", 1, true) and text_of(m.bufs.list):find("DATABASE", 1, true)
)
ok("customize: a one-of group says so", text_of(m.bufs.list):find("one of", 1, true))
ok("customize: wide, the list and the pane are side by side", not hidden(m.wins.list) and not hidden(m.wins.pane))
ok("customize: the strip starts empty", text_of(m.bufs.summary):find("Nothing picked", 1, true))

-- two choices of the same one-of group: the second replaces the first
local first, second
for _, c in ipairs(list) do
  if c.group == "Database" then
    if not first then
      first = c
    elseif not second then
      second = c
    end
  end
end
ok("customize: the stack offers a database", first and second)
cursor_on(m, function(r)
  return r.choice == first
end)
ok("customize: the pane reads the add-on under the cursor", text_of(m.bufs.pane):find(first.name:upper(), 1, true))
press(m.bufs.list, "<Space>")
ok("customize: Space picks it", m.checked[first.key] == true)
ok("customize: the strip says what it sets", text_of(m.bufs.summary):find("sets the rows Database", 1, true))
cursor_on(m, function(r)
  return r.choice == second
end)
press(m.bufs.list, "<Space>")
ok("customize: picking another of the group drops the first", m.checked[second.key] and not m.checked[first.key])
press(m.bufs.list, "<Space>")
ok("customize: picking it again leaves none", not m.checked[second.key])
press(m.bufs.list, "<Space>")

-- what it would write
press(m.bufs.list, "p")
ok("customize: p shows what the document gets", text_of(m.bufs.pane):find("WHAT STACK.md GETS", 1, true))
ok("customize: and it is the add-on's text", text_of(m.bufs.pane):find("Database", 1, true))
press(m.bufs.pane, "p")
eq("customize: p again goes back", m.view, "pane")

-- folding a group, the filter, the help
local at_group = select(2, market.current(m))
press(m.bufs.list, "<Tab>")
local folded = false
for _, r in ipairs(m.rows) do
  folded = folded or r.collapsed == true
end
ok("customize: Tab folds the group (its title says so)", folded and text_of(m.bufs.list):find("▸", 1, true))
press(m.bufs.list, "<Tab>")
ok("customize: Tab on the folded title unfolds it", not vim.iter(m.rows):any(function(r)
  return r.collapsed
end))
m.filter = "postgres"
market.refresh(m)
ok(
  "customize: the filter narrows the list",
  #vim.tbl_filter(function(r)
    return r.choice
  end, m.rows) < #list
)
m.filter = ""
market.refresh(m)
local wins_before = #vim.api.nvim_list_wins()
press(m.bufs.list, "?")
eq("customize: ? opens the help", #vim.api.nvim_list_wins(), wins_before + 1)
ok("customize: the help lists the keys", text_of(vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())):find("filter", 1, true))
press(vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win()), "<Esc>")
eq("customize: Esc closes the help", #vim.api.nvim_list_wins(), wins_before)
vim.api.nvim_set_current_win(m.wins.list)

-- a narrow terminal: the panes take turns
vim.o.columns = 80
market.layout(m)
ok("narrow: the list takes the screen", not hidden(m.wins.list) and hidden(m.wins.pane))
eq("narrow: at the full width", vim.api.nvim_win_get_width(m.wins.list), 80)
press(m.bufs.list, "l")
ok("narrow: l opens the pane in its place", hidden(m.wins.list) and not hidden(m.wins.pane))
eq("narrow: the pane has the focus", vim.api.nvim_get_current_win(), m.wins.pane)
press(m.bufs.pane, "<Esc>")
ok("narrow: Esc goes back to the list", not hidden(m.wins.list) and hidden(m.wins.pane))
vim.o.columns = 140
market.layout(m)

-- next and back
press(m.bufs.list, "<CR>")
vim.wait(200, function()
  return done_with ~= nil
end)
ok("customize: ⏎ goes on with what is picked", done_with and done_with[second.key] and not done_with[first.key])
ok("customize: and the windows are gone", not vim.api.nvim_win_is_valid(m.wins.list))

local m2 = addons.open {
  title = "Next.js",
  list = list,
  checked = {},
  done = function() end,
  back = function()
    went_back = true
  end,
}
ok("customize: without a base there is no `what it writes` view", m2.def.result == nil)
press(m2.bufs.list, "<Esc>")
vim.wait(200, function()
  return went_back
end)
ok("customize: Esc goes back one step", went_back and not vim.api.nvim_win_is_valid(m2.wins.list))

-- ── the SPEC.md modules: hide what is there, suggestions ─────────────────────

local all = sm.all()
local spec = table.concat({
  "# SPEC.md: Shop",
  "",
  "## Requirements",
  "",
  "### FR-1: Pay for an order",
  "",
  "The system must take payment with a card and send an invoice.",
  "",
  "- Given an order, when the person pays, then it is paid",
  "",
  "## Edge cases",
  "",
  "## Open questions",
}, "\n")
local applied = sm.applied(spec, all)
local suggested = sm.suggest(spec, all, applied)
ok("suggest: a module the text talks about (payments)", suggested.payments ~= nil)
ok("suggest: and invoices", suggested.invoices ~= nil)
ok("suggest: not one it never names", suggested.chat == nil)
local with_marker = spec .. "\n<!-- module: payments -->"
ok("suggest: nothing for what SPEC.md has", sm.suggest(with_marker, all, sm.applied(with_marker, all)).payments == nil)

local st = specmarket.new {
  root = "/tmp",
  spec = spec,
  all = all,
  kits = sm.kits(),
  labels = sm.labels(),
  applied = { accounts = true },
  on_add = function() end,
}
ok("modules: a suggested one is marked", text_of(st.bufs.list):find("Payments ★", 1, true) or text_of(st.bufs.list):find("★", 1, true))
cursor_on(st, function(r)
  return r.module and sm.key(r.module) == "payments"
end)
ok("modules: and its pane says why", text_of(st.bufs.pane):find("your SPEC.md mentions", 1, true))
ok("modules: what SPEC.md has is listed", text_of(st.bufs.list):find("✓ Accounts and sign-in", 1, true))
press(st.bufs.list, "h")
ok("modules: h hides what SPEC.md has", not text_of(st.bufs.list):find("Accounts and sign-in", 1, true))
press(st.bufs.list, "h")
ok("modules: h again shows it", text_of(st.bufs.list):find("Accounts and sign-in", 1, true) ~= nil)
press(st.bufs.list, "?")
ok("modules: the help explains the marks", text_of(vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())):find("already in SPEC.md", 1, true))
press(vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win()), "q")
vim.api.nvim_set_current_win(st.wins.list)
-- narrow: reading a module takes the whole screen, Esc gives the list back
vim.o.columns = 80
market.layout(st)
cursor_on(st, function(r)
  return r.module and sm.key(r.module) == "payments"
end)
press(st.bufs.list, "<CR>")
ok("modules, narrow: ⏎ reads the module on the whole screen", hidden(st.wins.list) and not hidden(st.wins.pane))
press(st.bufs.pane, "<Esc>")
ok("modules, narrow: Esc back to the list", not hidden(st.wins.list))
market.close(st)

-- ── what a module goes with: its STACK.md groups and DESIGN.md patterns, opened from the marketplace ──
vim.o.columns, vim.o.lines = 140, 40
local base = vim.fn.tempname()
vim.fn.mkdir(base .. "/app", "p")
local function write(file, body)
  local f = assert(io.open(base .. "/app/" .. file, "w"))
  f:write(body)
  f:close()
end
write("STACK.md", nextjs.body)
local a_design = presets.all("design")[1]
write("DESIGN.md", a_design.body)
write("SPEC.md", spec)
vim.system({ "git", "init", "-q" }, { cwd = base .. "/app" }):wait()
vim.cmd.edit(vim.fn.fnameescape(base .. "/app/SPEC.md"))
local pair = sm.open()
cursor_on(pair, function(r)
  return r.module and sm.key(r.module) == "accounts"
end)
local count = #vim.api.nvim_list_wins()
press(pair.bufs.list, "t")
ok("goes with: t opens the STACK.md add-ons over the marketplace", #vim.api.nvim_list_wins() == count + 3)
local top = vim.api.nvim_get_current_win()
local top_buf = vim.api.nvim_win_get_buf(top)
ok("goes with: its groups are marked ★", text_of(top_buf):find("AUTH", 1, true) and text_of(top_buf):find("★", 1, true))
local at = vim.api.nvim_win_get_cursor(top)[1]
ok("goes with: the cursor starts on a suggested group", vim.api.nvim_buf_get_lines(top_buf, at - 1, at, false)[1] ~= "")
local top_m
for _, w in ipairs(vim.api.nvim_list_wins()) do
  if vim.api.nvim_win_get_buf(w) == top_buf then
    top_m = true
  end
end
ok("goes with: the marketplace below is still there", vim.api.nvim_win_is_valid(pair.wins.list))
press(top_buf, "<Esc>")
vim.wait(200)
vim.api.nvim_set_current_win(pair.wins.list)
count = #vim.api.nvim_list_wins()
press(pair.bufs.list, "d")
ok("goes with: d opens the DESIGN.md add-ons with the patterns checked", #vim.api.nvim_list_wins() == count + 3)
local dbuf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
ok("goes with: the screen patterns are listed", text_of(dbuf):find("SCREEN PATTERNS", 1, true))
ok("goes with: and the ones it pairs with are picked", text_of(dbuf):find("■ Forms and validation", 1, true))
press(dbuf, "<Esc>")
vim.wait(200)
market.close(pair)

print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd "qa!"
