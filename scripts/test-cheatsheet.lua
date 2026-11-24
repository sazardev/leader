-- Tests of the live Mappings view: pure search/filter/order plus the market view and its controls.
--   nvim -u NONE --headless -c "luafile scripts/test-cheatsheet.lua"
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
  eq(name, not not cond, true)
end
local function keys(entries)
  return vim.tbl_map(function(e)
    return e.key
  end, entries)
end

local entries = {
  {
    key = "<leader>gr",
    action = "run",
    full = "Go run",
    modes = { "n" },
    language = "Go",
    group = "Go",
    source = "menu",
    scope = "Buffer-local",
    where = "go, gomod, gowork",
    prefix = "<leader>g",
  },
  {
    key = "<leader>gt",
    action = "test",
    full = "Go test",
    modes = { "n" },
    language = "Go",
    group = "Go",
    source = "menu",
    scope = "Buffer-local",
    where = "go, gomod, gowork",
    prefix = "<leader>g",
  },
  {
    key = "<leader>w",
    action = "save",
    full = "General save",
    modes = { "n" },
    language = "Global",
    group = "General",
    source = "global",
    scope = "Global",
    where = "everywhere",
  },
  {
    key = "gd",
    action = "go to definition",
    full = "LSP go to definition",
    modes = { "n" },
    language = "Global",
    group = "LSP",
    source = "lsp",
    scope = "Buffer-local",
    where = "buffers with an attached language server",
  },
  {
    key = "<Tab>",
    action = "next item",
    full = "next item",
    modes = { "i" },
    language = "Global",
    group = "Autocompletion",
    source = "completion",
    scope = "Insert mode",
    where = "blink.cmp completion",
  },
  {
    key = "K",
    action = "hover",
    full = "hover",
    modes = { "n" },
    language = "Global",
    group = "Neovim",
    source = "native",
    scope = "Native",
    where = "built into Neovim",
  },
}

local model = require("cheatsheet.model")
local examples = require("cheatsheet.examples")
for _, entry in ipairs(entries) do
  local described = examples.describe(entry)
  ok("examples: " .. entry.key, described.example ~= "" and described.usage ~= "")
  ok("examples: steps " .. entry.key, #described.steps >= 3)
  ok("examples: result " .. entry.key, described.result ~= "")
  ok("examples: notes " .. entry.key, #described.notes > 0)
  ok("examples: detailed usage " .. entry.key, #described.usage > 100)
end
local race = vim.deepcopy(entries[1])
race.key, race.action = "<leader>gR", "go test -race ./..."
local described = examples.describe(race)
ok("examples: curated Go race run", described.usage:find("race", 1, true) ~= nil)
ok("examples: Go race has steps", #described.steps >= 4)
ok("examples: Go race has result", described.result:find("tests", 1, true) ~= nil)
local visual = vim.deepcopy(entries[2])
visual.key, visual.action, visual.modes = "<local>x", "replace selection", { "x" }
ok("examples: visual selection", examples.describe(visual).example:find("Select", 1, true) ~= nil)
local completion = examples.describe(entries[5])
ok("examples: completion context", completion.usage:find("snippet", 1, true) ~= nil)
local tree_up = examples.describe({
  key = "-",
  action = "Up",
  modes = { "n" },
  language = "Global",
  group = "File tree",
  source = "tree",
  where = "inside nvim-tree",
})
ok("examples: tree navigation is specific", tree_up.result:find("cursor or root", 1, true) ~= nil)
local telescope = examples.describe({
  key = "<leader>ff",
  action = "find files",
  modes = { "n" },
  language = "Global",
  group = "Telescope",
  source = "global",
  where = "everywhere",
})
ok("examples: Telescope uses picker steps", telescope.steps[2]:find("query", 1, true) ~= nil)

local st = model.state(entries)
eq("model: all mappings", #model.visible(st), 6)
st.language = "Go"
eq("model: language", keys(model.visible(st)), { "<leader>gr", "<leader>gt" })
st.language = "All"
st.filter = "GO TEST"
eq("model: every search word matches", keys(model.visible(st)), { "<leader>gt" })
st.filter = "<leader>gr"
eq("model: key notation is searchable", keys(model.visible(st)), { "<leader>gr" })
st.filter = "attached server"
eq("model: scope is searchable", keys(model.visible(st)), { "gd" })
entries[1].example = "race detector"
st.filter = "race detector"
eq("model: examples are searchable", keys(model.visible(st)), { "<leader>gr" })
entries[1].example = nil
entries[1].steps = { "race detector workflow" }
st.filter = "detector workflow"
eq("model: steps are searchable", keys(model.visible(st)), { "<leader>gr" })
entries[1].steps = nil
st.filter = ""
st.modes.n, st.modes.x, st.modes.o, st.modes.t = false, false, false, false
eq("model: mode filter", keys(model.visible(st)), { "<Tab>" })
st.modes.n = true
st.sources.completion = false
eq("model: source filter", #model.visible(st), 5)
st.sources.lsp = false
eq("model: filters combine", #model.visible(st), 4)
st = model.state(entries)
local function sorted(sort)
  local copy = vim.deepcopy(entries)
  table.sort(copy, function(a, b)
    return model.less(a, b, sort)
  end)
  return copy
end
eq("model: key order", keys(sorted("key")), { "<leader>gr", "<leader>gt", "<leader>w", "<Tab>", "gd", "K" })
eq(
  "model: reverse key order",
  keys(sorted("key_desc")),
  { "K", "gd", "<Tab>", "<leader>w", "<leader>gt", "<leader>gr" }
)
local ordered = sorted("action")
eq("model: action order", ordered[1].action, "go to definition")
eq("model: action order last", ordered[#ordered].action, "test")
ordered = sorted("mode")
eq("model: mode order", ordered[1].key, "<leader>gr")
local groups = model.grouped(st)
eq(
  "model: groups alphabetical",
  vim.tbl_map(function(g)
    return g.name
  end, groups),
  { "Autocompletion", "General", "Go", "LSP", "Neovim" }
)
local languages = model.languages(entries)
eq("model: All languages first", languages[1].value, "All")
eq("model: Global second", languages[2].value, "Global")
eq("model: language counts", languages[3], { label = "Go", value = "Go", count = 2 })
eq("model: all modes label", model.active_modes(st), "All")
eq("model: all sources label", model.active_sources(st), "All")

-- View: rows, highlights, details and footer all describe the same filtered state.
local view = require("cheatsheet")
local modal = require("utils.modal")
local market = require("utils.market")
st = model.state(entries)
local rows = view.rows(st)
eq("view: title count", rows[1].count, 6)
ok(
  "view: group rows",
  vim.iter(rows):any(function(row)
    return row.group == "Go"
  end)
)
local go_group = vim.iter(rows):find(function(row)
  return row.group == "Go"
end)
eq("view: group count", go_group.count, 2)
local go = vim.iter(rows):find(function(row)
  return row.entry and row.entry.key == "<leader>gr"
end)
local line = view.list_line(go)
ok(
  "view: key is painted",
  vim.iter(line):any(function(seg)
    return seg[1] == "<leader>gr" and seg[2] == view.hl.key
  end)
)
local pane, pane_rows = view.pane(st, go, 70)
local pane_text = table.concat(
  vim.tbl_map(function(l)
    return table.concat(vim.tbl_map(function(seg)
      return seg[1]
    end, l))
  end, pane),
  "\n"
)
ok("view: detail has language", pane_text:find("Go", 1, true) ~= nil)
ok("view: detail has availability", pane_text:find("go, gomod, gowork", 1, true) ~= nil)
ok("view: detail has an example", pane_text:find("EXAMPLE", 1, true) ~= nil)
ok("view: detail has usage", pane_text:find("USAGE", 1, true) ~= nil)
ok("view: detail has steps", pane_text:find("STEPS", 1, true) ~= nil)
ok("view: detail has result", pane_text:find("RESULT", 1, true) ~= nil)
ok("view: detail has notes", pane_text:find("NOTES", 1, true) ~= nil)
local pane_actions = {}
for _, item in pairs(pane_rows) do
  for _, action in ipairs(item.actions or {}) do
    pane_actions[action.action] = action
  end
end
ok("view: mouse can copy", pane_actions.copy ~= nil)
ok("view: mouse can search", pane_actions.search ~= nil)
ok("view: mouse can choose language", pane_actions.language ~= nil)
local summary = view.summary(st)
ok("view: footer has result count", (summary[1][1][1] .. summary[1][2][1]):find("6 shortcuts", 1, true) ~= nil)
local saved_cols = vim.o.columns
vim.o.columns = 60
local narrow_summary = view.summary(st)
ok(
  "view: narrow footer fits",
  vim.iter(narrow_summary):all(function(line)
    return vim.fn.strdisplaywidth(table.concat(vim.tbl_map(function(segment)
      return segment[1]
    end, line))) <= 60
  end)
)
local narrow_hints = view.hints(st, "list")
local hint_width = vim.fn.strdisplaywidth(table.concat(vim.tbl_map(function(segment)
  return segment[1]
end, market.hints(narrow_hints))))
ok("view: narrow hints fit", hint_width <= 60)
eq("view: narrow hints keep search", narrow_hints[1][1], "/")
eq("view: narrow hints keep close", narrow_hints[#narrow_hints][1], "q")
vim.o.columns = saved_cols

-- Controls: search, language, filters, sort and reset update the model, not a second copy of it.
local spec = view.spec(st)
eq("view: compact footer", spec.summary_rows, 3)
ok("view: live search input is configured", spec.live_input ~= nil)
local function control(name, mode)
  for _, key in ipairs(spec.keys[mode or "list"]) do
    if key[1] == name then
      return key[2]
    end
  end
end
for _, name in ipairs({ "/", "l", "f", "s", "r", "y" }) do
  ok("view: control " .. name, control(name) ~= nil)
end
ok("view: copy works from details", control("y", "all") ~= nil)
local function press(name, m, row)
  control(name)(m, row)
end

st.filter = "go"
eq("control: search narrows", #model.visible(st), 3)

local languages_seen, language_opts
package.loaded["tasks.picker"] = {
  choose = function(items, opts, cb)
    languages_seen, language_opts = items, opts
    cb(items[2])
  end,
}
press("l", st, go)
eq("control: language picker has All", languages_seen[1].value, "All")
eq("control: language starts on All", language_opts.select, 1)
eq("control: language counts are visible", languages_seen[1].desc, "6 mappings")
eq("control: language applied", st.language, "Global")
eq("control: language narrows", #model.visible(st), 1)

local checklist
modal.checklist = function(items, _, cb)
  checklist = { items = items, cb = cb }
end
press("f", st, go)
eq("control: five modes", #checklist.items, 11)
local chosen = {}
for i, item in ipairs(checklist.items) do
  if
    (item.group == "Modes" and item.label == "Normal") or (item.group == "Sources" and item.label == "Leader menus")
  then
    chosen[#chosen + 1] = i
  end
end
checklist.cb(chosen)
eq("control: only Normal enabled", model.active_modes(st), "N")
eq("control: only menus enabled", model.active_sources(st), "Leader menus")
eq("control: combined filters", #model.visible(st), 0)

local sort_seen, sort_opts
package.loaded["tasks.picker"].choose = function(items, opts, cb)
  sort_seen, sort_opts = items, opts
  cb(items[3])
end
press("s", st, go)
eq("control: sort options", #sort_seen, 5)
eq("control: current sort is selected", sort_opts.select, 1)
eq("control: sort applied", st.sort, "action")
press("r", st, go)
eq("control: reset search", st.filter, "")
eq("control: reset language", st.language, "All")
eq("control: reset sort", st.sort, "key")
eq("control: reset modes", model.active_modes(st), "All")
eq("control: reset sources", model.active_sources(st), "All")
eq("control: reset results", #model.visible(st), 6)

-- Real windows: the view opens, narrow layout swaps panes, and closing leaves nothing behind.
local cols, lines = vim.o.columns, vim.o.lines
vim.o.columns, vim.o.lines = 120, 32
local m = view.open({ entries = entries })
ok("market: opens", m ~= nil)
eq("market: input adds one window", #vim.tbl_values(m.wins), 4)
ok("market: list is a market buffer", vim.bo[m.bufs.list].filetype == "market")
ok("market: cursor starts on a key", m.rows[vim.api.nvim_win_get_cursor(m.wins.list)[1]].entry ~= nil)
ok("market: live input exists", m.bufs.input and m.wins.input)
local slash
for _, key in ipairs(m.def.keys.list) do
  if key[1] == "/" then
    slash = key[2]
  end
end
slash(m)
eq("live search: slash focuses the input", vim.api.nvim_get_current_win(), m.wins.input)
local function type_live(text)
  vim.api.nvim_buf_set_lines(m.bufs.input, 0, -1, false, { "/ " .. text })
  vim.api.nvim_exec_autocmds("TextChangedI", { buffer = m.bufs.input })
end
type_live("g")
eq("live search: first keystroke updates", m.filter, "g")
type_live("go")
eq("live search: query updates", m.filter, "go")
eq("live search: results update immediately", #model.visible(m), 3)
type_live("go test")
eq("live search: refined query updates", #model.visible(m), 1)
local clear
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(m.bufs.input, "i")) do
  if mapping.lhs:lower() == "<c-u>" and mapping.callback then
    clear = mapping.callback
  end
end
clear()
eq("live search: Ctrl-U clears in place", m.filter, "")
eq("live search: Ctrl-U keeps focus", vim.api.nvim_get_current_win(), m.wins.input)
type_live("go test")
local footer = table.concat(vim.api.nvim_buf_get_lines(m.bufs.summary, 0, -1, false), "\n")
ok("live search: count updates in the footer", footer:find("1 of 6", 1, true) ~= nil)
vim.cmd("stopinsert")
local accept
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(m.bufs.input, "i")) do
  if mapping.lhs == "<CR>" and mapping.callback then
    accept = mapping.callback
  end
end
accept()
eq("live search: Enter returns to the list", vim.api.nvim_get_current_win(), m.wins.list)
eq("live search: Enter keeps the query", m.filter, "go test")
slash(m)
type_live("go")
vim.cmd("stopinsert")
local cancel
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(m.bufs.input, "i")) do
  if mapping.lhs == "<Esc>" and mapping.callback then
    cancel = mapping.callback
  end
end
cancel()
eq("live search: Esc returns to the list", vim.api.nvim_get_current_win(), m.wins.list)
eq("live search: Esc clears the query", m.filter, "")
eq("live search: input keeps its prefix", vim.api.nvim_buf_get_lines(m.bufs.input, 0, 1, false)[1], "/ ")
local real_mouse = vim.fn.getmousepos
local function fire_mouse(buf, lhs, pos)
  vim.fn.getmousepos = function()
    return pos
  end
  local fired = false
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if mapping.lhs == lhs and mapping.callback then
      mapping.callback()
      fired = true
      break
    end
  end
  vim.fn.getmousepos = real_mouse
  return fired
end
ok(
  "mouse: search bar is wired",
  fire_mouse(m.bufs.input, "<LeftRelease>", { winid = m.wins.input, line = 1, column = 1 })
)
eq("mouse: search bar takes focus", vim.api.nvim_get_current_win(), m.wins.input)
vim.cmd("stopinsert")
market.focus(m, "list")
local hover_row
for i, row in ipairs(m.rows) do
  if row.entry and row.entry.key == "gd" then
    hover_row = i
    break
  end
end
ok(
  "mouse: hover is wired",
  fire_mouse(m.bufs.list, "<MouseMove>", { winid = m.wins.list, line = hover_row, column = 3 })
)
eq("mouse: hover selects the row", vim.api.nvim_win_get_cursor(m.wins.list)[1], hover_row)
local chip_line, chip_region
for line, item in pairs(m.pane_rows) do
  for _, region in ipairs(item.actions or {}) do
    if region.action == "copy" then
      chip_line, chip_region = line, region
      break
    end
  end
end
ok(
  "mouse: detail chip is wired",
  fire_mouse(m.bufs.pane, "<MouseMove>", {
    winid = m.wins.pane,
    line = chip_line,
    column = chip_region.from + 1,
  })
)
ok("mouse: chip has hover feedback", m.hover ~= nil)
local group_row
for i, row in ipairs(m.rows) do
  if row.group == "Go" then
    group_row = i
    break
  end
end
ok(
  "mouse: group click is wired",
  fire_mouse(m.bufs.list, "<LeftRelease>", { winid = m.wins.list, line = group_row, column = 3 })
)
eq("mouse: group click folds", m.collapsed.Go, true)
m.filter = "go"
market.refresh(m)
ok(
  "live search: folded groups reveal matches",
  vim.iter(m.rows):any(function(row)
    return row.entry and row.entry.language == "Go"
  end)
)
m.filter = ""
market.refresh(m)
vim.o.columns = 80
market.layout(m)
ok("market: narrow list visible", not vim.api.nvim_win_get_config(m.wins.list).hide)
ok("market: narrow pane hidden", vim.api.nvim_win_get_config(m.wins.pane).hide)
m.filter = "no-such-mapping"
market.refresh(m)
local empty = table.concat(vim.api.nvim_buf_get_lines(m.bufs.list, 0, -1, false), "\n")
ok("market: useful empty state", empty:find("No mappings match", 1, true) ~= nil)
local wins = vim.tbl_values(m.wins)
market.close(m)
ok(
  "market: closes every window",
  vim.iter(wins):all(function(win)
    return not vim.api.nvim_win_is_valid(win)
  end)
)
eq("market: forgets current view", view.current, nil)
vim.o.columns, vim.o.lines = cols, lines

print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
