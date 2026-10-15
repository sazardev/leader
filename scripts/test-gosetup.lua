-- Tests of the Go project setup (nvim/lua/gosetup): presets, vars, rendering, never overwriting, the flows and the presets
-- checked by the real tools when they are installed. Hermetic: temp projects, no network or tokens.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-gosetup.lua"
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

local presets = require "gosetup.presets"
local vars = require "gosetup.vars"
local setup = require "gosetup"

local base = vim.fn.tempname()
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text or "")
  f:close()
end
local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return text
end
local function project(name, files)
  local dir = base .. "/" .. name
  vim.fn.mkdir(dir, "p")
  for rel, text in pairs(files or {}) do
    write(dir .. "/" .. rel, text)
  end
  return dir
end
local function run(cwd, ...)
  return vim.system({ ... }, { cwd = cwd, text = true }):wait()
end

-- ── pure: vars ──────────────────────────────────────────────────────────────
eq("module", vars.module "module github.com/acme/notes-api\n\ngo 1.23.4\n", "github.com/acme/notes-api")
eq("module: after a comment", vars.module "// hi\nmodule x/y\n", "x/y")
eq("module: none", vars.module "go 1.22\n", nil)
eq("go_version: patch dropped", vars.go_version "module x\n\ngo 1.23.4\n\ntoolchain go1.24.1\n", "1.23")
eq("go_version: major.minor", vars.go_version "module x\ngo 1.22\n", "1.22")
eq("go_version: none", vars.go_version "module x\n", nil)
eq("main_dir: the root wins", vars.main_dir(true, { "api" }), ".")
eq("main_dir: a preferred name", vars.main_dir(false, { "worker", "api", "cli" }), "./cmd/api")
eq("main_dir: else the first by name", vars.main_dir(false, { "zeta", "alpha" }), "./cmd/alpha")
eq("main_dir: nothing", vars.main_dir(false, {}), ".")
eq("binary: the cmd folder", vars.binary("github.com/a/b", "./cmd/api", "x"), "api")
eq("binary: the module's last element", vars.binary("github.com/a/notes-api", ".", "x"), "notes-api")
eq("binary: not the /v2", vars.binary("github.com/a/tool/v2", ".", "x"), "tool")
eq("binary: no module, the folder", vars.binary(nil, ".", "my app"), "my-app")
eq("render: fills", vars.render("a {{x}} b {{x}}", { x = "1" }), "a 1 b 1")
eq(
  "render: reports the unknown and keeps it",
  { vars.render("{{x}} {{nope}}", { x = "1" }) },
  { "1 {{nope}}", { "nope" } }
)
eq(
  "render: a CI expression is not a placeholder",
  { vars.render("${{ github.ref }}", {}) },
  { "${{ github.ref }}", {} }
)

-- ── collect (disk) ──────────────────────────────────────────────────────────
local flat =
  project("flat", { ["go.mod"] = "module github.com/acme/notes-api\n\ngo 1.23.4\n", ["main.go"] = "package main\n" })
eq(
  "collect: main at the root",
  vars.collect(flat),
  { module = "github.com/acme/notes-api", go = "1.23", main = ".", binary = "notes-api" }
)
local cmd = project("cmd", {
  ["go.mod"] = "module x/svc\ngo 1.22\n",
  ["cmd/worker/main.go"] = "",
  ["cmd/api/main.go"] = "",
  ["cmd/empty/readme"] = "",
})
eq(
  "collect: cmd/api, not a folder without main.go",
  vars.collect(cmd),
  { module = "x/svc", go = "1.22", main = "./cmd/api", binary = "api" }
)
local bare = project("bare", {})
local c = vars.collect(bare)
eq(
  "collect: nothing to read still gives usable values",
  { c.module, c.main, c.binary:match "^%S+$" ~= nil, c.go:match "^%d+%.%d+$" ~= nil },
  { "bare", ".", true, true }
)

-- ── preset files ────────────────────────────────────────────────────────────
for _, topic in ipairs(setup.TOPICS) do
  local list = presets.variants(topic.folder)
  ok(topic.id .. ": has presets", #list > 0)
  local names, targets = {}, {}
  for _, v in ipairs(list) do
    names[v.name] = true
    targets[v.target] = true
    ok(topic.id .. "/" .. v.name .. ": describes itself", #v.desc > 8)
    ok(topic.id .. "/" .. v.name .. ": the target line is not written", not v.body:find("# target:", 1, true))
    ok(topic.id .. "/" .. v.name .. ": the description is the first line", vim.startswith(v.body, "# " .. v.desc))
    local _, unknown = vars.render(v.body, { module = "m", go = "1", main = ".", binary = "b" })
    eq(topic.id .. "/" .. v.name .. ": only known placeholders", unknown, {})
    ok(
      topic.id .. "/" .. v.name .. ": ends with a newline once rendered",
      select(1, setup.render(bare, v)):sub(-2) ~= "\n\n"
    )
  end
  ok(topic.id .. ": the default variant exists", names[topic.default])
  eq(topic.id .. ": one target for all its variants", vim.tbl_count(targets), 1)
end
local keys = {}
for _, t in ipairs(setup.TOPICS) do
  ok("topic key " .. t.key .. " is single and unique", #t.key == 1 and not keys[t.key])
  keys[t.key] = true
end
eq("parse: needs a target", presets.parse("x", "# desc\nbody\n"), nil)
eq("parse: needs a description", presets.parse("x", "\n# target: a\nbody\n"), nil)
eq("parse: variant name drops the extension only", presets.variants("docker")[1].name, "alpine")

-- ── writing ─────────────────────────────────────────────────────────────────
for _, topic in ipairs(setup.TOPICS) do
  for _, v in ipairs(presets.variants(topic.folder)) do
    local dir = project(
      "w-" .. topic.id .. "-" .. v.name,
      { ["go.mod"] = "module github.com/acme/notes-api\n\ngo 1.23.4\n", ["main.go"] = "package main\n" }
    )
    local path, why = setup.write(dir, v)
    ok(topic.id .. "/" .. v.name .. ": written (" .. tostring(why) .. ")", path == dir .. "/" .. v.target)
    local text = read(dir .. "/" .. v.target) or ""
    ok(topic.id .. "/" .. v.name .. ": nothing left to fill", not text:find "{{%w+}}")
    eq(
      topic.id .. "/" .. v.name .. ": never overwrites",
      { setup.write(dir, v) },
      { nil, v.target .. " is already there" }
    )
  end
end
local docker_dir = project("docker-text", { ["go.mod"] = "module x/y\ngo 1.23.4\n", ["cmd/api/main.go"] = "" })
setup.write(docker_dir, presets.variants("docker")[1])
local dockerfile = read(docker_dir .. "/Dockerfile")
ok("docker: the Go version of go.mod", dockerfile:find("FROM golang:1.23-alpine AS build", 1, true))
ok("docker: builds the main package it found", dockerfile:find("-o /out/api ./cmd/api", 1, true))
ok("docker: runs as a user that is not root", dockerfile:find("USER app", 1, true))
local gci_dir = project("gci-text", { ["go.mod"] = "module github.com/acme/notes-api\ngo 1.23\n" })
setup.write(gci_dir, presets.variants("golangci")[2])
ok(
  "golangci: the module is the local import prefix",
  (read(gci_dir .. "/.golangci.yml") or ""):find("- github.com/acme/notes-api", 1, true)
)
local ci_dir = project("ci-text", { ["go.mod"] = "module x\ngo 1.23\n" })
setup.write(ci_dir, presets.variants("ci")[1])
ok(
  "ci: GitHub's own expressions survive",
  (read(ci_dir .. "/.github/workflows/ci.yml") or ""):find("group: ci-${{ github.ref }}", 1, true)
)

-- ── the real tools ──────────────────────────────────────────────────────────
local function tool(name)
  for _, candidate in ipairs { vim.fn.stdpath "data" .. "/mason/bin/" .. name, vim.fn.exepath(name) } do
    if candidate ~= "" and vim.uv.fs_stat(candidate) then
      return candidate
    end
  end
end

-- TOML and YAML parse (python's tomllib and PyYAML, when they exist)
local py = vim.system({ "python3", "-P", "-c", "import tomllib, yaml" }):wait().code == 0
if py then
  local script = [[
import sys, tomllib, yaml
path = sys.argv[1]
text = open(path).read()
if path.endswith(".toml"):
    tomllib.loads(text)
else:
    yaml.safe_load(text)
]]
  for _, topic in ipairs(setup.TOPICS) do
    for _, v in ipairs(presets.variants(topic.folder)) do
      if v.target:match "%.toml$" or v.target:match "%.ya?ml$" then
        local dir = base .. "/w-" .. topic.id .. "-" .. v.name
        local res = run(dir, "python3", "-P", "-c", script, dir .. "/" .. v.target)
        eq(
          topic.id .. "/" .. v.name .. ": parses as " .. (v.target:match "%.toml$" and "TOML" or "YAML"),
          res.stderr:match "[^\n]*$",
          ""
        )
      end
    end
  end
else
  print "skip: python3 with tomllib and PyYAML is not available (TOML/YAML syntax not checked)"
end

-- golangci-lint v2 verifies its own schema
local gl = tool "golangci-lint"
local v2
for _, candidate in ipairs { vim.fn.stdpath "data" .. "/mason/bin/golangci-lint", vim.fn.exepath "golangci-lint" } do
  if candidate ~= "" and vim.uv.fs_stat(candidate) then
    local out = run(base, candidate, "--version").stdout or ""
    if setup.golangci_major(out) == 2 then
      v2 = candidate
      break
    end
  end
end
if v2 then
  for _, v in ipairs(presets.variants "golangci") do
    local dir = base .. "/w-golangci-" .. v.name
    local res = run(dir, v2, "config", "verify")
    eq("golangci/" .. v.name .. ": golangci-lint v2 accepts the config", { res.code, res.stderr }, { 0, "" })
  end
else
  print("skip: golangci-lint v2 is not installed (config not verified)" .. (gl and "" or ""))
end
eq("golangci_major: v1", setup.golangci_major "golangci-lint has version v1.64.8 built with go1.27.2", 1)
eq("golangci_major: v2", setup.golangci_major "golangci-lint has version 2.13.2 built with go1.27.0", 2)
eq("golangci_major: nothing", setup.golangci_major "", nil)

-- air: every key we set exists in what `air init` generates
local air = tool "air"
if air and py then
  local dir = project("air-init", {})
  run(dir, air, "init")
  local default = dir .. "/.air.toml"
  if vim.uv.fs_stat(default) then
    local script = [[
import sys, tomllib
known = tomllib.load(open(sys.argv[1], "rb"))
ours = tomllib.load(open(sys.argv[2], "rb"))
bad = [f"{sec}.{k}" for sec, vals in ours.items() if isinstance(vals, dict) for k in vals if k not in known.get(sec, {})]
bad += [k for k, v in ours.items() if not isinstance(v, dict) and k not in known]
print(",".join(bad))
]]
    for _, v in ipairs(presets.variants "air") do
      local res = run(base, "python3", "-P", "-c", script, default, base .. "/w-air-" .. v.name .. "/.air.toml")
      eq("air/" .. v.name .. ": every key is one air knows", vim.trim(res.stdout or ""), "")
    end
  else
    print "skip: `air init` produced nothing"
  end
else
  print "skip: air is not installed (keys not compared)"
end

-- lefthook validates its own file
local lefthook = tool "lefthook"
if lefthook then
  local dir = base .. "/w-hooks-lefthook"
  run(dir, "git", "init", "-q")
  local res = run(dir, lefthook, "validate")
  eq("hooks/lefthook: lefthook validate", res.code, 0)
else
  print "skip: lefthook is not installed (not validated)"
end

-- ── the flows ───────────────────────────────────────────────────────────────
local picker = require "tasks.picker"
local real_choose = picker.choose
local chosen
picker.choose = function(items, opts, cb)
  chosen = { items = items, opts = opts, cb = cb }
end

local app =
  project("flow", { ["go.mod"] = "module github.com/acme/notes-api\ngo 1.23\n", ["main.go"] = "package main\n" })
notes = {}
setup.create("air", app)
ok("create: two variants ask which", chosen and #chosen.items == 2)
eq("create: the variants are listed by name", { chosen.items[1].label, chosen.items[2].label }, { "api", "basic" })
ok(
  "create: the preview is the file as it will be written",
  (read(chosen.items[1].path) or ""):find("go build -o ./tmp/notes-api .", 1, true)
)
ok(
  "create: the preview keeps the file's own name (for its filetype)",
  vim.fs.basename(chosen.items[1].path) == ".air.toml"
)
ok("create: nothing is written before choosing", read(app .. "/.air.toml") == nil)
chosen.cb(chosen.items[2].value)
ok(
  "create: the choice is written",
  (read(app .. "/.air.toml") or ""):find('cmd = "go build -o ./tmp/notes-api ."', 1, true)
)
ok("create: and opened", vim.api.nvim_buf_get_name(0) == app .. "/.air.toml")
ok(
  "create: says what it did",
  vim.iter(notes):any(function(m)
    return m:find("created .air.toml (basic)", 1, true)
  end)
)

notes = {}
chosen = nil
vim.cmd "enew"
setup.create("air", app)
ok(
  "create: an existing file is opened, not replaced",
  chosen == nil and vim.api.nvim_buf_get_name(0) == app .. "/.air.toml"
)
ok("create: and says so", notes[1] and notes[1]:find("already there", 1, true) ~= nil)

-- one variant: no picker
local one = project("one", { ["go.mod"] = "module x\ngo 1.23\n" })
chosen = nil
setup.create("editorconfig", one)
ok("create: a single variant is written straight away", chosen == nil and read(one .. "/.editorconfig") ~= nil)

-- an alternative name counts as there
local alt = project("alt", { ["go.mod"] = "module x\ngo 1.23\n", [".golangci.yaml"] = 'version: "2"\n' })
chosen = nil
setup.create("golangci", alt)
ok("create: .golangci.yaml counts as the config", chosen == nil and read(alt .. "/.golangci.yml") == nil)
eq(
  "state: misnamed",
  setup.state(project("mis", { [".golangcli.yml"] = "x" }), setup.topic "golangci", ".golangci.yml").kind,
  "misnamed"
)
eq("state: absent", setup.state(project("none", {}), setup.topic "golangci", ".golangci.yml").kind, "absent")

-- the misnamed config of the user's own project
local modal = require "utils.modal"
local real_confirm = modal.confirm
local asked
modal.confirm = function(lines, opts, on_yes)
  asked = { lines = lines, opts = opts, yes = on_yes }
end
local typo =
  project("typo", { ["go.mod"] = "module x\ngo 1.23\n", [".golangcli.yml"] = "linters:\n  enable: [govet]\n" })
chosen = nil
setup.create("golangci", typo)
ok("misnamed: asks before touching anything", asked and chosen == nil and read(typo .. "/.golangcli.yml") ~= nil)
eq("misnamed: says what it would do", asked.opts.confirm, "Rename")
asked.yes()
eq(
  "misnamed: renamed, content kept",
  { read(typo .. "/.golangci.yml"), read(typo .. "/.golangcli.yml") },
  { "linters:\n  enable: [govet]\n", nil }
)
modal.confirm = real_confirm

-- several at once
local real_checklist = modal.checklist
local list
modal.checklist = function(items, opts, on_submit)
  list = { items = items, opts = opts, submit = on_submit }
end
local many = project("many", {
  ["go.mod"] = "module x\ngo 1.23\n",
  ["main.go"] = "package main\n",
  [".air.toml"] = 'root = "."\n',
  [".golangcli.yml"] = "x",
})
notes = {}
setup.pick(many)
local labels = {}
for _, it in ipairs(list.items) do
  labels[#labels + 1] = ("%s|%s|%s"):format(it.label, it.checked, it.desc)
end
eq("pick: what is there is not checked, what is core and missing is", {
  labels[1]:match "^[^|]+|[^|]+",
  labels[2]:match "^[^|]+|[^|]+",
  labels[3]:match "^[^|]+|[^|]+",
  labels[7]:match "^[^|]+|[^|]+",
}, { "golangci-lint config|false", "Air live reload (.air.toml)|false", "Dockerfile|false", ".editorconfig|true" })
ok("pick: says why the misnamed one is not checked", list.items[1].desc:find("wrong name", 1, true))
ok("pick: says what already exists", list.items[2].desc:find("already there: .air.toml", 1, true))
list.submit { 1, 2, 3, 7 } -- misnamed, existing, Dockerfile, editorconfig
ok(
  "pick: creates the chosen ones that are missing",
  read(many .. "/Dockerfile") ~= nil and read(many .. "/.editorconfig") ~= nil
)
eq("pick: leaves what exists alone", read(many .. "/.air.toml"), 'root = "."\n')
ok("pick: no .golangci.yml next to the misnamed file", read(many .. "/.golangci.yml") == nil)
ok(
  "pick: says what it skipped",
  vim.iter(notes):any(function(m)
    return m:find("misnamed file found", 1, true)
  end)
)
modal.checklist = real_checklist
picker.choose = real_choose

-- ── the menu ────────────────────────────────────────────────────────────────
local go = require "languages.go"
eq("menu: the group is named", go.menu.groups, { S = "setup" })
local seen = {}
for _, m in ipairs(go.menu.maps) do
  ok("menu: key " .. m[1] .. " is unique", not seen[m[1]])
  seen[m[1]] = true
  ok(
    "menu: " .. m[1] .. " has a two word desc once prefixed",
    #vim.split(require("menus").desc(go.menu, m[2]), " ", { plain = true }) >= 2
  )
end
local setup_keys = {}
for _, m in ipairs(go.menu.maps) do
  if m[1]:sub(1, 1) == "S" then
    setup_keys[#setup_keys + 1] = m[1]
  end
end
eq("menu: the setup keys", setup_keys, { "Sl", "Sa", "Sd", "Si", "Sc", "Sh", "Se", "Sp", "Sm", "Sg" })
for _, k in ipairs(setup_keys) do
  ok("menu: no plain key " .. k:sub(2) .. " clashes with the sub-prefix S", not seen["S"])
end

vim.fn.delete(base, "rf")
print(fails == 0 and ("ALL OK (" .. total .. " checks)") or ("FAILURES: " .. fails .. " of " .. total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
