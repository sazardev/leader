-- Tests of the project kit (nvim/lua/agent/kit, <leader>aS): presets (every one parses and has its document's sections),
-- the pure text work (clean, principles section, AGENTS.md links, named preset), the project snapshot and the 0-token
-- AGENTS.md, the prompts, and the flows (never overwriting, the trash on replace, CLAUDE.md link) with a fake model.
-- Hermetic: temp projects, no network or tokens.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-kit.lua"
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

local presets = require "agent.kit.presets"
local compose = require "agent.kit.compose"
local snapshot = require "agent.kit.snapshot"
local template = require "agent.kit.template"
local prompts = require "agent.kit.prompts"

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

-- ── presets ──────────────────────────────────────────────────────────────────

local parsed =
  presets.parse("x", "<!-- name: X -->\n<!-- desc: what it is -->\n<!-- core: true -->\n\n# Title\n\nbody\n\n")
eq("parse: header read, body without it", parsed and { parsed.name, parsed.desc, parsed.core, parsed.body }, {
  "X",
  "what it is",
  true,
  "# Title\n\nbody\n",
})
eq("parse: no desc = not a preset", presets.parse("x", "# Title\n"), nil)
eq("parse: the name defaults to the file's", presets.parse("go-htmx", "<!-- desc: d -->\n# T\n").name, "go-htmx")

--- every preset of a folder: parses, unique names, the document's sections, no leftover header, a title line
local function check_folder(folder, id)
  local files = 0
  for file in vim.fs.dir(presets.dir() .. "/" .. folder) do
    if file:match "%.md$" then
      files = files + 1
    end
  end
  local list = presets.list(folder)
  eq(folder .. ": every file is a preset (has `<!-- desc: … -->`)", #list, files)
  local names = {}
  for _, p in ipairs(list) do
    eq(folder .. "/" .. p.id .. ": unique name", names[p.name], nil)
    names[p.name] = true
    ok(folder .. "/" .. p.id .. ": desc is one short line (<= 110)", #p.desc <= 110)
    ok(folder .. "/" .. p.id .. ": no header line left in the body", not p.body:find("<!--", 1, true))
    if id then
      ok(
        folder .. "/" .. p.id .. ": starts with the `# " .. compose.doc(id).file .. ": …` title",
        p.body:match("^# " .. compose.doc(id).file:gsub("%.", "%%.") .. ": %S")
      )
      eq(folder .. "/" .. p.id .. ": has every section", compose.missing(p.body, id), {})
      ok(
        folder .. "/" .. p.id .. ": no principles section (they are added)",
        not p.body:find("\n## " .. compose.PRINCIPLES, 1, true)
      )
      local fences = select(2, p.body:gsub("\n```", ""))
      eq(folder .. "/" .. p.id .. ": code fences are closed", fences % 2, 0)
    else
      ok(
        folder .. "/" .. p.id .. ": body starts with `### " .. p.name .. "`",
        p.body:sub(1, #p.name + 5) == "### " .. p.name .. "\n"
      )
      ok(folder .. "/" .. p.id .. ": no `## ` heading inside a principle", not p.body:find("\n## ", 1, true))
    end
  end
  return list
end

local designs = {}
local design_cats = presets.categories(nil, "design")
eq(
  "design: the three kinds, in order",
  vim.tbl_map(function(c)
    return c.id
  end, design_cats),
  { "systems", "styles", "terminal" }
)
for _, c in ipairs(design_cats) do
  vim.list_extend(designs, check_folder("design/" .. c.id, "design"))
end
ok("design: there are many to choose from", #designs >= 18)
eq("design: all() gathers every category", #presets.all "design", #designs)

-- design add-ons: only DESIGN.md sections, rows of 2-3 cells, every design gets some, merging keeps every section
local DESIGN_SECTIONS = {}
for _, sec in ipairs(compose.doc("design").sections) do
  DESIGN_SECTIONS[sec] = true
end
local design_addons = 0
for axis, kind in vim.fs.dir(presets.dir() .. "/design-addons") do
  if kind == "directory" then
    for _, a in ipairs(presets.list("design-addons/" .. axis)) do
      design_addons = design_addons + 1
      local where = "design-addons/" .. axis .. "/" .. a.id
      ok(where .. ": desc <= 110", #a.desc <= 110)
      ok(where .. ": no title line", not a.body:find "^# " and not a.body:find "\n# ")
      for _, h in ipairs(compose.headings(a.body)) do
        ok(where .. ": `## " .. h .. "` is a DESIGN.md section", DESIGN_SECTIONS[h] == true)
      end
      for line in a.body:gmatch "[^\n]+" do
        if line:match "^|" then
          local cells = select(2, line:gsub("|", "")) - 1
          ok(where .. ": a table row has 2-4 cells: " .. line:sub(1, 40), cells >= 2 and cells <= 4)
        end
      end
    end
  end
end
ok("design add-ons: many", design_addons >= 25)
for _, p in ipairs(presets.all "design") do
  local tags = presets.design_tags(p, p.category)
  local fit = presets.addons(tags, nil, "design")
  local where = "design/" .. p.category .. "/" .. p.id
  ok(where .. ": at least 8 add-ons fit it", #fit >= 8)
  local per = {}
  for a in pairs(presets.preselect(fit, tags, p.id, p.category)) do
    if presets.exclusive(a.group) then
      per[a.group] = (per[a.group] or 0) + 1
    end
  end
  for group, n in pairs(per) do
    eq(where .. ": one preselected " .. group, n, 1)
  end
  for _, a in ipairs(fit) do
    local merged = compose.merge(p.body, a.body)
    eq(where .. " + " .. a.id .. ": still every section", compose.missing(merged, "design"), {})
    eq(where .. " + " .. a.id .. ": twice = once", compose.merge(merged, a.body), merged)
  end
end
local cats = presets.categories()
ok("stack: categories found", #cats >= 4)
eq("stack: the known categories come first, in order", cats[1] and cats[1].id, "backend")
local stacks = 0
for _, c in ipairs(cats) do
  stacks = stacks + #check_folder("stack/" .. c.id, "stack")
end
ok("stack: many stacks across the categories", stacks >= 20)
local principles = check_folder("principles", nil)
ok("principles: there are many", #principles >= 10)
ok("principles: some are core (checked by default), not all", #vim.tbl_filter(function(p)
  return p.core
end, principles) >= 3 and #vim.tbl_filter(function(p)
  return not p.core
end, principles) >= 3)

-- add-ons: parse, only STACK.md sections, rows with the right number of cells, every stack gets some
local STACK_SECTIONS = {}
for _, sec in ipairs(compose.doc("stack").sections) do
  STACK_SECTIONS[sec] = true
end
local addon_count = 0
for axis, kind in vim.fs.dir(presets.dir() .. "/addons") do
  if kind == "directory" then
    local files = 0
    for file in vim.fs.dir(presets.dir() .. "/addons/" .. axis) do
      files = files + (file:match "%.md$" and 1 or 0)
    end
    local list = presets.list("addons/" .. axis)
    eq("addons/" .. axis .. ": every file is an add-on", #list, files)
    for _, a in ipairs(list) do
      addon_count = addon_count + 1
      local where = "addons/" .. axis .. "/" .. a.id
      ok(where .. ": desc <= 110", #a.desc <= 110)
      ok(where .. ": no title line (only sections)", not a.body:find "^# " and not a.body:find "\n# ")
      for _, h in ipairs(compose.headings(a.body)) do
        ok(where .. ": `## " .. h .. "` is a STACK.md section", STACK_SECTIONS[h] == true)
      end
      for line in a.body:gmatch "[^\n]+" do
        if line:match "^|" then
          local cells = select(2, line:gsub("|", "")) - 1
          ok(where .. ": a table row has 2 or 3 cells: " .. line:sub(1, 40), cells == 2 or cells == 3)
        end
      end
      local fences = select(2, ("\n" .. a.body):gsub("\n```", ""))
      eq(where .. ": code fences are closed", fences % 2, 0)
    end
  end
end
ok("addons: many to choose from", addon_count >= 15)
for _, c in ipairs(presets.categories()) do
  for _, p in ipairs(presets.list("stack/" .. c.id)) do
    local fit = presets.addons(presets.tags(p, c.id))
    ok("stack/" .. c.id .. "/" .. p.id .. ": at least 3 add-ons fit it", #fit >= 3)
    for _, a in ipairs(fit) do
      local merged = compose.merge(p.body, a.body)
      local where = "stack/" .. c.id .. "/" .. p.id .. " + " .. a.id
      eq(where .. ": still every section", compose.missing(merged, "stack"), {})
      eq(where .. ": applying twice changes nothing", compose.merge(merged, a.body), merged)
    end
  end
end

-- preselection: the best picks per stack, one at most in a one-of group
local function picks(category, id)
  for _, p in ipairs(presets.list("stack/" .. category)) do
    if p.id == id then
      local tags = presets.tags(p, category)
      local addons = presets.addons(tags)
      local picked = presets.preselect(addons, tags, p.id, category)
      local out = {}
      for _, a in ipairs(addons) do
        if picked[a] then
          out[a.id] = true
        end
      end
      return out
    end
  end
  return {}
end
for _, c in ipairs(presets.categories()) do
  for _, p in ipairs(presets.list("stack/" .. c.id)) do
    local tags = presets.tags(p, c.id)
    local addons = presets.addons(tags)
    local per = {}
    for a in pairs(presets.preselect(addons, tags, p.id, c.id)) do
      if presets.exclusive(a.group) then
        per[a.group] = (per[a.group] or 0) + 1
      end
    end
    for group, n in pairs(per) do
      eq("preselect " .. c.id .. "/" .. p.id .. ": one " .. group, n, 1)
    end
  end
end
local nx = picks("web", "nextjs")
ok(
  "preselect nextjs: Vercel, TS 7, Biome, Tailwind, GitHub Actions",
  nx.vercel and nx.ts7 and nx.biome and nx.tailwind4 and nx["github-actions"]
)
ok("preselect nextjs: not Cloudflare", not nx.cloudflare)
local ga = picks("backend", "go-api")
ok("preselect go-api: Docker self-hosted, OpenTelemetry", ga["docker-selfhosted"] and ga.opentelemetry)
ok("preselect go-api: no TypeScript things", not ga.ts7 and not ga.biome and not ga.tailwind4)
ok("preselect go-huma: no TypeScript things (its text names TS clients)", not picks("backend", "go-huma").ts7)
local fr = picks("mobile", "flutter-firebase")
ok("preselect flutter-firebase: stores, no TS 7 (Cloud Functions are TS)", fr["stores-fastlane"] and not fr.ts7)
ok("preselect go-bubbletea: GoReleaser", picks("cli-desktop", "go-bubbletea").goreleaser)
ok("preselect rust-ratatui: cargo-dist", picks("cli-desktop", "rust-ratatui")["cargo-dist"])
ok("preselect lit: no Tailwind (shadow DOM)", not picks("web", "lit").tailwind4)

-- ── compose ──────────────────────────────────────────────────────────────────

eq(
  "clean: fence and chatter removed",
  compose.clean "Sure! Here it is:\n```markdown\n# SPEC.md: X\n\n## Summary\nhi\n```\n",
  "# SPEC.md: X\n\n## Summary\nhi\n"
)
eq("clean: a plain answer stays", compose.clean "# A\n\ntext\n\n\n", "# A\n\ntext\n")
eq("clean: chatter before the heading dropped", compose.clean "Here you go\n\n# A\nx", "# A\nx\n")
eq("headings: not inside code fences", compose.headings "## A\n```\n## not\n```\n## B\n", { "A", "B" })
eq(
  "missing: what a spec lacks",
  #compose.missing("# S\n## Summary\n## Goals\n", "spec"),
  #compose.doc("spec").sections - 2
)

local p1 = { name = "SOLID", body = "### SOLID\n\n- one\n" }
local p2 = { name = "Testing", body = "### Testing\n\n- two\n" }
local stack = "# STACK.md: X\n\n## Summary\n\ns\n\n## Rules for agents\n\n- r\n"
local with = compose.set_principles(stack, { p1, p2 })
ok("set_principles: appended at the end", with:find "## Rules for agents\n\n%- r\n\n## Engineering principles\n" ~= nil)
eq("principles_in: titles read back", compose.principles_in(with), { "SOLID", "Testing" })
local again = compose.set_principles(with, { p2 })
eq("set_principles: replaced, not added twice", compose.principles_in(again), { "Testing" })
eq("set_principles: once only", select(2, again:gsub("## Engineering principles", "")), 1)
eq("set_principles: none removes it", compose.set_principles(with, {}), stack)
local middle =
  compose.set_principles(stack:gsub("## Rules", "## Engineering principles\n\n### Old\n\n## Rules"), { p1 })
ok("set_principles: in the middle stays in the middle", middle:find "### SOLID.-## Rules for agents" ~= nil)
eq("set_principles: the old one gone", compose.principles_in(middle), { "SOLID" })

-- merge: rows replaced by their first word, lines added once, missing sections created before the principles
local base_stack = table.concat({
  "# STACK.md: X",
  "",
  "## Stack",
  "",
  "| Layer | Choice | Why |",
  "| --- | --- | --- |",
  "| Language | Go | fast |",
  "| Deploy | Fly.io | easy |",
  "",
  "## Commands",
  "",
  "| Task | Command |",
  "| --- | --- |",
  "| Test | `go test ./...` |",
  "",
  "## Rules for agents",
  "",
  "- one",
  "",
  "## Engineering principles",
  "",
  "### SOLID",
}, "\n") .. "\n"
local addon =
  "## Stack\n\n| Deploy | Docker | own server |\n| CI | GitHub Actions | free |\n\n## Commands\n\n| Deploy | `docker compose up -d` |\n\n## Rules for agents\n\n- one\n- two\n\n## Testing\n\n- e2e in CI\n"
local merged = compose.merge(base_stack, addon)
ok(
  "merge: a row with the same first word replaced",
  merged:find("| Deploy | Docker | own server |", 1, true) and not merged:find("Fly.io", 1, true)
)
ok(
  "merge: a new row at the end of the table",
  merged:find("| Deploy | Docker | own server |\n| CI | GitHub Actions | free |\n\n## Commands", 1, true)
)
ok(
  "merge: a row added to another section's table",
  merged:find("| Test | `go test ./...` |\n| Deploy | `docker compose up -d` |", 1, true)
)
ok("merge: only new lines added", merged:find("- one\n- two\n\n## Testing", 1, true))
ok(
  "merge: a missing section goes before the principles",
  merged:find("## Testing\n\n- e2e in CI\n\n## Engineering principles", 1, true)
)
eq("merge: twice = once", compose.merge(merged, addon), merged)
ok("applied: yes after merging", compose.applied(merged, addon))
ok("applied: no before", not compose.applied(base_stack, addon))

-- package manager: a pnpm preset written for bun / npm
local pnpm_text =
  "| Package manager | pnpm | strict |\n| Install | `pnpm install` |\n| Test | `pnpm test` |\n| Dev | `pnpm dev` |\n- CI runs `pnpm install --frozen-lockfile`, commits `pnpm-lock.yaml`, `pnpm dlx shadcn add button`, `pnpm add -D vitest`.\n- pnpm workspaces\n"
eq("package_manager: pnpm found", compose.package_manager(pnpm_text), "pnpm")
local bun = compose.use_package_manager(pnpm_text, "bun")
ok("bun: the Stack row", bun:find("| Package manager | Bun (", 1, true))
ok(
  "bun: commands",
  bun:find("`bun install`", 1, true) and bun:find("`bun run test`", 1, true) and bun:find("`bun run dev`", 1, true)
)
ok(
  "bun: lockfile, dlx, add -D",
  bun:find(
    "`bun install --frozen-lockfile`, commits `bun.lock`, `bunx shadcn add button`, `bun add -d vitest`",
    1,
    true
  )
)
ok("bun: prose", bun:find("- Bun workspaces", 1, true))
eq("bun: no pnpm left", bun:find("pnpm", 1, true), nil)
local npm = compose.use_package_manager(pnpm_text, "npm")
ok(
  "npm: commands",
  npm:find("`npm install`", 1, true) and npm:find("`npm test`", 1, true) and npm:find("`npm run dev`", 1, true)
)
ok(
  "npm: ci, lockfile, npx, -D",
  npm:find("`npm ci`, commits `package-lock.json`, `npx shadcn add button`, `npm install -D vitest`", 1, true)
)
eq("npm: no pnpm left", npm:find("pnpm", 1, true), nil)

local chain =
  "| M | `pnpm drizzle-kit generate && pnpm drizzle-kit migrate` |\n| U | `pnpm vitest run` |\n| D | `pnpm db:push` |\n"
eq(
  "npm: tools with npx, scripts with run, after && too",
  compose.use_package_manager(chain, "npm"),
  "| M | `npx drizzle-kit generate && npx drizzle-kit migrate` |\n| U | `npx vitest run` |\n| D | `npm run db:push` |\n"
)
ok("bun: after && too", compose.use_package_manager(chain, "bun"):find("&& bun run drizzle-kit migrate", 1, true))
for _, c in ipairs(presets.categories()) do
  if c.id ~= "monorepo" then
    for _, p in ipairs(presets.list("stack/" .. c.id)) do
      if compose.package_manager(p.body) == "pnpm" then
        for _, to in ipairs { "bun", "npm" } do
          local out = compose.use_package_manager(p.body, to)
          eq("stack/" .. c.id .. "/" .. p.id .. " → " .. to .. ": no pnpm left", out:find("pnpm", 1, true), nil)
          eq(
            "stack/" .. c.id .. "/" .. p.id .. " → " .. to .. ": no command left capitalised",
            out:match "`Bun [%w%-]+" or out:match "&& Bun ",
            nil
          )
        end
      end
    end
  end
end

-- tags: from the stack's words
local tg = presets.tags({
  id = "x",
  body = "# S\n\n## Summary\n\nA TypeScript API on Node with pnpm.\n\n## Stack\n\n| Language | Go |\n\n## Project layout\n\ngo_router flutter\n",
}, "backend")
ok(
  "tags: category, id, kind words, language from the row",
  tg.backend and tg.x and tg.node and tg.pnpm and tg.go and tg["lang:go"] and tg.server and tg.all
)
ok("tags: a language named in prose does not count when the table says another", not tg.ts)
local described = presets.tags({ id = "d", body = "a typescript api with bun" }, nil)
ok(
  "tags: a description (no table) names languages by its words",
  described.ts and described.bun and described["lang:typescript"]
)
ok("tags: not from the layout (go_router, flutter)", not tg.flutter)

local agents =
  "# AGENTS.md\n\nIntro.\n\n## Project\n\nx\n\n## Read first\n\n- [STACK.md](STACK.md): s.\n- Read the code.\n\n## Commands\n"
local linked, added = compose.link_docs(agents, { "AGENTS.md", "STACK.md", "SPEC.md" })
eq("link_docs: only what is there and not linked", added, { "SPEC.md" })
ok(
  "link_docs: inside Read first, before the next section",
  linked:find "%- Read the code%.\n%- %[SPEC%.md%]%(SPEC%.md%).-\n\n## Commands" ~= nil
)
eq("link_docs: nothing to add = same text", select(2, compose.link_docs(linked, { "SPEC.md", "STACK.md" })), {})
local fresh = compose.link_docs("# AGENTS.md\n\nIntro.\n\n## Project\n\nx\n", { "DESIGN.md" })
ok(
  "link_docs: section created before the first one",
  fresh:find "Intro%.\n\n## Read first\n\n%- %[DESIGN%.md%]%(DESIGN%.md%).-\n\n## Project" ~= nil
)

local list = {
  { id = "linear", name = "Linear" },
  { id = "material3", name = "Material 3" },
  { id = "m3-expressive", name = "M3 Expressive" },
}
eq("named: a system in a sentence", compose.named("Like linear but warmer", list).id, "linear")
eq("named: multi-word names", compose.named("start from material 3, rounder", list).id, "material3")
eq("named: the longer match wins", compose.named("M3 Expressive with our blue", list).id, "m3-expressive")
eq("named: nothing named", compose.named("dark and dense", list), nil)
eq("named: no partial words", compose.named("nonlinear layouts", list), nil)

-- ── snapshot and the 0-token AGENTS.md ──────────────────────────────────────

eq(
  "languages: by files",
  snapshot.languages { "a.go", "b.go", "web/x.ts", "README.md", "y.tsx" },
  { { name = "Go", files = 2 }, { name = "TypeScript", files = 2 } }
)
eq(
  "make_targets: own targets only",
  snapshot.make_targets ".PHONY: test\nbuild: deps\n\tgo build\ntest:\n%.o: %.c\nVAR := 1\n",
  { "build", "test" }
)
local function labels(cmds)
  return vim.tbl_map(function(c)
    return c.label .. "=" .. c.cmd
  end, cmds)
end
eq(
  "commands: Makefile first, then go",
  labels(snapshot.commands { files = { "go.mod", "Makefile" }, targets = { "test", "lint" } }),
  { "test=make test", "lint=make lint", "install=go mod download", "build=go build ./...", "format=gofmt -w ." }
)
eq(
  "commands: package manager from the lockfile",
  labels(
    snapshot.commands { files = { "package.json", "pnpm-lock.yaml" }, scripts = { dev = "vite", test = "vitest" } }
  ),
  { "install=pnpm install", "dev=pnpm run dev", "test=pnpm test" }
)
eq(
  "commands: npm runs scripts with `run` (not test)",
  labels(snapshot.commands { files = { "package.json" }, scripts = { build = "tsc", test = "jest" } }),
  { "install=npm install", "build=npm run build", "test=npm test" }
)
eq(
  "commands: bun runs the script, not its own runner",
  labels(snapshot.commands { files = { "package.json", "bun.lock" }, scripts = { test = "vitest" } }),
  { "install=bun install", "test=bun run test" }
)
eq(
  "commands: python tools only when declared, runner from the lockfile",
  labels(snapshot.commands {
    files = { "pyproject.toml", "poetry.lock" },
    manifests = { ["pyproject.toml"] = "[tool.poetry.group.dev.dependencies]\npytest = '*'\n" },
  }),
  { "install=poetry install", "test=poetry run pytest" }
)
eq(
  "commands: plain pip guesses no tools",
  labels(snapshot.commands { files = { "requirements.txt" }, manifests = { ["requirements.txt"] = "flask\n" } }),
  { "install=pip install -r requirements.txt" }
)
eq(
  "commands: wrappers when they are there",
  labels(snapshot.commands { files = { "pom.xml", "mvnw" } }),
  { "build=./mvnw -q package", "test=./mvnw -q test" }
)
eq(
  "commands: deno",
  labels(snapshot.commands { files = { "deno.json" }, deno_tasks = { dev = "deno run main.ts" } }),
  { "dev=deno task dev", "test=deno test", "lint=deno lint", "format=deno fmt" }
)
eq(
  "commands: composer scripts and tools",
  labels(snapshot.commands {
    files = { "composer.json" },
    composer_scripts = { test = "pest" },
    manifests = { ["composer.json"] = '"phpstan/phpstan": "^2"' },
  }),
  { "install=composer install", "test=composer test", "lint=vendor/bin/phpstan analyse" }
)
eq(
  "commands: flutter app",
  labels(snapshot.commands { files = { "pubspec.yaml", "lib/main.dart" } }),
  { "install=flutter pub get", "test=flutter test", "lint=flutter analyze", "format=dart format .", "run=flutter run" }
)
eq(
  "project_name: package.json",
  snapshot.project_name({ ["package.json"] = '{ "name": "shopfront", "private": true }' }, "web"),
  "shopfront"
)
eq(
  "project_name: pubspec",
  snapshot.project_name({ ["pubspec.yaml"] = "name: fleet_app\ndescription: x\n" }, "app"),
  "fleet_app"
)
eq(
  "project_name: go module's last segment",
  snapshot.project_name({ ["go.mod"] = "module github.com/acme/invoices\n\ngo 1.23\n" }, "go"),
  "invoices"
)
eq(
  "project_name: Cargo",
  snapshot.project_name({ ["Cargo.toml"] = '[package]\nname = "fastgrep"\nversion = "0.1.0"\n' }, "x"),
  "fastgrep"
)
eq(
  "project_name: pyproject",
  snapshot.project_name({ ["pyproject.toml"] = '[project]\nname = "cfdi-api"\n' }, "x"),
  "cfdi-api"
)
eq("project_name: the folder when nothing says", snapshot.project_name({}, "shop"), "shop")
local tree = snapshot.tree { "go.mod", "cmd/web/main.go", "internal/domain/order.go", "internal/app/place.go" }
eq("tree: folders with counts, two levels, then top files", tree, {
  "cmd/ (1)",
  "  web/ (1)",
  "internal/ (2)",
  "  app/ (1)",
  "  domain/ (1)",
  "go.mod",
})

local shop = project("shop", {
  ["go.mod"] = "module example.com/shop\n\ngo 1.23\n",
  ["Makefile"] = "test:\n\tgo test ./...\n",
  ["README.md"] = "# Shop\n\nSells things.\n",
  ["cmd/api/main.go"] = "package main\n",
  ["internal/order/order.go"] = "package order\n",
  ["STACK.md"] = "# STACK.md: Go\n",
})
vim.system({ "git", "init", "-q" }, { cwd = shop }):wait()
local facts = snapshot.collect(shop)
eq("collect: name", facts.name, "shop")
ok("collect: files listed (untracked included)", vim.tbl_contains(facts.files, "internal/order/order.go"))
ok("collect: manifests read", facts.manifests["go.mod"] and facts.manifests["go.mod"]:find "example.com/shop")
eq("collect: Makefile targets", facts.targets, { "test" })
ok("collect: README head", facts.readme and facts.readme:find "Sells things")
eq("collect: kit documents there", vim.tbl_keys(facts.docs), { "STACK.md" })
eq("root: the repository's root from a subfolder", snapshot.root(shop .. "/internal/order"), shop)

local t = template.agents(facts)
eq("template: every AGENTS.md section", compose.missing(t, "agents"), {})
ok(
  "template: the real commands",
  t:find("| test | `make test` |", 1, true) and t:find("| build | `go build ./...` |", 1, true)
)
ok("template: links the documents there", t:find("- [STACK.md](STACK.md)", 1, true))
ok("template: not the ones missing", not t:find("[SPEC.md]", 1, true))
ok("template: top folders", t:find("\ncmd/ (1)\n", 1, true) and not t:find("  api/", 1, true))

-- ── prompts ─────────────────────────────────────────────────────────────────

local req = prompts.agents(facts)
ok("prompt agents: names every section", req.prompt:find("## Definition of done", 1, true))
ok(
  "prompt agents: the manifests, tagged",
  req.prompt:find('<file path="go.mod">\nmodule example.com/shop', 1, true) and req.prompt:find("</file>", 1, true)
)
ok("prompt agents: no <current> when there is none", not req.prompt:find("<current>", 1, true))
eq("prompt agents: main tier, own name", { req.tier, req.action }, { "main", "kit_agents" })
local d = prompts.design("like Linear", { body = "# DESIGN.md: Linear\n" }, { "Linear" })
ok("prompt design: the base preset goes along", d.prompt:find("<base>\n# DESIGN.md: Linear", 1, true))
local s = prompts.stack("Go API", { "SOLID", "Testing" })
ok(
  "prompt stack: the principles named, not written",
  s.prompt:find("SOLID, Testing", 1, true) and s.prompt:find('Do NOT write an "Engineering principles"', 1, true)
)
ok(
  "prompt spec: open questions instead of inventions",
  prompts.spec("an app").prompt:find("Never fill a gap with an invention", 1, true)
)

-- ── flows (fake model, canned answers to the modals) ─────────────────────────

local kit = require "agent.kit"
local answer = "# SPEC.md: Shop\n\n## Summary\nx\n"
package.loaded["agent"] = {
  complete = function(r, cb)
    notes[#notes + 1] = "asked: " .. r.action
    cb(true, "```markdown\n" .. answer .. "```")
  end,
}
package.loaded["agent.selection"] = {
  current = function()
    return { backend = "fake", model = "m" }
  end,
  label = function()
    return "fake/m"
  end,
}
local confirms = {}
package.loaded["utils.modal"] = {
  hl = setmetatable({}, {
    __index = function(_, k)
      return k
    end,
  }),
  confirm = function(lines, opts, yes)
    confirms[#confirms + 1] = opts.confirm
    if opts.answer_no then
      return opts.on_cancel and opts.on_cancel()
    end
    yes()
  end,
  checklist = function(items, _, done)
    local out = {}
    for i, item in ipairs(items) do
      if item.checked then
        out[#out + 1] = i
      end
    end
    done(out)
  end,
}
local drafts = {}
package.loaded["agent.kit.draft"] = {
  open = function(opts, submit)
    drafts[#drafts + 1] = opts
    submit "we sell shoes online"
  end,
  forget = function() end,
}
local function in_project(dir)
  vim.cmd.edit(vim.fn.fnameescape(dir .. "/cmd/api/main.go"))
end

in_project(shop)
kit.spec()
eq("spec: written from the draft, cleaned", read(shop .. "/SPEC.md"), answer)
eq("spec: the draft starts empty when there is no SPEC.md", drafts[#drafts].text, nil)
answer = "# SPEC.md: Shop v2\n\n## Summary\ny\n"
in_project(shop)
kit.spec()
eq("spec: the draft starts from the current one", drafts[#drafts].text, "# SPEC.md: Shop\n\n## Summary\nx\n")
eq("spec: rewritten", read(shop .. "/SPEC.md"), answer)
local trashed = require("files.ops").last_trashed()
ok(
  "spec: the old one is in the trash",
  trashed and trashed.from == shop .. "/SPEC.md" and read(trashed.stored):find "# SPEC.md: Shop\n"
)

-- STACK.md from a preset is replaced only after a yes; the principles come from the checklist (core ones)
package.loaded["tasks.picker"] = {
  choose = function(items, _, fn)
    fn(items[1].value)
  end,
}
in_project(shop)
confirms = {}
kit.stack()
eq("stack: asks before replacing the one there", confirms, { "Replace" })
local stack_text = read(shop .. "/STACK.md")
ok("stack: a preset was written", stack_text:find "^# STACK.md: " ~= nil)
local core = vim.tbl_map(
  function(p)
    return p.name
  end,
  vim.tbl_filter(function(p)
    return p.core
  end, principles)
)
eq("stack: with the core principles", compose.principles_in(stack_text), core)

-- AGENTS.md: template, then links the others; the model's update keeps the old as input
in_project(shop)
kit.agents_template()
local agents_text = read(shop .. "/AGENTS.md")
ok("agents template: written", agents_text and agents_text:find "## Definition of done")
ok(
  "agents template: links STACK.md and SPEC.md",
  agents_text:find("[STACK.md]", 1, true) and agents_text:find("[SPEC.md]", 1, true)
)
write(shop .. "/DESIGN.md", "# DESIGN.md: x\n")
eq("link: a document created later is added to Read first", kit.link(shop), { "DESIGN.md" })
ok("link: there now", read(shop .. "/AGENTS.md"):find("[DESIGN.md](DESIGN.md)", 1, true))

answer = "# AGENTS.md\n\n## Project\nshop\n"
local seen_prompt
package.loaded["agent"].complete = function(r, cb)
  seen_prompt = r.prompt
  cb(true, answer)
end
in_project(shop)
confirms = {}
kit.agents()
eq("agents: asks to update the one there", confirms, { "Update" })
ok("agents: the current one goes to the model", seen_prompt and seen_prompt:find("<current>\n# AGENTS.md", 1, true))
eq("agents: written", read(shop .. "/AGENTS.md"), answer)
ok(
  "agents: warns about the sections the answer left out",
  vim.iter(notes):any(function(n)
    return n:find("AGENTS.md came without Read first", 1, true) ~= nil
  end)
)

-- a busy document is not asked twice; a failed request writes nothing
local pending
package.loaded["agent"].complete = function(_, cb)
  pending = cb
end
local empty = project("empty", { ["cmd/api/main.go"] = "package main\n" })
vim.system({ "git", "init", "-q" }, { cwd = empty }):wait()
in_project(empty)
kit.spec()
local before = #notes
kit.spec()
ok("busy: the second request is refused", notes[#notes]:find("already being written", 1, true) and #notes == before + 1)
pending(false, "boom")
eq("failed: nothing written", read(empty .. "/SPEC.md"), nil)

-- CLAUDE.md imports AGENTS.md; an existing one gets the line added once
in_project(empty)
kit.claude()
ok("claude: created with @AGENTS.md", read(empty .. "/CLAUDE.md"):find("\n@AGENTS.md\n", 1, true))
write(shop .. "/CLAUDE.md", "# Mine\n\nrules\n")
in_project(shop)
kit.claude()
eq("claude: the line added to the one there", read(shop .. "/CLAUDE.md"), "# Mine\n\nrules\n\n@AGENTS.md\n")
kit.claude()
eq("claude: not twice", read(shop .. "/CLAUDE.md"), "# Mine\n\nrules\n\n@AGENTS.md\n")

-- principles: the checklist starts from what STACK.md carries
local principles_seen
package.loaded["utils.modal"].checklist = function(items, _, done)
  principles_seen = vim.tbl_map(
    function(i)
      return i.label
    end,
    vim.tbl_filter(function(i)
      return i.checked
    end, items)
  )
  done { 1 }
end
in_project(shop)
kit.principles()
eq("principles: checked = what STACK.md has", principles_seen, core)
eq("principles: replaced by the new choice", compose.principles_in(read(shop .. "/STACK.md")), { principles[1].name })

-- design: kind → design → customize (best picks) → written with its add-ons merged
package.loaded["utils.modal"].checklist = function(items, _, done)
  local out = {}
  for i, item in ipairs(items) do
    if item.checked then
      out[#out + 1] = i
    end
  end
  done(out)
end
local picked_titles = {}
package.loaded["tasks.picker"].choose = function(items, opts, fn)
  picked_titles[#picked_titles + 1] = opts.title
  for _, it in ipairs(items) do
    if it.label == "Terminal / TUI" or it.label:find("ASCII", 1, true) then
      return fn(it.value)
    end
  end
  fn(items[1].value)
end
local fresh = project("design", { ["main.go"] = "package main\n" })
vim.system({ "git", "init", "-q" }, { cwd = fresh }):wait()
vim.cmd.edit(vim.fn.fnameescape(fresh .. "/main.go"))
kit.design()
local design_text = read(fresh .. "/DESIGN.md") or ""
eq("design: kind then design pickers", picked_titles, { "Design", "Terminal / TUI" })
ok(
  "design: an ASCII art terminal design written",
  design_text:find "^# DESIGN.md: " ~= nil and design_text:find("ASCII", 1, true) ~= nil
)
ok("design: the best picks merged (inherit the terminal)", design_text:find("The terminal decides", 1, true) ~= nil)
eq("design: every section", compose.missing(design_text, "design"), {})

-- build: the plan, safe paths, the file's text, errors mapped to files, the missing documents, a whole run (fake model)
local bplan = require "agent.kit.build.plan"
local bprompt = require "agent.kit.build.prompt"
local bverify = require "agent.kit.build.verify"
for _, bad in ipairs { "/etc/passwd", "../x.go", "a/../../b", "~/.ssh/k", "C:/w", ".git/config", "a\\b", "" } do
  ok("build plan: unsafe path refused: " .. bad, not bplan.safe(bad))
end
ok("build plan: a normal path", bplan.safe "internal/calc/eval.go")
local parsed =
  bplan.parse 'Here: {"name":"calc","files":[{"path":"go.mod","purpose":"module","docs":["stack"]},{"path":"../evil","purpose":"x"},{"path":"main.go","purpose":"entry","docs":["spec","nope"],"needs":["go.mod","later.go"]},{"path":"later.go","purpose":"l"}]}'
eq(
  "build plan: unsafe and duplicated dropped",
  vim.tbl_map(function(f)
    return f.path
  end, parsed.files),
  { "go.mod", "main.go", "later.go" }
)
eq("build plan: unknown docs dropped", parsed.files[2].docs, { "spec" })
eq("build plan: needs only earlier files", parsed.files[2].needs, { "go.mod" })
eq("build plan: no JSON", select(2, bplan.parse "sorry"), "the answer has no JSON object")
eq("build content: fence removed", bprompt.content "```go\npackage main\n```\n", "package main\n")
eq("build content: plain kept", bprompt.content "package main\n\n", "package main\n")
local freq = bprompt.file(
  parsed.files[2],
  parsed,
  { spec = "S", stack = "T", design = "D" },
  { ["go.mod"] = "module x" }
)
ok(
  "build file request: every document and the plan in the system prompt (one cached prefix for the whole build)",
  freq.system:find("<spec>", 1, true)
    and freq.system:find("<design>", 1, true)
    and freq.system:find("- main.go: entry", 1, true)
)
eq(
  "build file request: the same system prompt for every file",
  bprompt.file(parsed.files[1], parsed, { spec = "S", stack = "T", design = "D" }, {}).system,
  freq.system
)
ok(
  "build file request: the message has the focus, the files it uses and the task",
  freq.prompt:find("Focus on: SPEC.md", 1, true)
    and freq.prompt:find('<file path="go.mod">', 1, true)
    and freq.prompt:find("Write `main.go`", 1, true)
    and not freq.prompt:find("<spec>", 1, true)
)
eq(
  "build blame: errors mapped to planned files",
  bverify.blame(
    "# x\n./internal/ui/view.go:12:3: undefined: Foo\nmain.go:4:2: bad\nvendor/z.go:1:1: no\ninternal/ui/view.go\n",
    { "internal/ui/view.go", "main.go" }
  ),
  {
    ["internal/ui/view.go"] = { "./internal/ui/view.go:12:3: undefined: Foo", "internal/ui/view.go" },
    ["main.go"] = { "main.go:4:2: bad" },
  }
)
eq(
  "build blame: go vet's `vet: ` prefix",
  bverify.blame(
    "# ascii-calc/internal/ui\nvet: internal/ui/app_test.go:60:5: tm.WaitFor undefined\n",
    { "internal/ui/app_test.go" }
  ),
  { ["internal/ui/app_test.go"] = { "vet: internal/ui/app_test.go:60:5: tm.WaitFor undefined" } }
)
eq(
  "build outside: a file the build did not write",
  bverify.outside("x/old.go:3:1: boom\nmain.go:1:1: e\n", { "main.go" }),
  { "x/old.go" }
)
local broot = project("buildme", { ["AGENTS.md"] = "# A\n", ["STACK.md"] = "# S\n", ["SPEC.md"] = "# P\n" })
vim.system({ "git", "init", "-q" }, { cwd = broot }):wait()
local bdocs, bmissing = require("agent.kit.build").docs(broot)
eq("build docs: the missing one named", bmissing, { "DESIGN.md" })
vim.cmd.edit(vim.fn.fnameescape(broot .. "/AGENTS.md"))
local before_notes = #notes
require("agent.kit.build").run()
ok(
  "build: refuses with the missing document and its key",
  notes[#notes]:find("missing DESIGN.md (<leader>aSd)", 1, true) and #notes == before_notes + 1
)
write(broot .. "/DESIGN.md", "# D\n")
local asked = {}
package.loaded["agent"].complete = function(r, cb)
  asked[#asked + 1] = r.action
  if r.action == "kit_build_plan" then
    return cb(
      true,
      '{"name":"t","files":[{"path":"src/a.txt","purpose":"a","docs":["spec"]},{"path":"README.md","purpose":"r","needs":["src/a.txt"]}]}',
      { tokens_in = 10, tokens_out = 5 }
    )
  end
  if r.on_text then
    r.on_text "hel"
    r.on_text "lo"
  end
  cb(true, "```\nhello " .. r.prompt:match "Write `([^`]+)`" .. "\n```", { tokens_in = 3, tokens_out = 2 })
end
vim.cmd.edit(vim.fn.fnameescape(broot .. "/AGENTS.md"))
local build = require "agent.kit.build"
local bstate = require "agent.kit.build.state"
build.open()
eq("build: opens on the pre-flight, nothing asked yet", { bstate.run.phase, #asked }, { "ready", 0 })
ok("build: the view is up", require("agent.kit.build.view").shown())
build.go()
eq("build: Enter plans, then waits on the review", { bstate.run.phase, asked }, { "review", { "kit_build_plan" } })
ok("build: the review has an estimate per file", bstate.run.files[1].estimate and bstate.run.estimate.tokens > 0)
build.toggle_skip "README.md"
eq("build: x skips a file", bstate.run.files[2].state, "skipped")
build.toggle_skip "README.md"
build.cycle "files"
eq("build: 2 switches the files' tier", bstate.run.tiers.files, "light")
build.go()
vim.wait(1000, function()
  return bstate.run.phase == "done"
end)
eq("build: plan then one request per file", asked, { "kit_build_plan", "kit_build_file", "kit_build_file" })
eq(
  "build: files written, fence-free",
  { read(broot .. "/src/a.txt"), read(broot .. "/README.md") },
  { "hello src/a.txt\n", "hello README.md\n" }
)
eq("build: the totals add every request", bstate.run.totals.requests, 3)
ok(
  "build: saved, and a done run does not resume",
  bstate.load(broot) ~= nil and not bstate.resumable(bstate.load(broot))
)
ok(
  "build: the request of a file is kept for `p`",
  build.sent "src/a.txt" and build.sent("src/a.txt").prompt:find("Write `src/a.txt`", 1, true)
)
eq("build: no statusline when nothing runs", bstate.statusline(), "")

-- stop in the middle, then resume from the file it stopped at
local hold
package.loaded["agent"].complete = function(r, cb)
  asked[#asked + 1] = r.action
  if r.action == "kit_build_plan" then
    return cb(true, '{"name":"t","files":[{"path":"one.txt","purpose":"1"},{"path":"two.txt","purpose":"2"}]}', {})
  end
  if r.prompt:find("Write `two.txt`", 1, true) and not hold then
    hold = cb -- never answers: the stop comes first
    return { kill = function() end }
  end
  cb(true, "x", { cost = 0.001 })
  return { kill = function() end }
end
build.restart()
build.go()
build.go()
vim.wait(200)
eq("build: running on the second file", { bstate.run.running, bstate.run.current }, { true, "two.txt" })
ok("build: the statusline shows it", bstate.statusline():find("build 1/2", 1, true))
build.stop()
eq(
  "build: stopped, the file back to pending",
  { bstate.run.phase, bstate.file("two.txt").state },
  { "stopped", "pending" }
)
hold(true, "late answer", {})
eq("build: a late answer after the stop is dropped", read(broot .. "/two.txt"), nil)
ok("build: a stopped run can resume", bstate.resumable(bstate.load(broot)))
bstate.run = nil
vim.cmd "silent! tabonly"
vim.cmd.edit(vim.fn.fnameescape(broot .. "/AGENTS.md"))
build.open()
ok(
  "build: reopened, the saved run is offered to resume",
  bstate.run.outcome and bstate.run.outcome:find("⏎ continues", 1, true)
)
build.go()
vim.wait(1000, function()
  return bstate.run.phase == "done"
end)
eq(
  "build: resumed from the file it stopped at",
  { read(broot .. "/one.txt"), read(broot .. "/two.txt") },
  { "x\n", "x\n" }
)
vim.cmd "silent! tabonly"

-- library: every preset in one list; use merges an add-on / adds a principle; embed inserts at the cursor
local lib = require "agent.kit.library"
local all = lib.entries()
local kinds = {}
for _, e in ipairs(all) do
  kinds[e.kind] = (kinds[e.kind] or 0) + 1
end
ok(
  "library: every kind is there",
  kinds.stack and kinds.design and kinds["stack add-on"] and kinds["design add-on"] and kinds.principle
)
eq(
  "library: as many as the folders hold",
  #all,
  #presets.all "stack" + #presets.all "design" + kinds["stack add-on"] + kinds["design add-on"] + #principles
)
local libroot = project(
  "library",
  {
    ["STACK.md"] = "# STACK.md: x\n\n## Stack\n\n| Layer | Choice | Why |\n| --- | --- | --- |\n| Language | Go | x |\n\n## Rules for agents\n\n- r\n",
  }
)
vim.system({ "git", "init", "-q" }, { cwd = libroot }):wait()
vim.cmd "silent! tabonly"
vim.cmd.edit(vim.fn.fnameescape(libroot .. "/STACK.md"))
local function entry(kind, id)
  for _, e in ipairs(all) do
    if e.kind == kind and e.preset.id == id then
      return e
    end
  end
end
lib.use(entry("stack add-on", "github-actions"))
ok("library use: an add-on merged into STACK.md", read(libroot .. "/STACK.md"):find("GitHub Actions", 1, true))
lib.use(entry("principle", "solid"))
eq("library use: a principle added", compose.principles_in(read(libroot .. "/STACK.md")), { "SOLID" })
lib.use(entry("principle", "testing"))
eq(
  "library use: another principle kept with the first",
  compose.principles_in(read(libroot .. "/STACK.md")),
  { "SOLID", "Testing" }
)
vim.cmd "enew"
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "before", "after" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
lib.embed(entry("principle", "solid"), vim.api.nvim_get_current_win())
eq("library embed: under the cursor", vim.api.nvim_buf_get_lines(0, 0, 2, false), { "before", "### SOLID" })
vim.cmd "bwipeout!"

-- menu: keys and the Service level moved to aU
local menu = require "menus.agent_setup"
eq("menu: prefix", menu.prefix, "aS")
eq(
  "menu: keys",
  vim.tbl_map(function(m)
    return m[1]
  end, menu.maps),
  { "b", "B", "/", "o", "a", "A", "c", "t", "T", "k", "p", "d", "D", "s" }
)
eq("menu: Service lives on aU now", require("menus.agent_service").prefix, "aU")

vim.fn.delete(base, "rf")
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd "qa!"
