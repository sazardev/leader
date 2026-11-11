-- Tests of lua/panes and of the start screen living in more than one window (ui/start). Real windows, no plugins:
-- opening a pane with the dashboard, each pane keeping its own selection, a file loading in ITS pane, resizing,
-- zooming, closing, the pane list and the plain-split setting.
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

local settings = require "core.settings"
vim.o.number = true -- what the real config sets: the start screen hides it only in its own window
settings.panes.dashboard = true
settings.panes.resize_step = 2
local panes = require "panes"
local start = require "ui.start"
start.setup()

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local function write(name)
  local path = dir .. "/" .. name
  local f = assert(io.open(path, "w"))
  f:write("local x = 1\n")
  f:close()
  return path
end
local a, b = write "a.lua", write "b.lua"

---@return integer[]
local function normal_wins()
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_tabpage_list_wins(0))
end

vim.cmd("edit " .. vim.fn.fnameescape(a))
local win1, buf1 = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()

-- ── a new pane opens on the start screen ─────────────────────────────────────
local win2 = assert(panes.open "right")
eq("split: two panes", #normal_wins(), 2)
eq("split: the new pane shows the dashboard", vim.bo.filetype, "nvdash")
eq("split: the original keeps its file", vim.api.nvim_win_get_buf(win1), buf1)
local inst2 = assert(start.instance(win2))
eq("split: the new dashboard belongs to that window", inst2.win, win2)
eq("split: the original window has no dashboard instance", start.instance(win1), nil)

-- the original window can show its own dashboard too: two independent instances
vim.api.nvim_set_current_win(win1)
local inst1 = assert(start.open())
ok("two dashboards: one instance per pane", start.instance(win1) ~= nil and start.instance(win2) ~= nil)
eq("two dashboards: they start with their own selection", { inst1.sel, inst2.sel }, { 1, 1 })
vim.api.nvim_set_current_win(win1)
vim.api.nvim_feedkeys("j", "x", false)
eq("two dashboards: moving one moves only its own", { inst1.sel, inst2.sel }, { 2, 1 })
vim.api.nvim_feedkeys("k", "x", false)

-- ── a file opened from a pane lands in THAT pane ─────────────────────────────
vim.api.nvim_set_current_win(win2)
vim.cmd("edit " .. vim.fn.fnameescape(b))
vim.wait(50, function()
  return vim.wo[win2].number
end)
eq("file in pane: the buffer is the chosen file", vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "b.lua")
eq("file in pane: its dashboard instance is gone", start.instance(win2), nil)
ok("file in pane: the other dashboard is still alive", start.instance(win1) ~= nil)
eq("file in pane: the window gets normal options back", vim.wo[win2].number, true)
eq("file in pane: the other dashboard keeps its own options", vim.wo[win1].number, false)
eq("file in pane: the start screen did not change the global defaults", vim.go.number, true)

-- ── resize ───────────────────────────────────────────────────────────────────
vim.api.nvim_set_current_win(win2)
local widths = { vim.api.nvim_win_get_width(win1), vim.api.nvim_win_get_width(win2) }
ok("resize: wider", panes.resize("right", 3) and vim.api.nvim_win_get_width(win2) > widths[2])
ok("resize: narrower", panes.resize("left", 3) and vim.api.nvim_win_get_width(win2) < widths[2] + 3)

-- a horizontal pane and its height
local win3 = assert(panes.open "below")
eq("below: a third pane", #normal_wins(), 3)
local height = vim.api.nvim_win_get_height(win3)
ok("resize: taller", panes.resize("down", 2) and vim.api.nvim_win_get_height(win3) > height)
ok("resize: shorter", panes.resize("up", 2) and vim.api.nvim_win_get_height(win3) < height + 2)
panes.close()
eq("close: the pane goes", #normal_wins(), 2)

-- ── zoom keeps the layout and comes back ─────────────────────────────────────
vim.api.nvim_set_current_win(win2)
panes.zoom()
eq("zoom: a tab of its own", #vim.api.nvim_list_tabpages(), 2)
panes.zoom()
eq("zoom: back to the real layout", #vim.api.nvim_list_tabpages(), 1)

-- ── the list ─────────────────────────────────────────────────────────────────
local picked
package.loaded["tasks.picker"] = {
  choose = function(items, opts, on_select)
    picked = { items = items, title = opts.title, on_select = on_select }
  end,
}
panes.pick()
ok("list: one row per pane", picked and #picked.items == #normal_wins())
local by_win = {}
for _, item in ipairs(picked.items) do
  by_win[item.value] = item
end
eq("list: the current pane is marked", by_win[win2].current, true)
eq("list: a file pane has its file name", by_win[win2].label, "b.lua")
eq("list: a dashboard pane says so", by_win[win1].label, "Dashboard")
picked.on_select(win1)
eq("list: Enter focuses the chosen pane", vim.api.nvim_get_current_win(), win1)
package.loaded["tasks.picker"] = nil

-- ── plain splits (no dashboard) when the setting is off ──────────────────────
settings.panes.dashboard = false
vim.api.nvim_set_current_win(win2)
local same = vim.api.nvim_get_current_buf()
local win4 = assert(panes.open "right")
eq("plain split: the same buffer", vim.api.nvim_win_get_buf(win4), same)
eq("plain split: no dashboard instance", start.instance(win4), nil)
panes.close()
settings.panes.dashboard = true

-- ── the last pane is never closed ────────────────────────────────────────────
vim.api.nvim_set_current_win(win1)
panes.close()
panes.close()
eq("close: the last pane stays", #normal_wins(), 1)
eq("close: and says no", panes.close(), false)

-- ── layout presets ───────────────────────────────────────────────────────────
---@return integer
local function one_pane()
  vim.o.hidden = true
  pcall(vim.cmd, "silent! only")
  vim.o.hidden = false
  vim.cmd("edit " .. vim.fn.fnameescape(a))
  return vim.api.nvim_get_current_win()
end

---@param wins integer[]
---@return number, number, number, number
local function box(wins)
  local top, left, bottom, right = math.huge, math.huge, 0, 0
  for _, win in ipairs(wins) do
    local pos = vim.api.nvim_win_get_position(win)
    local w, h = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
    top, left = math.min(top, pos[1]), math.min(left, pos[2])
    bottom, right = math.max(bottom, pos[1] + h), math.max(right, pos[2] + w)
  end
  return top, left, bottom, right
end

---@return integer[]
local function sorted_wins()
  local ws = normal_wins()
  table.sort(ws, function(x, y)
    local xr, xc = unpack(vim.api.nvim_win_get_position(x))
    local yr, yc = unpack(vim.api.nvim_win_get_position(y))
    if xr ~= yr then
      return xr < yr
    end
    return xc < yc
  end)
  return ws
end

local first = one_pane()
ok("preset: double starts", panes.preset "double")
eq("preset: double has two panes", #normal_wins(), 2)
local left, right = sorted_wins()[1], sorted_wins()[2]
eq("preset: double side by side", vim.api.nvim_win_get_position(left)[1], vim.api.nvim_win_get_position(right)[1])
ok("preset: double equal widths", math.abs(vim.api.nvim_win_get_width(left) - vim.api.nvim_win_get_width(right)) <= 1)
eq("preset: the file stays in the first pane", vim.api.nvim_win_get_buf(first), vim.fn.bufnr(a))

first = one_pane()
ok("preset: triple starts", panes.preset "triple")
eq("preset: triple has three panes", #normal_wins(), 3)
local wins = sorted_wins()
eq("preset: triple in one row", vim.api.nvim_win_get_position(wins[1])[1], vim.api.nvim_win_get_position(wins[3])[1])
ok("preset: triple equal heights", vim.api.nvim_win_get_height(wins[1]) == vim.api.nvim_win_get_height(wins[2]))
ok(
  "preset: triple equal widths",
  math.abs(vim.api.nvim_win_get_width(wins[1]) - vim.api.nvim_win_get_width(wins[3])) <= 1
)

first = one_pane()
ok("preset: main starts", panes.preset "main")
eq("preset: main has three panes", #normal_wins(), 3)
local main_width = vim.api.nvim_win_get_width(first)
local others = vim.tbl_filter(function(win)
  return win ~= first
end, normal_wins())
ok("preset: main is wider", main_width > vim.api.nvim_win_get_width(others[1]))
eq(
  "preset: the right column shares a width",
  vim.api.nvim_win_get_width(others[1]),
  vim.api.nvim_win_get_width(others[2])
)
ok(
  "preset: the right column is stacked",
  vim.api.nvim_win_get_position(others[1])[1] ~= vim.api.nvim_win_get_position(others[2])[1]
)

first = one_pane()
ok("preset: quad starts", panes.preset "quad")
eq("preset: quad has four panes", #normal_wins(), 4)
local rows, cols = {}, {}
for _, win in ipairs(normal_wins()) do
  local pos = vim.api.nvim_win_get_position(win)
  rows[pos[1]] = (rows[pos[1]] or 0) + 1
  cols[pos[2]] = (cols[pos[2]] or 0) + 1
end
eq("preset: quad has two rows", vim.tbl_count(rows), 2)
eq("preset: quad has two columns", vim.tbl_count(cols), 2)
eq("preset: quad has two panes in each row", { rows[vim.tbl_keys(rows)[1]], rows[vim.tbl_keys(rows)[2]] }, { 2, 2 })
eq("preset: quad has two panes in each column", { cols[vim.tbl_keys(cols)[1]], cols[vim.tbl_keys(cols)[2]] }, { 2, 2 })

local top, left, bottom, right = box(normal_wins())
ok("preset: quad fills its box", bottom > top and right > left)

-- ── close every other pane ──────────────────────────────────────────────────
vim.api.nvim_set_current_win(normal_wins()[1])
ok("only: closes the other panes", panes.only())
eq("only: one pane left", #normal_wins(), 1)
eq("only: it says no with one", panes.only(), false)

print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd(fails == 0 and "qa!" or "cq!")
