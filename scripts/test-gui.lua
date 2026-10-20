-- Tests of the desktop app's config side (nvim/lua/gui/): the install checks, the welcome screen's lines and the app
-- bar's state. Run by scripts/test-app.sh with the real config loaded (headless; no window, the app is not needed).
local ROOT = vim.env.AGENT_TEST_ROOT
vim.opt.rtp:prepend(ROOT .. "/nvim")
for name in pairs(package.loaded) do
	if name == "gui" or name:find("^gui%.") then
		package.loaded[name] = nil
	end
end

local failures = 0
local function check(name, cond, detail)
	if cond then
		print("ok   " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. (detail and (": " .. vim.inspect(detail)) or ""))
	end
end

-- checks: every entry has its fields, and the ones that cannot be fixed from here say how
local checks = require("gui.checks")
local list = checks.run()
check("checks run", #list >= 8, #list)
local shaped = vim.iter(list):all(function(c)
	return type(c.id) == "string"
		and type(c.label) == "string"
		and type(c.ok) == "boolean"
		and type(c.detail) == "string"
end)
check("checks are shaped", shaped, list)
check("missing counts the failures", checks.missing({ { ok = true }, { ok = false }, { ok = false } }) == 2)

local function text(segs)
  return table.concat(vim.tbl_map(function(seg)
    return seg[1]
  end, segs))
end

-- system packages: the command for each Linux family, sudo only when needed, apt refreshes first, unpackaged tools said
local sysdeps = require "gui.sysdeps"
local fake = function(present)
  return function(bin)
    return vim.tbl_contains(present, bin)
  end
end
local rg = vim.iter(sysdeps.TOOLS):find(function(t)
  return t.id == "rg"
end)
local cc = vim.iter(sysdeps.TOOLS):find(function(t)
  return t.id == "cc"
end)
local by = function(id)
  return vim.iter(sysdeps.MANAGERS):find(function(m)
    return m.id == id
  end)
end
check("pacman command", sysdeps.command(by "pacman", { rg, cc }, false) == "sudo pacman -S --needed --noconfirm ripgrep base-devel", sysdeps.command(by "pacman", { rg, cc }, false))
check("apt refreshes first", sysdeps.command(by "apt", { rg }, false) == "sudo apt-get update && sudo apt-get install -y ripgrep")
check("root needs no sudo", sysdeps.command(by "dnf", { rg }, true) == "dnf install -y ripgrep")
local cmd, skipped = sysdeps.command(by "brew", { rg, cc }, false)
check("brew has no sudo and says what it lacks", cmd == "brew install ripgrep" and skipped[1] == "C compiler", { cmd, skipped })
check("manager in order", sysdeps.manager(fake { "dnf", "apt-get" }).id == "apt" and sysdeps.manager(fake {}) == nil)
local missing = vim.tbl_map(function(t)
  return t.id
end, sysdeps.missing(fake { "git", "rg", "cc", "unzip", "fd", "node", "npm", "cmake" }, { go = true, jvm = false }))
check("missing: only the runtimes of the packs that are on", vim.deep_equal(missing, { "go" }), missing)
check("node needs node and npm", not sysdeps.present(vim.iter(sysdeps.TOOLS):find(function(t)
  return t.id == "node"
end), fake { "node" }))
check("distro name", sysdeps.distro 'NAME="Arch"\nPRETTY_NAME="Arch Linux"\n' == "Arch Linux")

-- toolbar: the defaults, your choices on top (saved), the chips
local toolbar = require "gui.toolbar"
local left, right = toolbar.tools()
local actions = function(list)
  return vim.tbl_map(function(t)
    return t.action
  end, list)
end
check("default left tools", vim.deep_equal(actions(left), { "projects", "home", "history" }), actions(left))
check("default right tools", vim.deep_equal(actions(right), { "agent", "theme" }), actions(right))
check("tools carry a tooltip", vim.iter(right):all(function(t)
  return type(t.tip) == "string" and t.tip ~= ""
end), right)
require("gui.state").update { toolbar = { home = false, terminal = true, ["chip.lsp"] = true } }
left, right = toolbar.tools()
check("your choices win", not vim.tbl_contains(actions(left), "home") and vim.tbl_contains(actions(right), "terminal"), { actions(left), actions(right) })
check("chips follow your choices", toolbar.chips({}).lsp == true and toolbar.chips({}).recording == true)
require("gui.state").update { toolbar = { home = true, terminal = false, ["chip.lsp"] = false } }

-- the setup wizard: every step renders with choices, buttons sit on one row and a click picks by column
local wizard = require "gui.wizard"
local wm = wizard.open()
for i, st in ipairs(wizard.STEPS) do
  wizard.go(wm, i)
  check("wizard step " .. st.id .. " has choices", vim.tbl_count(wm.pane_rows) > 0 and wm.step == i, { wm.step, vim.tbl_count(wm.pane_rows) })
end
wizard.go(wm, 3)
local pack_line, pack_id
for line, item in pairs(wm.pane_rows) do
  if item.kind == "pack" and (not pack_line or line < pack_line) then
    pack_line, pack_id = line, item.id
  end
end
local before = wm.packs[pack_id]
wizard.choose(wm, wm.pane_rows[pack_line])
check("a pack toggles", wm.packs[pack_id] == not before)
wizard.choose(wm, wm.pane_rows[pack_line])
local buttons_row
for _, item in pairs(wm.pane_rows) do
  if item.kind == "buttons" then
    buttons_row = item
  end
end
check("buttons on one row", buttons_row and #buttons_row.chips == 2, buttons_row)
wizard.choose(wm, buttons_row, buttons_row.chips[2].from + 2)
check("a click on Back goes back", wm.step == 2, wm.step)
wizard.choose(wm, buttons_row)
check("Space on the row takes the first (Next)", wm.step == 3, wm.step)
require("utils.market").close(wm)

-- the theme menu previews and undoes; the agent menu lists what this machine has
local appearance = require "appearance"
local theme_before = appearance.current()
local titems, trevert = require("gui").theme_menu()
check("theme menu has dark and light", vim.iter(titems):any(function(it)
  return it.label == "Dark" and it.items and #it.items > 0
end))
local other = vim.iter(titems):find(function(it)
  return it.label == "Dark"
end).items[2]
other.preview()
trevert()
check("closing without a choice puts the theme back", appearance.current() == theme_before, appearance.current())
check("agent menu builds", #require("gui").agent_menu() >= 3)

-- app bar: the path of a real file, folders then the file, and the indent chip
local gui = require("gui")
vim.g.leader_gui = true -- what the app sets before the config loads; setup() only wires its autocmds inside the app
gui.setup()
local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/src/app", "p")
vim.cmd.cd(dir)
vim.cmd.edit("src/app/main.lua")
vim.bo.expandtab, vim.bo.shiftwidth = true, 4
require("core.settings").gui.appbar.show.indent = true -- off by default; the chip still has to work
local state = gui.state()
check("path is split into folders", vim.deep_equal(state.path, { "src", "app" }), state.path)
check("file is the name", state.file == "main.lua", state.file)
local indent = vim.iter(state.chips):find(function(c)
	return c.text == "␣4"
end)
check("indent chip", indent ~= nil, state.chips)
check(
	"colors are hex",
	type(state.colors.fg) == "string" and state.colors.fg:match("^#%x%x%x%x%x%x$") ~= nil,
	state.colors
)
check("toolbar and controls", #state.left >= 1 and state.left[1].action == "projects" and state.controls == "right", state)
check("project name on its tool", type(state.left[1].label) == "string" and state.left[1].label ~= "", state.left[1])
-- a special buffer keeps the file you were on
vim.cmd("enew")
vim.bo.buftype = "nofile"
local kept = gui.state()
check("special buffers keep the last file", kept.file == "main.lua", kept.file)
-- activity: LSP progress shows while it runs and says it is ready when it ends
local function progress(kind, extra)
	vim.api.nvim_exec_autocmds("LspProgress", {
		pattern = kind,
		data = {
			client_id = 999,
			params = { token = "t1", value = vim.tbl_extend("force", { kind = kind }, extra or {}) },
		},
	})
end
progress("begin", { title = "indexing", percentage = 10 })
vim.wait(50, function()
	return false
end)
local busy = gui.state().activity
check("progress shows while running", busy and busy.text:find("indexing") ~= nil and busy.percent == 10, busy)
progress("end")
local ready = gui.state().activity
check("progress says when it is done", ready and ready.done == true and ready.text:find("ready") ~= nil, ready)
check("actions exist", type(gui.actions.home) == "function" and type(gui.actions.history) == "function")

-- menus: rows, separators, keys right-aligned to one width; the app and projects menus are made of runnable items
local menu = require "gui.menu"
local lines, marks, width = menu.render {
  { label = "Open File…", hint = "Space f f", run = function() end },
  { sep = true },
  { label = "Quit", hint = ":qa", current = true, run = function() end },
}
check("menu rows", #lines == 3 and lines[2]:find "─" ~= nil, lines)
check("menu rows share one width", vim.fn.strdisplaywidth(lines[1]) == width and vim.fn.strdisplaywidth(lines[3]) == width, lines)
check("menu marks the current item", lines[3]:find "●" ~= nil, lines[3])
check("menu paints keys", vim.iter(marks):any(function(m)
  return m[4] == "GuiMenuHint"
end), marks)
local runnable
runnable = function(items)
  return vim.iter(items):all(function(it)
    return it.sep or type(it.run) == "function" or type(it.keys) == "string" or (it.items and runnable(it.items))
  end)
end
check("app menu items run", runnable(gui.app_menu()))

-- keys written for people, submenus, and the palette's flat list of everything the menus do
check("describe leader", menu.describe "<leader>fw" == "Space f w", menu.describe "<leader>fw")
check("describe ctrl shift", menu.describe "<C-S-r>" == "Ctrl+Shift+R", menu.describe "<C-S-r>")
check("describe alt", menu.describe "<M-i>" == "Alt+I", menu.describe "<M-i>")
local app = gui.app_menu()
local tops = vim.tbl_map(function(it)
  return it.label
end, menu.visible(app))
for _, want in ipairs { "File", "Edit", "Selection", "View", "Go", "Run", "Agent", "Window", "Help" } do
  check("app menu has " .. want, vim.tbl_contains(tops, want), tops)
end
local flat = menu.flatten(app)
local save = vim.iter(flat):find(function(e)
  return e.path == "File › Save"
end)
check("palette paths", save ~= nil and save.item.keys == "<C-s>", save)
check("separators never lead or double", vim.iter(menu.visible { { sep = true }, { label = "a" }, { sep = true }, { sep = true }, { label = "b" }, { sep = true } }):fold(0, function(n, it)
  return n + (it.sep and 1 or 0)
end) == 1)

-- the mouse: chips found from the segments that drew them, chip words as keys, hover marks the buffer
local umouse = require "utils.mouse"
local chips = umouse.chips({ { "  " }, { " y Delete ", "NvModalBtn" }, { "  " }, { " Esc Cancel ", "NvModalBtn2" } }, function(g)
  return g ~= nil
end)
check("chips columns", #chips == 2 and chips[1].from == 2 and chips[1].to == 12 and chips[2].key == "Esc", chips)
check("chip keys", umouse.keys "Esc" == "<Esc>" and umouse.keys "⏎" == "<CR>" and umouse.keys "y" == "y")
local hb = vim.api.nvim_create_buf(false, true)
umouse.on(hb, { move = function() end, click = function() end })
check("hover marks the buffer", vim.b[hb].leader_hover == true)
local maps = vim.tbl_map(function(m)
  return m.lhs
end, vim.api.nvim_buf_get_keymap(hb, "n"))
check("hover and click are mapped", vim.tbl_contains(maps, "<MouseMove>") and vim.tbl_contains(maps, "<LeftRelease>"), maps)
vim.api.nvim_set_current_buf(hb)
umouse.sync()
check("mousemoveevent follows the focused buffer", vim.o.mousemoveevent == true)
vim.cmd "enew"
umouse.sync()
check("and goes off elsewhere", vim.o.mousemoveevent == false)

-- hover in the menus: the pointer over "View" lights it and opens its submenu beside it; over a plain item it closes
local function pointer(winid, line, column)
  local real = vim.fn.getmousepos
  vim.fn.getmousepos = function()
    return { winid = winid, line = line, column = column or 3 }
  end
  return function()
    vim.fn.getmousepos = real
  end
end
local function fire(lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
    if m.lhs == lhs and m.callback then
      return m.callback()
    end
  end
end
local function floats()
  return #vim.tbl_filter(function(w)
    return vim.api.nvim_win_get_config(w).relative ~= ""
  end, vim.api.nvim_list_wins())
end
menu.open(gui.app_menu(), { col = 2 })
local root = vim.api.nvim_get_current_win()
local view_row, plain_row
for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
  if l:find "View" then
    view_row = i
  elseif l:find "Home" then
    plain_row = i
  end
end
local restore = pointer(root, view_row)
fire "<MouseMove>"
restore()
check("hover moves the selection", vim.api.nvim_win_get_cursor(root)[1] == view_row)
check("hover opens the submenu", floats() == 2, floats())
check("the keyboard stays on the menu under the pointer", vim.api.nvim_get_current_win() == root)
restore = pointer(root, plain_row)
fire "<MouseMove>"
restore()
check("a plain item closes the submenu", floats() == 1, floats())
menu.close()
check("closing leaves no menu", floats() == 0, floats())

-- hover in the project picker (utils/market.lua): the row under the pointer is selected and the pane follows
local mk = require("gui.picker").open()
local target
for i, r in ipairs(mk.rows) do
  if r.start == "clone" then
    target = i
  end
end
restore = pointer(mk.wins.list, target)
fire "<MouseMove>"
restore()
check("picker hover selects", vim.api.nvim_win_get_cursor(mk.wins.list)[1] == target)
local pane_text = table.concat(vim.api.nvim_buf_get_lines(mk.bufs.pane, 0, -1, false), " ")
check("picker pane follows the hover", pane_text:find "git clone" ~= nil, pane_text)
check("picker key chips are known", mk.chips and #mk.chips.list >= 4, mk.chips)
require("utils.market").close(mk)

-- a click on a modal's button presses its key
local said_yes = false
require("utils.modal").confirm({ "Sure?" }, { title = "Test", confirm = "Do it" }, function()
  said_yes = true
end)
local mwin = vim.api.nvim_get_current_win()
local yrow, ycol
for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
  local c = l:find " y Do it "
  if c then
    yrow, ycol = i, c + 1
  end
end
restore = pointer(mwin, yrow, ycol)
fire "<LeftRelease>"
restore()
vim.api.nvim_feedkeys("", "x", false)
check("a click on a modal button presses it", said_yes == true)

-- projects: remembered newest first, without duplicates; home is not a project; the menu marks where you are
local projects = require "gui.projects"
local a, b = vim.fn.tempname(), vim.fn.tempname()
vim.fn.mkdir(a, "p")
vim.fn.mkdir(b, "p")
projects.remember(a)
projects.remember(b)
projects.remember(a)
projects.remember "~"
local dirs = vim.tbl_map(function(p)
  return p.dir
end, projects.list())
local once = #vim.tbl_filter(function(d)
  return d == projects.normalize(a)
end, dirs) == 1
check("projects newest first, once", dirs[1] == projects.normalize(a) and dirs[2] == projects.normalize(b) and once, dirs)
check("home is not a project", not vim.tbl_contains(dirs, projects.normalize "~"), dirs)
vim.cmd.cd(a)
local pm = gui.projects_menu()
check("projects menu marks the current one", pm[1].current == true and pm[2].current == false, pm)
check("projects menu items run", runnable(pm))
projects.forget(b)
check("forget removes it", not vim.iter(projects.list()):any(function(p)
  return p.dir == projects.normalize(b)
end))

-- the project picker: groups, the start rows, and a pane with the facts of a real git project
local picker = require "gui.picker"
local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")
vim.fn.writefile({ "module x" }, repo .. "/go.mod")
vim.fn.writefile({ "# Hello", "a project" }, repo .. "/README.md")
vim.system({ "git", "init", "-q", repo }):wait()
vim.system({ "git", "-C", repo, "-c", "user.email=t@t", "-c", "user.name=t", "add", "." }):wait()
vim.system({ "git", "-C", repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "first commit" }):wait()
local pm_state = { recent = { { dir = repo, at = os.time() - 7200 } }, found = { { dir = a } }, filter = "", info = {} }
local prow = picker.rows(pm_state)
local kinds = vim.tbl_map(function(r)
  return r.group or (r.project and "project") or r.start or r.note or (r.title and "title") or "spacer"
end, prow)
check("picker groups", vim.tbl_contains(kinds, "Recent") and vim.tbl_contains(kinds, "On this machine") and vim.tbl_contains(kinds, "clone"), kinds)
local pane = picker.pane(pm_state, { project = pm_state.recent[1] }, 80)
local text = table.concat(vim.tbl_map(function(l)
  return table.concat(vim.tbl_map(function(seg)
    return seg[1]
  end, l))
end, pane), "\n")
check("pane shows the commit", text:find "first commit" ~= nil, text)
check("pane shows the stack", text:find "Go" ~= nil, text)
check("pane shows the readme", text:find "# Hello" ~= nil, text)
check("pane says when it was opened", text:find "2 hours ago" ~= nil, text)
pm_state.filter = "zzz-nothing"
check("filter hides what does not match", not vim.iter(picker.rows(pm_state)):any(function(r)
  return r.project ~= nil
end))

-- switching: the folder changes, it is remembered, and with no session there the start screen opens
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  pcall(function()
    vim.bo[buf].modified = false
  end)
end
projects.switch(b)
check("switch changes folder", projects.normalize(vim.uv.cwd()) == projects.normalize(b), vim.uv.cwd())
check("switch remembers it", projects.list()[1].dir == projects.normalize(b), projects.list()[1])
check("no session: start screen", vim.bo.filetype == "nvdash", vim.bo.filetype)

print(failures == 0 and "ALL OK" or ("FAILURES: " .. failures))
vim.cmd(failures == 0 and "qa!" or "cq!")
