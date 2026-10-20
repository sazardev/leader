-- Tests of the desktop app's config side (nvim/lua/gui/): the install checks, the welcome screen's lines and the app
-- bar's state. Run by scripts/test-app.sh with the real config loaded (headless; no window, the app is not needed).
local ROOT = vim.env.AGENT_TEST_ROOT
vim.opt.rtp:prepend(ROOT .. "/nvim")
for name in pairs(package.loaded) do
  if name == "gui" or name:find "^gui%." then
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
local checks = require "gui.checks"
local list = checks.run()
check("checks run", #list >= 8, #list)
local shaped = vim.iter(list):all(function(c)
  return type(c.id) == "string" and type(c.label) == "string" and type(c.ok) == "boolean" and type(c.detail) == "string"
end)
check("checks are shaped", shaped, list)
check("missing counts the failures", checks.missing { { ok = true }, { ok = false }, { ok = false } } == 2)

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
check(
  "pacman command",
  sysdeps.command(by "pacman", { rg, cc }, false) == "sudo pacman -S --needed --noconfirm ripgrep base-devel",
  sysdeps.command(by "pacman", { rg, cc }, false)
)
check(
  "apt refreshes first",
  sysdeps.command(by "apt", { rg }, false) == "sudo apt-get update && sudo apt-get install -y ripgrep"
)
check("root needs no sudo", sysdeps.command(by "dnf", { rg }, true) == "dnf install -y ripgrep")
local cmd, skipped = sysdeps.command(by "brew", { rg, cc }, false)
check(
  "brew has no sudo and says what it lacks",
  cmd == "brew install ripgrep" and skipped[1] == "C compiler",
  { cmd, skipped }
)
check("manager in order", sysdeps.manager(fake { "dnf", "apt-get" }).id == "apt" and sysdeps.manager(fake {}) == nil)
local missing = vim.tbl_map(function(t)
  return t.id
end, sysdeps.missing(fake { "git", "rg", "cc", "unzip", "fd", "node", "npm", "cmake" }, { go = true, jvm = false }))
check("missing: only the runtimes of the packs that are on", vim.deep_equal(missing, { "go" }), missing)
check("node needs node and npm", not sysdeps.present(
  vim.iter(sysdeps.TOOLS):find(function(t)
    return t.id == "node"
  end),
  fake { "node" }
))
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
check(
  "tools carry a tooltip",
  vim.iter(right):all(function(t)
    return type(t.tip) == "string" and t.tip ~= ""
  end),
  right
)
require("gui.state").update { toolbar = { home = false, terminal = true, ["chip.lsp"] = true } }
left, right = toolbar.tools()
check(
  "your choices win",
  not vim.tbl_contains(actions(left), "home") and vim.tbl_contains(actions(right), "terminal"),
  { actions(left), actions(right) }
)
check("chips follow your choices", toolbar.chips({}).lsp == true and toolbar.chips({}).recording == true)
require("gui.state").update { toolbar = { home = true, terminal = false, ["chip.lsp"] = false } }

-- the setup wizard: full screen (no statusline), every step renders choices, Next waits for the step to be ready,
-- choices toggle, Back works and the mouse has a region per choice
local wizard = require "gui.wizard"
local status_before = vim.o.laststatus
local wm = wizard.open()
check("wizard hides the statusline", vim.o.laststatus == 0, vim.o.laststatus)
for i, st in ipairs(wizard.STEPS) do
  wizard.go(wm, i)
  local text = table.concat(vim.api.nvim_buf_get_lines(wm.buf, 0, -1, false), "\n")
  check(
    "wizard step " .. st.id .. " renders",
    wm.step == i and (#wm.items > 0 or st.id == "welcome") and text:find(st.title, 1, true) ~= nil,
    { wm.step, #wm.items }
  )
  check("wizard step " .. st.id .. " has a way on", vim.iter(wm.buttons):any(function(b)
    return b.primary
  end) or i == #wizard.STEPS, wm.buttons)
end
check(
  "every choice is a mouse region",
  vim.iter(wm.regions):any(function(r)
    return r.hit.kind == "item"
  end)
)
wizard.go(wm, 2)
wm.theme = nil
wizard.next(wm)
check("no theme, no next", wm.step == 2, wm.step)
wizard.go(wm, 3)
local first
for i, it in ipairs(wm.items) do
  if it.mark == "check" then
    first = first or i
  end
end
local before = wm.items[first].on
wizard.choose(wm, first)
check("a pack toggles", wm.items[first].on == not before, { before, wm.items[first].on })
wizard.choose(wm, first)
local basics = #wm.items
wizard.choose(wm, basics)
check("only the basics unchecks the packs and is ready", wm.items[first].on == false and wm.items[basics].on == true)
wizard.next(wm)
check("ready, next goes on", wm.step == 4, wm.step)
for _, b in ipairs(wm.buttons) do
  if b.left then
    b.press()
  end
end
check("Back goes back", wm.step == 3, wm.step)
wizard.close(wm)
check("closing brings the statusline back", vim.o.laststatus == status_before, vim.o.laststatus)

-- the lists (utils/market.lua, here the project picker): the chosen row is lit whole with a bar, no cursor block,
-- l / → only move to the details and h / ← come back
local cursor_before = vim.o.guicursor
local pm = require("gui.picker").open()
check("the list lights the whole row", vim.wo[pm.wins.list].cursorlineopt == "line")
check("no cursor block over the list", vim.o.guicursor:find("NvStartCursor", 1, true) ~= nil)
check(
  "a bar marks the chosen row",
  #vim.api.nvim_buf_get_extmarks(pm.bufs.list, vim.api.nvim_create_namespace "MarketSel", 0, -1, {}) == 1
)
vim.api.nvim_feedkeys("l", "xt", false)
check("l goes to the details", vim.api.nvim_get_current_win() == pm.wins.pane)
vim.api.nvim_feedkeys("h", "xt", false)
check("h comes back to the list", vim.api.nvim_get_current_win() == pm.wins.list)
require("utils.market").close(pm)
check("the cursor comes back", vim.o.guicursor == cursor_before, vim.o.guicursor)

-- the theme menu previews and undoes; the agent menu lists what this machine has
local appearance = require "appearance"
local theme_before = appearance.current()
local titems, trevert = require("gui").theme_menu()
check(
  "theme menu has dark and light",
  vim.iter(titems):any(function(it)
    return it.label == "Dark" and it.items and #it.items > 0
  end)
)
local other = vim.iter(titems):find(function(it)
  return it.label == "Dark"
end).items[2]
other.preview()
trevert()
check("closing without a choice puts the theme back", appearance.current() == theme_before, appearance.current())
check("agent menu builds", #require("gui").agent_menu() >= 3)

-- app bar: the path of a real file, folders then the file, and the indent chip
local gui = require "gui"
vim.g.leader_gui = true -- what the app sets before the config loads; setup() only wires its autocmds inside the app
gui.setup()
local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/src/app", "p")
vim.cmd.cd(dir)
vim.cmd.edit "src/app/main.lua"
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
  type(state.colors.fg) == "string" and state.colors.fg:match "^#%x%x%x%x%x%x$" ~= nil,
  state.colors
)
check(
  "toolbar and controls",
  #state.left >= 1 and state.left[1].action == "projects" and state.controls == "right",
  state
)
check("project name on its tool", type(state.left[1].label) == "string" and state.left[1].label ~= "", state.left[1])
-- a special buffer keeps the file you were on
vim.cmd "enew"
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
check("progress shows while running", busy and busy.text:find "indexing" ~= nil and busy.percent == 10, busy)
progress "end"
local ready = gui.state().activity
check("progress says when it is done", ready and ready.done == true and ready.text:find "ready" ~= nil, ready)
check("actions exist", type(gui.actions.home) == "function" and type(gui.actions.history) == "function")

-- menus: rows, separators, keys right-aligned to one width; the app and projects menus are made of runnable items
local menu = require "gui.menu"
local lines, marks, width = menu.render {
  { label = "Open File…", hint = "Space f f", run = function() end },
  { sep = true },
  { label = "Quit", hint = ":qa", current = true, run = function() end },
}
check("menu rows", #lines == 3 and lines[2]:find "─" ~= nil, lines)
check(
  "menu rows share one width",
  vim.fn.strdisplaywidth(lines[1]) == width and vim.fn.strdisplaywidth(lines[3]) == width,
  lines
)
check("menu marks the current item", lines[3]:find "●" ~= nil, lines[3])
check(
  "menu paints keys",
  vim.iter(marks):any(function(m)
    return m[4] == "GuiMenuHint"
  end),
  marks
)
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
check("separators never lead or double", vim
  .iter(menu.visible {
    { sep = true },
    { label = "a" },
    { sep = true },
    { sep = true },
    { label = "b" },
    { sep = true },
  })
  :fold(0, function(n, it)
    return n + (it.sep and 1 or 0)
  end) == 1)

-- the mouse: chips found from the segments that drew them, chip words as keys, hover marks the buffer
local umouse = require "utils.mouse"
local chips = umouse.chips(
  { { "  " }, { " y Delete ", "NvModalBtn" }, { "  " }, { " Esc Cancel ", "NvModalBtn2" } },
  function(g)
    return g ~= nil
  end
)
check("chips columns", #chips == 2 and chips[1].from == 2 and chips[1].to == 12 and chips[2].key == "Esc", chips)
check("chip keys", umouse.keys "Esc" == "<Esc>" and umouse.keys "⏎" == "<CR>" and umouse.keys "y" == "y")
local hb = vim.api.nvim_create_buf(false, true)
umouse.on(hb, { move = function() end, click = function() end })
check("hover marks the buffer", vim.b[hb].leader_hover == true)
local maps = vim.tbl_map(function(m)
  return m.lhs
end, vim.api.nvim_buf_get_keymap(hb, "n"))
check(
  "hover and click are mapped",
  vim.tbl_contains(maps, "<MouseMove>") and vim.tbl_contains(maps, "<LeftRelease>"),
  maps
)
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
check(
  "projects newest first, once",
  dirs[1] == projects.normalize(a) and dirs[2] == projects.normalize(b) and once,
  dirs
)
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
check(
  "picker groups",
  vim.tbl_contains(kinds, "Recent") and vim.tbl_contains(kinds, "On this machine") and vim.tbl_contains(kinds, "clone"),
  kinds
)
local function pane_of(st)
  return table.concat(
    vim.tbl_map(function(l)
      return table.concat(vim.tbl_map(function(seg)
        return seg[1]
      end, l))
    end, picker.pane(st, { project = st.recent[1] }, 80)),
    "\n"
  )
end
-- git is read in the background: the pane says so first, then the facts arrive and are saved with the stamp
local text = pane_of(pm_state)
check("pane reads git in the background", text:find("reading git", 1, true) ~= nil, text)
vim.wait(5000, function()
  return not pm_state.info[repo].pending
end)
text = pane_of(pm_state)
check("pane shows the commit", text:find "first commit" ~= nil, text)
check("pane shows the branch", text:find("clean", 1, true) ~= nil, text)
local cache = require "gui.projcache"
check("the facts are saved", cache.info(repo, cache.stamp(repo)) ~= nil)
local again = { recent = pm_state.recent, found = {}, filter = "", info = {} }
check("another opening needs no git", pane_of(again):find "first commit" ~= nil and not again.info[repo].pending)
vim.fn.writefile({ "x" }, repo .. "/new.txt")
vim.system({ "git", "-C", repo, "add", "new.txt" }):wait()
check("a change to the project drops the saved facts", cache.info(repo, cache.stamp(repo)) == nil)
cache.save()
cache.reset()
check("the cache survives a restart", cache.get().info[repo] ~= nil)
check(
  "git status: branch and changes",
  vim.deep_equal({ picker.parse_status "## main...origin/main [ahead 1]\n M a.lua\n?? b" }, { "main", 2 })
)
check("git status: no commits yet", picker.parse_status "## No commits yet on dev" == "dev")
check("git status: detached", picker.parse_status "## HEAD (no branch)" == "HEAD (detached)")
check("pane shows the stack", text:find "Go" ~= nil, text)
check("pane shows the readme", text:find "# Hello" ~= nil, text)
check("pane says when it was opened", text:find "2 hours ago" ~= nil, text)
pm_state.filter = "zzz-nothing"
check("filter hides what does not match", not vim.iter(picker.rows(pm_state)):any(function(r)
  return r.project ~= nil
end))

-- pinning: a pinned project stays first and is never dropped for newer ones; the picker shows it in Pinned
projects.pin(repo, true)
check("pin", projects.pinned(repo))
local pins = { recent = projects.list(), found = {}, filter = "", info = {} }
local first_group
for _, r in ipairs(picker.rows(pins)) do
  first_group = first_group or r.group
end
check("pinned projects come first", first_group == "Pinned", first_group)
check("pinned ones are not in Recent too", #vim.tbl_filter(function(r)
  return r.project and r.project.dir == projects.normalize(repo)
end, picker.rows(pins)) == 1)
local many = { { dir = "/pinned", pinned = true } }
for i = 1, 40 do
  many[#many + 1] = { dir = "/p" .. i, at = i }
end
check("trimming keeps the pinned", vim.iter(projects.trim(many)):any(function(p)
  return p.dir == "/pinned"
end) and #many == 30, #many)
projects.pin(repo, false)
check("unpin", not projects.pinned(repo))
-- a file that is not a list (another tool wrote it) is not a list of projects, and does not break the picker
local projects_file = vim.fn.stdpath "state" .. "/leader-projects.json"
local saved_projects = vim.fn.readfile(projects_file)
vim.fn.writefile({ vim.json.encode { found = {}, info = {} } }, projects_file)
check("a file that is not a list gives no projects", #projects.list() == 0)
vim.fn.writefile(saved_projects, projects_file)
check("the picker's cache has its own file", require("gui.projcache").FILE ~= projects_file)

-- opening the picker again (the saved list is fresh, nothing is searched) still draws every project: it did not
local pcache = require "gui.projcache"
pcache.set_found { a, b }
local again_pm = require("gui.picker").open()
local shown_projects = vim.tbl_filter(function(r)
  return r.project ~= nil
end, again_pm.rows)
check("a fresh cache still lists the projects found", #shown_projects >= 2 and not again_pm.searching, #shown_projects)
require("utils.market").close(again_pm)

-- the folder browser: folders of a directory, in, up, hidden, the project row it starts on
local browse = require "gui.browse"
local tree = vim.fn.tempname()
for _, d in ipairs { "alpha/inner", "beta", ".hidden", "gamma/.git" } do
  vim.fn.mkdir(tree .. "/" .. d, "p")
end
vim.fn.writefile({ "x" }, tree .. "/file.txt")
local bm = browse.open(tree)
local function folders()
  return vim.tbl_map(
    function(r)
      return r.name
    end,
    vim.tbl_filter(function(r)
      return r.dir ~= nil
    end, bm.rows)
  )
end
check(
  "browser lists folders, not files or hidden ones",
  vim.deep_equal(folders(), { "alpha", "beta", "gamma" }),
  folders()
)
vim.api.nvim_feedkeys(".", "xt", false)
check("browser: . shows hidden folders", vim.tbl_contains(folders(), ".hidden"), folders())
vim.api.nvim_feedkeys(".", "xt", false)
local at = vim.iter(ipairs(bm.rows)):find(function(_, r)
  return r.name == "alpha"
end)
vim.api.nvim_win_set_cursor(bm.wins.list, { at, 0 })
vim.api.nvim_feedkeys("l", "xt", false)
check(
  "browser: l goes in",
  bm.dir == require("gui.projects").normalize(tree .. "/alpha") and vim.deep_equal(folders(), { "inner" }),
  bm.dir
)
vim.api.nvim_feedkeys("h", "xt", false)
local row = require("utils.market").current(bm)
check(
  "browser: h goes up onto the folder it came from",
  bm.dir == require("gui.projects").normalize(tree) and row.name == "alpha",
  row
)
local pane_text = table.concat(
  vim.tbl_map(function(l)
    return table.concat(vim.tbl_map(function(seg)
      return seg[1]
    end, l))
  end, browse.pane(bm, row, 80)),
  "\n"
)
check("browser: the pane lists what the folder holds", pane_text:find("inner/", 1, true) ~= nil, pane_text)
require("utils.market").close(bm)

-- the hidden cursor has ONE owner list: pages opened over one another never leave it hidden
local cursor = require "utils.cursor"
cursor.reset()
local shown = vim.o.guicursor
local p1, p2 = {}, {}
cursor.hide(p1)
cursor.hide(p2, "nv")
check("hidden while a page owns it", cursor.is_hidden(vim.o.guicursor))
cursor.show(p1)
check("still hidden (in normal mode) while another owns it", vim.o.guicursor:find("n-v:NvStartCursor", 1, true) ~= nil)
cursor.show(p2)
check("back to the real cursor when the last lets go", vim.o.guicursor == shown, vim.o.guicursor)
cursor.hide(p1)
cursor.hide(p1)
cursor.show(p1)
check("hiding twice and showing once is enough", vim.o.guicursor == shown, vim.o.guicursor)
-- a value that is already hidden is never taken as the real one (what used to leave it invisible for good)
vim.o.guicursor = "a:NvStartCursor"
cursor.hide(p1)
cursor.show(p1)
check("a hidden value is never the one restored", not cursor.is_hidden(vim.o.guicursor), vim.o.guicursor)
vim.o.guicursor = "a:NvStartCursor"
cursor.repair()
check("repair: hidden with no owner is put right", not cursor.is_hidden(vim.o.guicursor), vim.o.guicursor)
vim.o.guicursor = shown
local wiz = require("gui.wizard").open()
local over = require("gui.picker").open()
require("gui.wizard").close(wiz)
require("utils.market").close(over)
check("setup and list over one another leave the cursor visible", vim.o.guicursor == shown, vim.o.guicursor)

-- install progress: formatting, a tracker over a fake Mason (waiting → running → done, speed, stalls, failures)
local progress = require "gui.progress"
check(
  "bytes",
  progress.bytes(812) == "812 B"
    and progress.bytes(12.7 * 1024 * 1024) == "12.7 MB"
    and progress.bytes(30 * 1024) == "30 KB"
)
check("rate", progress.rate(31 * 1024) == "31 KB/s")
check("durations", progress.dur(45) == "45s" and progress.dur(400) == "6m 40s" and progress.dur(3900) == "1h 05m")
check(
  "rough time left is never precise",
  progress.about(20) == "less than a minute" and progress.about(100) == "about 2 min"
)
check("bar", progress.bar(0.5, 10) == "█████░░░░░" and progress.bar(2, 4) == "████")
local fake = { installed = {}, installing = {}, bytes = {} }
local env = {
  installed = function(n)
    return fake.installed[n] == true
  end,
  installing = function(n)
    return fake.installing[n] == true
  end,
  bytes = function(n)
    return fake.bytes[n] or 0
  end,
}
local tr = progress.new({ "a", "b", "c", "d" }, env, 100)
progress.poll(tr, 101)
check("everything waits at first", progress.summary(tr, 101).waiting == 4)
fake.installing.a, fake.bytes.a = true, 1000
progress.poll(tr, 102)
fake.bytes.a = 51000
progress.poll(tr, 103)
check(
  "a running item has bytes and a speed",
  tr.items[1].state == "running" and tr.items[1].bytes == 51000 and tr.items[1].rate > 10000,
  tr.items[1]
)
check(
  "describe: numbers",
  progress.describe(tr.items[1], 104):find("downloading 50 KB", 1, true) ~= nil,
  progress.describe(tr.items[1], 104)
)
for t = 104, 130 do
  progress.poll(tr, t) -- no new byte
end
local said, stalled = progress.describe(tr.items[1], 131)
check("no data for a while says so", stalled and said:find("no data for", 1, true) ~= nil, said)
fake.installing.a, fake.installed.a = false, true
progress.poll(tr, 132)
check("an installed one is done", tr.items[1].state == "done")
fake.installed.b, fake.installed.c = true, true
progress.poll(tr, 140)
local sum = progress.summary(tr, 150)
check(
  "counts and a rough time left after three",
  sum.done == 3 and sum.total == 4 and sum.left ~= nil and math.abs(sum.fraction - 0.75) < 1e-9,
  sum
)
progress.finish(tr, 160)
sum = progress.summary(tr, 999)
check(
  "what Mason did not install failed",
  sum.failed == 1 and tr.items[4].state == "failed" and not tr.active and sum.elapsed == 60,
  sum
)
local status, pct = progress.status_text(progress.new({ "x" }, env, 0), 5)
check("status text for the bar", status == "0/1 · 5s" and pct == 0, status)
local shown = progress.lines(tr, 170, 100, "⠋")
check(
  "lines: header, bar, a row per tool",
  #shown >= 3 + 4 and shown[1][1][1]:find("3 of 4", 1, true) == nil and shown[1][1][1]:find("4 of 4", 1, true) ~= nil,
  shown[1]
)
check(
  "dir_bytes counts files in folders",
  (function()
    local d = vim.fn.tempname()
    vim.fn.mkdir(d .. "/sub", "p")
    vim.fn.writefile({ string.rep("x", 99) }, d .. "/a")
    vim.fn.writefile({ string.rep("x", 49) }, d .. "/sub/b")
    return progress.dir_bytes(d) == 100 + 50
  end)()
)

-- a list that fails half way opens nothing: no windows left behind that cannot be closed, the cursor comes back
local wins_before = #vim.api.nvim_list_wins()
local cursor_was = vim.o.guicursor
local errors = {}
local notify = vim.notify
vim.notify = function(msg)
  errors[#errors + 1] = msg
end
local broken = require("utils.market").new {
  rows = function()
    return { { x = 1 } }
  end,
  selectable = function()
    return true
  end,
  list_line = function()
    error "a bad row"
  end,
  pane = function()
    return {}
  end,
  summary = function()
    return {}
  end,
  hints = function()
    return {}
  end,
}
vim.notify = notify
check(
  "a market that fails opens nothing",
  broken == nil
    and #vim.api.nvim_list_wins() == wins_before
    and #errors == 1
    and errors[1]:find("a bad row", 1, true) ~= nil,
  errors
)
check("and the cursor is back", vim.o.guicursor == cursor_was, vim.o.guicursor)

-- long background work says how long it has been going
check("elapsed: seconds", require("gui").elapsed(12400) == "12s")
check("elapsed: minutes", require("gui").elapsed(125000) == "2m 05s")

-- what opens at start: a folder argument, a repo you start in, otherwise the on_start choice
local startup = require "gui.startup"
local home = vim.uv.os_homedir()
local base_ctx = { args = {}, empty = true, cwd = home, on_start = "ask", first_launch = false, last = repo }
local function decide(over)
  return { startup.decide(vim.tbl_extend("force", base_ctx, over or {})) }
end
check("start: ask by default", decide()[1] == "ask")
check("start: a folder argument is the project", vim.deep_equal(decide { args = { repo } }, { "enter", repo }))
check("start: files open as they are", decide({ args = { repo .. "/go.mod" } })[1] == nil)
check("start: inside a repo, that repo", vim.deep_equal(decide { cwd = repo }, { "enter", repo }))
check("start: last project", vim.deep_equal(decide { on_start = "last" }, { "enter", repo }))
check("start: start screen", decide({ on_start = "home" })[1] == nil)
check("start: nothing asked under the first setup", decide({ first_launch = true })[1] == nil)
check("start: home is not a project", not startup.is_project(home))

-- the window settings: in the settings panel's App group, and they reach the app with the bar's state
local prefs = require "prefs"
local keep = prefs.find "gui.window.remember_size"
check("window settings are settings", keep ~= nil and prefs.find "gui.window.on_start" ~= nil)
prefs.set(keep, false)
check("remember size off reaches the app", require("gui").state().window.size == false)
prefs.set(keep, true)
check("remember size on again", require("gui").state().window.size == true)

-- the pointer never scrolls a list: hovering the last visible row keeps the view where it is
local sbuf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(sbuf, 0, -1, false, vim.tbl_map(tostring, vim.fn.range(1, 200)))
local swin = vim.api.nvim_open_win(sbuf, false, { relative = "editor", row = 0, col = 0, width = 20, height = 10 })
vim.wo[swin].scrolloff = 5
require("utils.mouse").follow(swin, vim.fn.line("w$", swin))
check("hover does not scroll", vim.fn.line("w0", swin) == 1, vim.fn.line("w0", swin))
vim.api.nvim_win_close(swin, true)

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
