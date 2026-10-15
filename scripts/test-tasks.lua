-- Tests of the project tasks (nvim/lua/tasks): Make's database and text parsers, Make against a real `make`, finding the
-- Makefile up to the git root, "works only with a Makefile", the cache, quoting and running (the terminal is a stub), "run last",
-- the arguments modal, the menu and the Makefile presets (every one is checked by a real make). Hermetic: temp projects, a
-- throwaway state dir, no network or tokens.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-tasks.lua"
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

local util = require "tasks.util"
local tasks = require "tasks"
local exec = require "tasks.exec"
local store = require "tasks.store"

local function names(list)
  return vim.tbl_map(function(t)
    return t.name
  end, list)
end

-- a temporary project: `files` = { relative path = text }, with a .git so the search stops at it
local base = vim.fn.tempname()
local function project(name, files)
  local dir = base .. "/" .. name
  vim.fn.mkdir(dir .. "/.git", "p")
  for rel, text in pairs(files) do
    vim.fn.mkdir(vim.fs.dirname(dir .. "/" .. rel), "p")
    local f = assert(io.open(dir .. "/" .. rel, "w"))
    f:write(text)
    f:close()
  end
  return dir
end

-- ── shell words ─────────────────────────────────────────────────────────────
eq("quote: plain words stay plain", util.quote { "make", "test" }, "make test")
eq("quote: paths and flags stay plain", util.quote { "go", "test", "./...", "-run=A/b" }, "go test ./... -run=A/b")
ok("quote: a space is quoted", util.quote({ "echo", "a b" }):find("'a b'", 1, true) ~= nil)
eq("text: vim.NIL and blanks are no text", { util.text(vim.NIL), util.text "  ", util.text " x " }, { nil, nil, "x" })

-- ── make: the database and the Makefile's text ──────────────────────────────
local make = require "tasks.make"
local db = make.parse_db [[
# GNU Make 4.3
.DEFAULT_GOAL := build
.PHONY: build test
.PHONY: lint build
]]
eq("make db: phony targets, once each, and the default goal", db, { phony = { "build", "test", "lint" }, default = "build" })

local src = make.parse_file {
  "VERSION := 1 ## not a target",
  "# ----------",
  "# Build the app",
  "build: deps ## Build everything",
  "\tgo build",
  ".PHONY: build \\",
  "  test",
  "",
  "# Run the tests",
  "test:",
  "\tgo test",
  "# License text",
  "",
  "clean:",
  "\trm -rf out",
  "pkg/%.o: pkg/%.c",
  "FOO=bar:baz",
}
eq("make file: targets in file order, no variables or pattern rules", src.order, { "build", "test", "clean" })
eq("make file: .PHONY with a continuation", src.phony, { "build", "test" })
eq("make file: ## beats the comment above; the comment above needs to be right above; variables have no description", src.desc, {
  build = "Build everything",
  test = "Run the tests",
})

local built = make.build("/p", nil, src)
eq("make build: the .PHONY ones, in the file's order", names(built), { "build", "test" })
eq("make build: the first target is the default without GNU make", built[1].default, true)
eq("make build: command, dry run and where", { built[2].cmd, built[2].dry, built[2].cwd }, { { "make", "test" }, { "make", "-n", "test" }, "/p" })
local nophony = make.build("/p", nil, make.parse_file { "all: a", "a: ## say a", "b:" })
eq("make build: no .PHONY → the described ones", names(nophony), { "a" })
local nothing = make.build("/p", nil, make.parse_file { "all:", ".hidden:", "x/y:" })
eq("make build: nothing described → every target, but not hidden or paths", names(nothing), { "all" })
eq("make build: the database's default goal wins", (function()
  local list = make.build("/p", { phony = { "a", "b" }, default = "b" }, make.parse_file { "a:", "b:" })
  return { list[1].default, list[2].default }
end)(), { nil, true })

-- ── make against a real make ────────────────────────────────────────────────
if vim.fn.executable "make" == 1 then
  local dir = project("real", {
    Makefile = table.concat({
      "include extra.mk",
      ".DEFAULT_GOAL := build",
      ".PHONY: build test",
      "build: ## Build everything",
      "\t@echo building",
      "test: build",
      "\t@echo testing",
      "# Remove artifacts",
      "clean:",
      "\t@rm -rf out",
      "",
    }, "\n"),
    ["extra.mk"] = ".PHONY: lint\nlint:\n\t@true\n",
  })
  local got
  make.list(dir .. "/Makefile", function(t)
    got = t
  end)
  ok("make real: answers", vim.wait(8000, function()
    return got ~= nil
  end, 20))
  eq("make real: phony from the include too, file order, then the described", names(got or {}), { "build", "test", "clean", "lint" })
  eq("make real: default goal and description", { got[1].default, got[1].desc, got[3].desc }, { true, "Build everything", "Remove artifacts" })
else
  print "skip make real: make is not installed"
end

-- ── finding the Makefile ────────────────────────────────────────────────────
-- a Makefile ABOVE the git root is the machine's, not the project's
vim.fn.mkdir(base .. "/outer", "p")
local f = assert(io.open(base .. "/outer/Makefile", "w"))
f:write "stray:\n"
f:close()
local inner = project("outer/app", { ["sub/x.txt"] = "" })
eq("find: stops at the git root", make.detect(inner, util.stop(inner)), nil)
local withmk = project("withmk", { Makefile = ".PHONY: a\na:\n\t@true\n", ["web/src/x.txt"] = "" })
eq("find: a Makefile in a parent folder is found from a subfolder", make.detect(withmk .. "/web/src", util.stop(withmk)), withmk .. "/Makefile")
eq("find: GNUmakefile wins, like make does", (function()
  local d = project("gnu", { Makefile = "a:\n", GNUmakefile = "b:\n" })
  return vim.fs.basename(make.detect(d, util.stop(d)))
end)(), "GNUmakefile")
eq("root: the git root", util.root(withmk .. "/web/src"), withmk)

-- ── only with a Makefile ────────────────────────────────────────────────────
local nomk = project("nomk", { ["main.go"] = "package main\n", ["go.mod"] = "module x\n", ["package.json"] = "{}" })
vim.cmd("cd " .. vim.fn.fnameescape(nomk))
local ran = {}
package.loaded["utils.terminal"] = {
  run = function(cmd, dir)
    ran[#ran + 1] = { cmd, dir }
  end,
  direction = function()
    return "horizontal"
  end,
}
for _, action in ipairs { "pick", "last", "default", "output", "quickfix", "stop" } do
  notes = {}
  tasks[action]()
  ok("no Makefile: " .. action .. " says so and does nothing", #ran == 0 and notes[1] ~= nil and notes[1]:find("no Makefile above", 1, true) ~= nil and notes[1]:find("<leader>Rc", 1, true) ~= nil)
end
notes = {}
tasks.last { ask = true }
ok("no Makefile: last with arguments says so", notes[1] ~= nil and notes[1]:find("no Makefile above", 1, true) ~= nil)
notes = {}
tasks.pick { dry = true }
ok("no Makefile: dry run says so", notes[1] ~= nil and notes[1]:find("no Makefile above", 1, true) ~= nil)
ok("no Makefile: go.mod and package.json are not tasks (nothing was collected)", next(tasks.cache) == nil)

-- ── collect: sorted, cached ─────────────────────────────────────────────────
local proj = project("multi", {
  Makefile = ".PHONY: test build\ntest: ## Test all\n\t@true\nbuild:\n\t@true\n",
})
local file = proj .. "/Makefile"
local collected
local function collect(opts)
  collected = nil
  tasks.collect(file, opts, function(t)
    collected = t
  end)
  vim.wait(8000, function()
    return collected ~= nil
  end, 20)
end
local calls = 0
local real_list = make.list
make.list = function(path, cb)
  calls = calls + 1
  return real_list(path, cb)
end
collect()
eq("collect: the default goal first, then the Makefile's order", names(collected), { "test", "build" })
collect()
eq("collect: the second time comes from the cache", calls, 1)
collect { force = true }
eq("collect: force asks again", calls, 2)
vim.uv.fs_utime(file, 1, 1)
collect()
eq("collect: a changed Makefile asks again", calls, 3)
make.list = real_list

-- ── the line that runs ──────────────────────────────────────────────────────
eq("line: the command", exec.line { cmd = { "make", "test" } }, "make test")
eq("line: arguments go after it", exec.line({ cmd = { "make", "test" } }, " PKG=./x "), "make test PKG=./x")
eq("line: no arguments, nothing added", exec.line({ cmd = { "make", "test" } }, ""), "make test")

-- ── running and "run last" (the terminal is a stub) ─────────────────────────
ran = {}
local task = { name = "test", cmd = { "make", "test" }, cwd = proj, dry = { "make", "-n", "test" } }
tasks.run(task, "PKG=./x")
eq("run: goes to the terminal in the task's folder", ran, { { "make test PKG=./x", proj } })
eq("run: remembered as the last of the project", store.get_last(proj), {
  name = "test",
  cmd = { "make", "test" },
  cwd = proj,
  extra = "PKG=./x",
})
ran = {}
vim.cmd("cd " .. vim.fn.fnameescape(proj))
tasks.last()
eq("last: again, with the same arguments", ran, { { "make test PKG=./x", proj } })

ran = {}
tasks.dry(task)
eq("dry: runs the dry command", ran, { { "make -n test", proj } })
eq("dry: is not the last task", store.get_last(proj).cmd, { "make", "test" })

local other = project("other", { Makefile = "a:\n" })
vim.cmd("cd " .. vim.fn.fnameescape(other))
ran = {}
tasks.last()
eq("last: a project with none falls back to the last anywhere", #ran, 1)
os.remove(store.path())
notes = {}
tasks.last()
ok("last: with nothing run it says so", notes[1] ~= nil and notes[1]:find("nothing has run", 1, true) ~= nil)

notes = {}
tasks.run({ name = "x", cmd = { "make" }, cwd = base .. "/gone" })
ok("run: a folder that is gone is a warning", notes[1] ~= nil and notes[1]:find("no longer exists", 1, true) ~= nil)

-- a task still running asks before the next one goes in
local asked, accepted
package.loaded["utils.modal"] = {
  hl = { muted = "Comment", folder = "Directory" },
  confirm = function(lines, opts, on_yes)
    asked = { lines, opts }
    if accepted then
      on_yes()
    end
  end,
  input = function(lines, opts, on_submit)
    asked = { lines, opts }
    on_submit(opts.answer or "typed")
  end,
}
local real_busy, real_stop = exec.busy, exec.stop
local was_stopped = false
exec.busy = function()
  return true
end
exec.stop = function()
  was_stopped = true
  exec.busy = function()
    return false
  end
  return true
end
ran = {}
exec.run(task)
ok("busy: asks first and starts nothing", asked ~= nil and #ran == 0)
accepted = true
exec.run(task)
vim.wait(1500, function()
  return #ran > 0
end, 20)
ok("busy: yes stops the running one and starts the new one", was_stopped and #ran == 1)
exec.busy, exec.stop = real_busy, real_stop
ok("busy: no terminal was ever opened, nothing is running", not exec.busy())

-- ── arguments ───────────────────────────────────────────────────────────────
ran = {}
tasks.ask(task, "", function(text)
  tasks.run(task, text)
end)
vim.wait(1500, function()
  return #ran > 0
end, 20)
eq("ask: the modal's text goes after the target", ran, { { "make test typed", proj } })
eq("ask: the modal says which target", asked[2].title, "Arguments for test")
ran = {}
tasks.last { ask = true }
vim.wait(1500, function()
  return #ran > 0
end, 20)
eq("last with arguments: asks, with the previous ones as the default", { ran, asked[2].default }, { { { "make test typed", proj } }, "typed" })
ran = {}
vim.cmd("cd " .. vim.fn.fnameescape(proj))
tasks.default()
eq("default: a bare make in the Makefile's folder", ran, { { "make", proj } })

-- ── output to the quickfix ──────────────────────────────────────────────────
local gofile = proj .. "/main.go"
local gf = assert(io.open(gofile, "w"))
gf:write "package main\n\nfunc main() {\n\tx := 1\n}\n"
gf:close()
vim.cmd("cd " .. vim.fn.fnameescape(proj))
package.loaded["agent.errors.source"] = {
  terminal = function()
    return "# x\n./main.go:4:2: declared and not used: x\n"
  end,
}
tasks.quickfix()
local qf = vim.fn.getqflist()
eq("quickfix: the terminal's errors, parsed by the agent's own errorformat", { #qf, qf[1] and qf[1].lnum, qf[1] and qf[1].text }, { 1, 4, "declared and not used: x" })
vim.cmd "cclose"
package.loaded["agent.errors.source"] = {
  terminal = function()
    return "all fine\n"
  end,
}
notes = {}
tasks.quickfix()
ok("quickfix: nothing to list says so", notes[1] ~= nil and notes[1]:find("no file:line errors", 1, true) ~= nil)

-- ── presets ─────────────────────────────────────────────────────────────────
local presets = require "tasks.presets"
local langs = presets.languages()
local by_name = {}
for _, l in ipairs(langs) do
  by_name[l.name] = l
end
ok("presets: the languages are there", by_name.go and by_name.python and by_name.rust and by_name.typescript and by_name.dart and by_name.java and by_name.kotlin and by_name.c and by_name.docker and by_name.shell)
ok("presets: several per scenario in the big ones", #by_name.go.presets >= 4 and #by_name.python.presets >= 3)
eq("presets: sorted by label", vim.tbl_map(function(l)
  return l.label
end, langs), (function()
  local labels = vim.tbl_map(function(l)
    return l.label
  end, langs)
  table.sort(labels)
  return labels
end)())
eq("presets: a label for each folder", by_name.c.label, "C / C++")

local make_ok = vim.fn.executable "make" == 1
local count = 0
for _, lang in ipairs(langs) do
  for _, preset in ipairs(lang.presets) do
    count = count + 1
    local id = lang.name .. "/" .. preset.name
    ok("preset " .. id .. ": starts with a # description", preset.desc ~= nil and preset.desc ~= "")
    local dir = project("preset-" .. lang.name .. "-" .. preset.name, {})
    local path = presets.write(dir, preset)
    ok("preset " .. id .. ": is written as Makefile", path == dir .. "/Makefile")
    local src = make.parse_file(util.lines(path))
    local built = make.build(dir, nil, src)
    local listed = names(built)
    ok("preset " .. id .. ": has a help target and more", vim.tbl_contains(listed, "help") and #listed >= 4)
    ok("preset " .. id .. ": every listed target has a description", (function()
      for _, t in ipairs(built) do
        if not t.desc then
          print("  no description: " .. t.name)
          return false
        end
      end
      return true
    end)())
    ok("preset " .. id .. ": help is not the default goal", src.order[1] ~= "help")
    if make_ok then
      local res = vim.system({ "make", "-qp" }, { cwd = dir, text = true, env = { LC_ALL = "C" } }):wait()
      ok("preset " .. id .. ": a real make reads it (" .. tostring(res.code) .. ")", res.code <= 1 and not (res.stderr or ""):find("missing separator", 1, true) and not (res.stderr or ""):find("***", 1, true))
      local real = make.parse_db(res.stdout)
      ok("preset " .. id .. ": make agrees on the .PHONY targets", #real.phony >= 4 and vim.tbl_contains(real.phony, "help"))
    end
  end
end
ok("presets: counted", count >= 20)

-- `make help` of a preset prints each target with its description
if make_ok then
  local dir = project("helpout", {})
  presets.write(dir, by_name.go.presets[1])
  local res = vim.system({ "make", "help" }, { cwd = dir, text = true }):wait()
  ok("preset: make help lists the targets and what they do", res.code == 0 and res.stdout:find("build", 1, true) ~= nil and res.stdout:find("Build the binary", 1, true) ~= nil)
end

local exists = function(set)
  return function(path)
    return set[path] == true
  end
end
eq("guess: go.mod", presets.guess("/p", "lua", exists { ["/p/go.mod"] = true }), "go")
eq("guess: a Kotlin Gradle build beats the Java one", presets.guess("/p", nil, exists { ["/p/build.gradle.kts"] = true }), "kotlin")
eq("guess: the first marker wins", presets.guess("/p", nil, exists { ["/p/package.json"] = true, ["/p/Cargo.toml"] = true }), "rust")
eq("guess: no marker, the filetype", presets.guess("/p", "python", exists {}), "python")
eq("guess: nothing to go on", presets.guess("/p", "lua", exists {}), nil)
eq("order: the guessed language first, the rest as they were", vim.tbl_map(function(l)
  return l.name
end, presets.order({ { name = "a" }, { name = "b" }, { name = "c" } }, "c")), { "c", "a", "b" })

-- a language folder dropped in is discovered, whatever its name
local custom = base .. "/custom"
vim.fn.mkdir(custom .. "/zig", "p")
local zf = assert(io.open(custom .. "/zig/basic.mk", "w"))
zf:write "# Zig: build and test\nbuild: ## Build\n\tzig build\n"
zf:close()
vim.fn.mkdir(custom .. "/empty", "p")
eq("languages: discovered, an empty folder is not a language", vim.tbl_map(function(l)
  return { l.name, l.label, l.presets[1].name, l.presets[1].desc }
end, presets.languages(custom)), { { "zig", "Zig", "basic", "Zig: build and test" } })

-- never overwrites
local keep = project("keep", { Makefile = "mine:\n" })
local written, why = presets.write(keep, by_name.go.presets[1])
eq("write: an existing Makefile is never touched", { written, why, util.read(keep .. "/Makefile") }, { nil, "a Makefile is already there", "mine:\n" })

-- ── <leader>Rc: create ──────────────────────────────────────────────────────
local picker = require "tasks.picker"
local real_choose = picker.choose
local steps = {}
local want = { "Go", "service" }
picker.choose = function(items, opts, on_select)
  steps[#steps + 1] = { first = items[1].label, count = #items, title = opts.title, preview = opts.preview }
  for _, item in ipairs(items) do
    if item.label == want[#steps] then
      return on_select(item.value)
    end
  end
  error("no item " .. tostring(want[#steps]))
end
local fresh = project("fresh", { ["go.mod"] = "module x\n" })
vim.cmd("cd " .. vim.fn.fnameescape(fresh))
vim.cmd "enew"
notes = {}
tasks.create()
eq("create: the project's language comes first, then its presets with a preview", { steps[1].first, steps[2].preview, steps[2].count >= 4 }, { "Go", true, true })
ok("create: the picker says where the Makefile goes", steps[1].title:find("Makefile for", 1, true) ~= nil)
local service
for _, preset in ipairs(by_name.go.presets) do
  if preset.name == "service" then
    service = preset
  end
end
eq("create: the chosen preset is the Makefile", util.read(fresh .. "/Makefile"), util.read(service.path))
ok("create: and it is open", vim.api.nvim_buf_get_name(0) == fresh .. "/Makefile")
ok("create: says what was made", (notes[#notes] or ""):find("created Makefile (Go, service)", 1, true) ~= nil)
steps, notes = {}, {}
tasks.create()
ok("create: with a Makefile there it only says so", #steps == 0 and (notes[1] or ""):find("there is a Makefile already", 1, true) ~= nil)
picker.choose = real_choose

-- ── the menu ────────────────────────────────────────────────────────────────
local menu = require "menus.tasks"
eq("menu: prefix and keys", { menu.prefix, vim.tbl_map(function(m)
  return m[1]
end, menu.maps) }, { "R", { "r", "l", "d", "a", "p", "o", "q", "s", "c" } })
local used = {}
for _, m in ipairs(menu.maps) do
  eq("menu: " .. m[1] .. " has a two word desc once prefixed", #vim.split(require("menus").desc(menu, m[2]), " ", { plain = true }) >= 2, true)
  ok("menu: key " .. m[1] .. " is single and unique", #m[1] == 1 and not used[m[1]])
  used[m[1]] = true
end
ok("menu: registered", vim.tbl_contains(vim.tbl_map(function(c)
  return c.prefix
end, require("menus").contexts()), "R"))

vim.fn.delete(base, "rf")
print(fails == 0 and ("ALL OK (" .. total .. " checks)") or ("FAILURES: " .. fails .. " of " .. total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
