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

print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd(fails == 0 and "qa!" or "cq!")
