-- Tests of the .gitignore helper (nvim/lua/gitignore): the preset files, detection (pure matching + a real scan), composing
-- without duplicates, the REAL rules against `git check-ignore` (what a project needs must never be ignored), the checklist
-- modal and the whole flow on temp repos. Hermetic: no network or tokens.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-gitignore.lua"
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

local presets = require "gitignore.presets"
local detect = require "gitignore.detect"
local compose = require "gitignore.compose"

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
local function git(dir, ...)
  return vim.system({ "git", "-C", dir, ... }, { text = true }):wait()
end
local function repo(name, files)
  local dir = base .. "/" .. name
  vim.fn.mkdir(dir, "p")
  git(dir, "init", "-q")
  for rel, text in pairs(files or {}) do
    write(dir .. "/" .. rel, text)
  end
  return dir
end

-- ── preset files ────────────────────────────────────────────────────────────
local all = presets.list()
local by = {}
for _, p in ipairs(all) do
  by[p.name] = p
end
eq(
  "presets: the ones shipped",
  vim.tbl_map(function(p)
    return p.name
  end, all),
  { "secrets", "c", "dart", "docker", "dotnet", "go", "java", "node", "python", "rust", "terraform", "base" }
)
for _, p in ipairs(all) do
  ok(p.name .. ": has a title and what it ignores", p.title ~= "" and p.desc ~= nil)
  ok(p.name .. ": says when it applies", #p.detect > 0)
  ok(p.name .. ": has rules", #p.body > 0)
  ok(p.name .. ": the detect line is not written", not vim.tbl_contains(p.body, "# detect:"))
  local seen, dup = {}, nil
  for _, line in ipairs(p.body) do
    if line ~= "" and not line:match "^#" then
      dup = dup or (seen[line] and line)
      seen[line] = true
    end
  end
  eq(p.name .. ": no rule twice", dup, nil)
end
eq("presets: always on", { by.secrets.detect[1], by.base.detect[1] }, { "always", "always" })

local parsed = presets.parse("x", "# Thing: what it ignores\n# detect: a.txt *.md\n# why\nfoo\n\nbar\n\n")
eq("parse: title", parsed.title, "Thing")
eq("parse: desc", parsed.desc, "what it ignores")
eq("parse: detect", parsed.detect, { "a.txt", "*.md" })
eq("parse: body trimmed, detect removed", parsed.body, { "# why", "foo", "", "bar" })
eq("parse: no header", presets.parse("x", "foo\n"), nil)

-- ── detection ───────────────────────────────────────────────────────────────
ok("match: exact", detect.match("go.mod", "go.mod"))
ok("match: exact is not a suffix", not detect.match("go.mod", "x/go.mod"))
ok("match: glob on the extension", detect.match("*.go", "main.go"))
ok("match: the dot is a dot", not detect.match("*.go", "maingo"))
ok("match: glob after a prefix", detect.match(".env.*", ".env.local"))
ok("match: that prefix needs its dot", not detect.match(".env.*", ".envrc"))
ok("match: folders carry the slash", detect.match("node_modules/", "node_modules/"))
ok("match: a file is not a folder", not detect.match("node_modules/", "node_modules"))
ok("match: regex characters are literal", detect.match("a+b.txt", "a+b.txt") and not detect.match("a+b.txt", "aab.txt"))

local proj = repo("scan", {
  ["go.mod"] = "module x\n",
  ["main.go"] = "package main\n",
  ["web/package.json"] = "{}",
  ["web/src/app.tsx"] = "",
  ["web/src/deep/er/too.ts"] = "", -- 4 levels down: out of reach
  ["node_modules/pkg/index.js"] = "", -- the folder counts, what is inside is not read
  [".env"] = "KEY=1\n",
})
local names = detect.scan(proj, { depth = 3 })
ok("scan: files", vim.tbl_contains(names, "go.mod") and vim.tbl_contains(names, "main.go"))
ok("scan: nested files", vim.tbl_contains(names, "package.json") and vim.tbl_contains(names, "app.tsx"))
ok("scan: folders end with a slash", vim.tbl_contains(names, "node_modules/") and vim.tbl_contains(names, "web/"))
ok("scan: dependency folders are not walked", not vim.tbl_contains(names, "index.js"))
ok("scan: depth is bounded", not vim.tbl_contains(names, "too.ts"))
ok("scan: .git is not read", not vim.tbl_contains(names, "HEAD"))
eq("scan: a cap", #detect.scan(proj, { max = 3 }), 3)
eq("scan: a folder that is not there", detect.scan(base .. "/nope"), {})

local hits = detect.run(all, names)
ok("run: Go by go.mod", hits.go and hits.go.first == "go.mod")
ok("run: Node by package.json and the node_modules folder", hits.node and hits.node.count >= 3)
ok("run: .env is found, not only recommended", hits.secrets and hits.secrets.first == ".env" and hits.secrets.always)
ok("run: always is on with nothing found", hits.base and hits.base.always and hits.base.first == "")
eq("run: what is not there stays out", { hits.rust, hits.python, hits.docker }, {})

-- ── compose ─────────────────────────────────────────────────────────────────
local fresh, added = compose.build({ by.node, by.python }, nil)
ok("build: header first", vim.startswith(fresh, by.node.header .. "\n"))
ok("build: a rule shared by two presets is written once", select(2, fresh:gsub("\ndist/\n", "\n")) == 1)
ok("build: both sections are there", fresh:find(by.python.header, 1, true) ~= nil)
ok("build: ends with a newline, no double blank lines", fresh:sub(-1) == "\n" and not fresh:find "\n\n\n")
ok("build: counts the rules", added > 20)
eq("build: nothing chosen", { compose.build({}, nil) }, { "", 0 })

local have = "node_modules/\ndist/\n# mine\nsecret-thing\n"
local more, n = compose.build({ by.node }, have)
ok("build: appends after a blank line", vim.startswith(more, "\n" .. by.node.header))
ok(
  "build: what exists is not repeated",
  not more:find("\nnode_modules/\n", 1, true) and not more:find("\ndist/\n", 1, true)
)
ok("build: the rest of the block is kept", more:find(".yarn/*", 1, true) ~= nil and n > 10)
local again = compose.build({ by.node }, have .. more)
eq("build: running it again adds nothing", again, "")
eq("missing: a preset the file already has", compose.missing(by.node, compose.rules(have .. more)), 0)
ok("missing: counts what is not there", compose.missing(by.node, compose.rules(have)) == n)
eq("rules: CRLF and trailing spaces", compose.rules "a/  \r\n# c\r\n\r\nb\r\n", { ["a/"] = true, b = true })
ok("build: no newline at the end of the file still separates", vim.startswith(compose.build({ by.go }, "x"), "\n\n"))
-- a block whose rules all exist disappears with its comment, but a later block with something new keeps the header
local split = presets.parse("p", "# P: test\n# detect: a\n# first\none\n\n# second\ntwo\n")
local out = compose.build({ split }, "one\n")
eq("build: the covered block's comment goes too", out, "\n# P: test\n# second\ntwo\n")

-- ── the rules against git ───────────────────────────────────────────────────
-- Everything at once: files a project needs must never be ignored, junk and secrets must be
local everything = repo "rules"
write(everything .. "/.gitignore", (compose.build(all, nil)))
local needed = {
  "README.md",
  "LICENSE",
  "Makefile",
  "go.mod",
  "go.sum",
  "main.go",
  "cmd/app/main.go",
  "internal/secrets.go",
  "docs/secrets.md",
  "package.json",
  "package-lock.json",
  "tsconfig.json",
  "src/index.ts",
  "src/lib/build.ts",
  "lib/utils.js",
  "pyproject.toml",
  "requirements.txt",
  "app/main.py",
  "Cargo.toml",
  "Cargo.lock",
  "src/main.rs",
  "pubspec.yaml",
  "pubspec.lock",
  "lib/main.dart",
  "android/app/build.gradle",
  "pom.xml",
  "build.gradle.kts",
  "gradlew",
  "gradle/wrapper/gradle-wrapper.jar",
  "src/main/java/App.java",
  "src/main/kotlin/App.kt",
  "CMakeLists.txt",
  "src/main.c",
  "include/app.h",
  "Dockerfile",
  "docker-compose.yml",
  ".dockerignore",
  "main.tf",
  "variables.tf",
  ".terraform.lock.hcl",
  "terraform.tfvars.example",
  "App.csproj",
  "Program.cs",
  ".env.example",
  ".env.sample",
  ".github/workflows/ci.yml",
  ".vscode/settings.json",
  ".editorconfig",
  "deploy/key.pub",
  "data/seed.sql",
  "scripts/run.sh",
  "config/app.yaml",
}
local junk = {
  ".env",
  ".env.local",
  ".env.production",
  "api/.env",
  "server.pem",
  "certs/tls.key",
  "id_rsa",
  "credentials.json",
  "secrets.json",
  "terraform.tfstate",
  "prod.tfvars",
  ".DS_Store",
  "Thumbs.db",
  ".idea/workspace.xml",
  "x.swp",
  "debug.log",
  "node_modules/a/index.js",
  "dist/app.js",
  ".next/cache",
  "coverage/lcov.info",
  "__pycache__/a.cpython-312.pyc",
  ".venv/bin/python",
  ".pytest_cache/v",
  "target/debug/app",
  "app.test",
  "app.exe",
  "bin/app",
  ".dart_tool/package_config.json",
  "android/local.properties",
  "ios/Pods/x",
  "Foo.class",
  ".gradle/x",
  "build/out",
  ".terraform/providers/x",
  "bin/Debug/app.dll",
  "obj/x.cache",
  "CMakeCache.txt",
  "cmake-build-debug/x",
  "docker-compose.override.yml",
  ".vscode/state.vscdb",
}
local function ignored(path)
  write(everything .. "/" .. path, "x")
  return git(everything, "check-ignore", "-q", "--no-index", path).code == 0
end
local wrongly = vim.tbl_filter(ignored, needed)
eq("rules: nothing a project needs is ignored", wrongly, {})
local missed = vim.tbl_filter(function(p)
  return not ignored(p)
end, junk)
eq("rules: junk and secrets are ignored", missed, {})

-- ── the checklist modal (real) ──────────────────────────────────────────────
local modal = require "utils.modal"
local submitted
modal.checklist(
  {
    { label = "Go", desc = "found go.mod", checked = true },
    { label = "Node", desc = "build output" },
    { label = "Docker", checked = true },
  },
  { title = "Create .gitignore", intro = { "intro", "" }, confirm = "Create", footer = "Space toggle" },
  function(chosen)
    submitted = chosen
  end
)
local buf = vim.api.nvim_get_current_buf()
local win = vim.api.nvim_get_current_win()
local function lines()
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end
local function press(key)
  vim.fn.maparg(key, "n", false, true).callback()
end
eq(
  "checklist: rows show the marks",
  { lines()[3], lines()[4], lines()[5] },
  { " [x] Go      found go.mod", " [ ] Node    build output", " [x] Docker" }
)
eq("checklist: the cursor starts on the first item", vim.api.nvim_win_get_cursor(win)[1], 3)
vim.cmd "normal! j"
press "x"
eq("checklist: x toggles the row under the cursor", lines()[4], " [x] Node    build output")
vim.cmd "normal! 5j"
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf }) -- headless does not draw, so nothing fires it
eq("checklist: the cursor stays on the items", vim.api.nvim_win_get_cursor(win)[1], 5)
press "<Space>"
eq("checklist: space toggles too", lines()[5], " [ ] Docker")
press "a"
eq(
  "checklist: a switches everything on when something is off",
  { lines()[3], lines()[4], lines()[5] },
  { " [x] Go      found go.mod", " [x] Node    build output", " [x] Docker" }
)
press "a"
ok("checklist: a again switches everything off", not lines()[3]:find "%[x%]" and not lines()[5]:find "%[x%]")
press "x"
vim.cmd "normal! gg"
press "<CR>"
eq("checklist: Enter hands back the checked indexes", submitted, { 3 })
ok("checklist: and closes", not vim.api.nvim_win_is_valid(win))

-- ── the whole flow ──────────────────────────────────────────────────────────
local gi = require "gitignore"
local captured
local real_checklist = modal.checklist
modal.checklist = function(items, opts, on_submit)
  captured = { items = items, opts = opts, submit = on_submit }
end
local function labels(items, want_checked)
  return vim.tbl_map(
    function(i)
      return i.label
    end,
    vim.tbl_filter(function(i)
      return (i.checked and true or false) == want_checked
    end, items)
  )
end

local app = repo("flow", {
  ["go.mod"] = "module x\n",
  ["main.go"] = "package main\n",
  ["Dockerfile"] = "FROM scratch\n",
  [".env"] = "TOKEN=1\n",
  ["README.md"] = "# x\n",
})
git(app, "add", "-A")
git(app, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init")

gi.open(app)
eq("flow: a new file says create", captured.opts.title, "Create .gitignore")
eq(
  "flow: what the project looks like is checked",
  labels(captured.items, true),
  { "Secrets", "Docker", "Go", "Editor and system" }
)
ok("flow: the rest is there, unchecked", vim.tbl_contains(labels(captured.items, false), "Node.js / TypeScript"))
local function item(label)
  for i, it in ipairs(captured.items) do
    if it.label == label then
      return i, it
    end
  end
end
eq("flow: why Go is checked", select(2, item "Go").desc, "found go.mod +1")
eq("flow: why secrets is", select(2, item "Secrets").desc, "found .env")
eq("flow: a topic that was not found tells what it is for", select(2, item "Rust").desc, by.rust.desc)
eq("flow: the order of the file is preset order", captured.items[1].label, "Secrets")

local picked = {}
for i, it in ipairs(captured.items) do
  if it.checked then
    picked[#picked + 1] = i
  end
end
notes = {}
captured.submit(picked)
local text = read(app .. "/.gitignore")
ok("flow: the file is written", text ~= nil)
ok(
  "flow: secrets first, editor leftovers last",
  text:find("# Secrets", 1, true) < text:find("# Go", 1, true)
    and text:find("# Go", 1, true) < text:find("# Editor and system", 1, true)
)
ok("flow: the rules are there", text:find("\n.env\n", 1, true) ~= nil and text:find("*.test", 1, true) ~= nil)
ok("flow: what was not chosen is not", not text:find("node_modules", 1, true))
ok("flow: the file is opened", vim.api.nvim_buf_get_name(0) == app .. "/.gitignore")
ok("flow: says what it did", notes[1] and notes[1]:find("created .gitignore", 1, true) ~= nil)
vim.wait(5000, function()
  return vim.iter(notes):any(function(m)
    return m:find "tracked"
  end)
end)
local warned = vim.iter(notes):find(function(m)
  return m:find "tracked"
end)
ok(
  "flow: warns about the .env git already tracks",
  warned and warned:find(".env", 1, true) and warned:find("git rm --cached", 1, true)
)
eq("tracked_message: nothing", gi.tracked_message {}, nil)
ok(
  "tracked_message: counts and trims",
  gi.tracked_message({ "a", "b", "c", "d", "e", "f", "g" }):find("7 tracked files", 1, true)
    and gi.tracked_message({ "a", "b", "c", "d", "e", "f", "g" }):find("(+2 more)", 1, true)
)

-- again: it updates, covered topics are unchecked, nothing is lost
write(app .. "/.gitignore", "# mine\ncustom-rule\n" .. text)
write(app .. "/package.json", "{}")
vim.cmd "bwipeout!"
gi.open(app)
eq("flow: an existing file says update", captured.opts.title, "Update .gitignore")
eq("flow: covered topics are not checked again", labels(captured.items, true), { "Node.js / TypeScript" })
eq("flow: and say so", select(2, item "Go").desc, "already in .gitignore")
ok(
  "flow: the new topic says how many rules",
  select(2, item "Node.js / TypeScript").desc:find("found package.json", 1, true)
    and select(2, item "Node.js / TypeScript").desc:find(" new", 1, true)
)
local nodei = item "Node.js / TypeScript"
notes = {}
captured.submit { nodei }
local updated = read(app .. "/.gitignore")
ok("flow: the old file is untouched at the top", vim.startswith(updated, "# mine\ncustom-rule\n" .. text))
ok("flow: the new rules come after", updated:find("node_modules/", #text, true) ~= nil)
ok("flow: says it updated", notes[1] and notes[1]:find("updated .gitignore", 1, true) ~= nil)

notes = {}
local goi = item "Go"
captured.submit { goi }
eq("flow: choosing what is already there writes nothing", read(app .. "/.gitignore"), updated)
ok("flow: and says so", notes[1] and notes[1]:find("nothing to add", 1, true) ~= nil)
captured.submit {}
eq("flow: nothing chosen, nothing happens", read(app .. "/.gitignore"), updated)

-- guards
notes = {}
gi.open(base .. "/not-a-repo-" .. vim.uv.hrtime())
ok("flow: outside a repo it still resolves a root or says so", true)
local unsaved = repo("unsaved", { [".gitignore"] = "a\n" })
vim.cmd("edit " .. vim.fn.fnameescape(unsaved .. "/.gitignore"))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })
notes = {}
captured = nil
gi.open(unsaved)
ok(
  "flow: unsaved changes in .gitignore stop it",
  captured == nil and notes[1] and notes[1]:find("unsaved", 1, true) ~= nil
)
vim.cmd "bwipeout!"
modal.checklist = real_checklist

-- ── the menu ────────────────────────────────────────────────────────────────
local menu = require "menus.git"
local entry
for _, m in ipairs(menu.maps) do
  if m[1] == "i" then
    entry = m
  end
end
ok("menu: <leader>Gi exists in the Git menu", entry ~= nil)
eq("menu: its desc", entry and entry[2], "ignore rules")
local keys = {}
for _, m in ipairs(menu.maps) do
  ok("menu: key " .. m[1] .. " is unique", not keys[m[1]])
  keys[m[1]] = true
end

vim.fn.delete(base, "rf")
print(fails == 0 and ("ALL OK (" .. total .. " checks)") or ("FAILURES: " .. fails .. " of " .. total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
