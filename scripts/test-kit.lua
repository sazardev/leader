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
for _, sec in ipairs(compose.doc("design").optional) do
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
eq("commands: flutter app", labels(snapshot.commands { files = { "pubspec.yaml", "lib/main.dart" } }), {
  "install=flutter pub get",
  "test=flutter test",
  "lint=flutter analyze",
  "format=dart format .",
  "run=flutter run",
})
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
  { "go.mod", "later.go", "main.go" }
)
eq("build plan: unknown docs dropped", parsed.files[3].docs, { "spec" })
eq("build plan: needs kept even when later", parsed.files[3].needs, { "go.mod", "later.go" })
eq("build plan: no JSON", select(2, bplan.parse "sorry"), "the answer has no JSON object")
-- the plan while it is written: what is complete so far, nothing half-read
local whole =
  '{"name":"calc","summary":"A \\"TUI\\" calculator.","architecture":"domain <- ui","decisions":["Bubble Tea","sentinel errors"],"files":[{"path":"go.mod","purpose":"module","exports":[],"docs":["stack"]},{"path":"keypad.go","purpose":"the keypad","exports":["NewKeypad() — starts on ="],"needs":["go.mod"]}]}'
local cut = bplan.partial(whole:sub(1, whole:find "Bubble Tea" + 12))
eq(
  "partial: complete strings only (escaped quotes kept)",
  { cut.summary, cut.architecture, cut.decisions, #cut.files },
  { 'A "TUI" calculator.', "domain <- ui", { "Bubble Tea" }, 0 }
)
local mid = bplan.partial(whole:sub(1, whole:find '"keypad.go"' + 14))
eq(
  "partial: a file whose path arrived, its purpose not yet",
  { #mid.files, mid.files[2].path, mid.files[2].purpose },
  { 2, "keypad.go", "" }
)
local all = bplan.partial(whole)
eq(
  "partial: the whole JSON = every file with its contract",
  { #all.files, all.files[2].exports, all.files[2].needs },
  { 2, { "NewKeypad() — starts on =" }, { "go.mod" } }
)
eq("partial: nothing yet", #bplan.partial("").files, 0)
local thinking = {}
local cparser = require("agent.backends.claude").parser {
  on_think = function(d)
    thinking[#thinking + 1] = d
  end,
}
local streamed = cparser.feed(
  '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hmm"}}}\n'
    .. '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"{"}}}\n'
)
eq("claude parser: thinking goes to on_think, text is returned", { thinking, streamed }, { { "hmm" }, "{" })
local rich =
  bplan.parse '{"name":"calc","summary":"A TUI calculator.","architecture":"domain <- ui <- cmd","decisions":["Bubble Tea"],"files":[{"path":"keypad.go","purpose":"the keypad","exports":["NewKeypad() Keypad — the highlight starts on ="],"docs":["design"]},{"path":"app_test.go","purpose":"tests","verifies":"FR-3 Enter evaluates","needs":["keypad.go"]}]}'
eq(
  "build plan: summary, architecture, decisions",
  { rich.summary, rich.architecture, rich.decisions },
  { "A TUI calculator.", "domain <- ui <- cmd", { "Bubble Tea" } }
)
eq(
  "build plan: what a file exports and promises",
  rich.files[1].exports,
  { "NewKeypad() Keypad — the highlight starts on =" }
)
eq("build plan: what a test verifies", rich.files[2].verifies, "FR-3 Enter evaluates")
local rich_system = bprompt.system(rich, { spec = "S" })
ok(
  "build plan: every file request carries the contract",
  rich_system:find("exports NewKeypad() Keypad — the highlight starts on =", 1, true)
    and rich_system:find("Architecture: domain <- ui <- cmd", 1, true)
    and rich_system:find("verifies FR-3", 1, true)
)
local rich_md = require("agent.kit.build").plan_text(rich)
ok(
  "build plan.md: how it works, architecture, decisions, files by folder",
  rich_md:find("## How it works", 1, true)
    and rich_md:find("## Architecture", 1, true)
    and rich_md:find("## Decisions", 1, true)
    and rich_md:find("`NewKeypad() Keypad — the highlight starts on =`", 1, true)
)
eq("build content: fence removed", bprompt.content "```go\npackage main\n```\n", "package main\n")
eq("build content: plain kept", bprompt.content "package main\n\n", "package main\n")
local freq = bprompt.file(
  parsed.files[3],
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
  "build blame: TypeScript's file(line,col)",
  bverify.blame("src/main.ts(12,5): error TS2304: Cannot find name 'x'.\n", { "src/main.ts" }),
  { ["src/main.ts"] = { "src/main.ts(12,5): error TS2304: Cannot find name 'x'." } }
)
eq(
  "build blame: go test's package-relative names, mapped through the package line and the module",
  bverify.blame(
    '--- FAIL: TestLayout (0.05s)\n    app_test.go:46: keypad label "C" is not visible\nFAIL\nFAIL\tascii-calc/internal/ui\t0.05s\n--- FAIL: TestEval (0.00s)\n    calculator_test.go:39: unexpected\nFAIL\tascii-calc/internal/domain\t0.01s\n',
    { "internal/ui/app_test.go", "internal/domain/calculator_test.go", "internal/other/app_test.go" },
    "ascii-calc"
  ),
  {
    ["internal/ui/app_test.go"] = { '    app_test.go:46: keypad label "C" is not visible' },
    ["internal/domain/calculator_test.go"] = { "    calculator_test.go:39: unexpected" },
  }
)
eq(
  "build tests: test files by language",
  vim.tbl_map(bverify.is_test, {
    "internal/ui/app_test.go",
    "src/a.test.ts",
    "src/b.spec.tsx",
    "tests/x.rs",
    "test_api.py",
    "pkg/api_test.py",
    "src/main.ts",
    "app.go",
  }),
  { true, true, true, true, true, true, false, false }
)
local tplan = {
  name = "t",
  files = {
    { path = "calc.go", purpose = "c", docs = { "spec" }, needs = {} },
    { path = "calc_test.go", purpose = "t", docs = { "spec" }, needs = { "calc.go" } },
  },
}
ok(
  "build fix of a test: never weaken it",
  bprompt
    .fix("calc_test.go", "package x", "--- FAIL", tplan.files[2], tplan, { spec = "S" }, {}, "test").prompt
    :find("Never delete or weaken assertions", 1, true)
)
ok(
  "build fix of the code a test exercises: fix it or leave it as it is",
  bprompt
    .fix("calc.go", "package x", "--- FAIL", tplan.files[1], tplan, { spec = "S" }, {}, "subject").prompt
    :find("otherwise this file is right as it is", 1, true)
)
eq(
  "build pm hint: from STACK.md's row",
  bverify.package_manager_hint "x\n| Package manager | Bun (`bun install`) | fast |\n",
  "bun"
)
eq("build pm hint: none", bverify.package_manager_hint "no table", nil)
eq("build manifest: the planned one", bverify.manifest_of { "src/a.ts", "package.json" }, "package.json")
eq(
  "build tools: what STACK.md names and package.json lacks",
  bverify.missing_tools(
    "x\n## Stack\n\n| Layer | Choice | Why |\n| --- | --- | --- |\n| Build | Vite 8 (Rolldown) | fast |\n| Tests | Vitest | ok |\n| Lint | Biome 2 | one tool |\n\n## Project layout\n",
    '{"devDependencies":{"vitest":"^3"}}'
  ),
  { "@biomejs/biome", "vite" }
)
eq(
  "build tools: nothing missing",
  bverify.missing_tools("\n## Stack\n| Tests | Vitest | x |\n## X\n", '{"devDependencies":{"vitest":"^3"}}'),
  {}
)
eq(
  "build DOM: ids the code looks up that the HTML lacks",
  bverify.missing_ids {
    ["index.html"] = '<main id="app"><button id="start">go</button></main>',
    ["src/main.ts"] = 'const a = document.getElementById("app")\nconst b = document.querySelector("#open-settings")\nconst c = document.getElementById(\'start\')',
    ["src/main.test.ts"] = 'document.getElementById("only-in-tests")',
  },
  { 'index.html:1: no element with id "open-settings" (src/main.ts:2 looks for it)' }
)
eq(
  "build DOM: an id kept in a constant",
  bverify.missing_ids {
    ["index.html"] = '<main id="app"></main>',
    ["src/main.ts"] = 'const OPEN_SETTINGS_ID = "open-settings";\nconst rootId = "app";\nconst element = document.getElementById(id);',
  },
  { 'index.html:1: no element with id "open-settings" (src/main.ts:1 looks for it)' }
)
ok(
  "build api: the HTML's ids are part of the API",
  bprompt.api({ ["index.html"] = '<div id="timer"></div><button id="start">' }, "x"):find("#timer", 1, true)
)
eq(
  "build orphans: a stylesheet nothing loads, blamed on the page",
  bverify.orphans {
    ["index.html"] = '<link rel="stylesheet" href="/src/styles/tokens.css"><script type="module" src="/src/main.ts"></script>',
    ["src/main.ts"] = 'import { start } from "./features/timer/timer.view";',
    ["src/features/timer/timer.view.ts"] = "export function start() {}",
    ["src/styles/tokens.css"] = ":root {}",
    ["src/styles/base.css"] = "body {}",
    ["src/main.test.ts"] = "",
    ["vite.config.ts"] = "",
  },
  { "index.html:1: src/styles/base.css is never linked or imported (load it from the page or its entry script)" }
)
local golden_only =
  "?   \tascii-calc/cmd/app\t[no test files]\n--- FAIL: TestLayout (0.05s)\n    golden.go:22: open testdata/TestLayout.golden: no such file or directory\n--- FAIL: TestHistory (0.05s)\n    golden.go:22: open testdata/TestHistory.golden: no such file or directory\nFAIL\nFAIL\tascii-calc/internal/ui\t0.051s\nFAIL"
eq(
  "build golden: only those tests, only those packages, with -update (Go's real output)",
  bverify.golden_update(golden_only),
  { "go", "test", "ascii-calc/internal/ui", "-run", "^(TestHistory|TestLayout)$", "-update" }
)
eq(
  "build golden: another test failing too = no snapshot (it would lock the bug in)",
  bverify.golden_update(
    golden_only:gsub(
      "FAIL\nFAIL\t",
      "--- FAIL: TestKeypad (0.01s)\n    app_test.go:46: keypad not visible\nFAIL\nFAIL\t",
      1
    )
  ),
  nil
)
eq(
  "build golden: not about golden files = no command",
  bverify.golden_update "--- FAIL: TestA\nFAIL\tx/ui\t0.1s\n",
  nil
)
local bmod = require "agent.kit.build"
eq(
  "build progress: the same failure, other timings = the same signature",
  bmod.signature("go test", "--- FAIL: TestA (0.05s)\nFAIL\tx\t0.05s"),
  bmod.signature("go test", "--- FAIL: TestA (0.07s)\nFAIL\tx\t0.09s")
)
ok(
  "build progress: another failing test = progress",
  bmod.signature("go test", "--- FAIL: TestA (0.05s)") ~= bmod.signature("go test", "--- FAIL: TestB (0.05s)")
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
  if r.action == "kit_build_plan" and r.on_think and #asked == 1 then
    local code = vim.fn.bufnr "build://code"
    r.on_think "The spec asks for a keypad."
    asked.thinking = vim.api.nvim_buf_get_lines(code, 0, -1, false)
    r.on_text '{"name":"t","files":[{"path":"src/a.txt","purpose":"a"'
    asked.planning = vim.api.nvim_buf_get_lines(code, 0, 1, false)[1]
  end
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
eq(
  "build: Enter plans, then waits on the review",
  { bstate.run.phase, asked[1], #asked },
  { "review", "kit_build_plan", 1 }
)
eq("plan live: the thinking shows before the plan", { asked.thinking[1]:match "^> thinking", asked.thinking[3] }, {
  "> thinking",
  "The spec asks for a keypad.",
})
ok("plan live: then the plan as it arrives", asked.planning:find("> planning · 1 file so far", 1, true))
asked.thinking, asked.planning = nil, nil
ok("build: the review has an estimate per file", bstate.run.files[1].estimate and bstate.run.estimate.tokens > 0)
-- the view: the plan is markdown and stays so across toggles; z focuses it; l hides the list; Tab moves between panes
local function code_ft()
  return vim.bo[vim.fn.bufnr "build://code"].filetype
end
local function feed_key(k)
  vim.api.nvim_feedkeys(vim.keycode(k), "x", false)
end
eq("view: the plan shows as markdown", code_ft(), "markdown")
feed_key "c"
feed_key "c"
eq("view: c twice keeps it markdown", code_ft(), "markdown")
feed_key "z"
eq(
  "view: z = the code pane alone, the cursor in it",
  { #vim.api.nvim_tabpage_list_wins(0), vim.api.nvim_buf_get_name(0):match "build://(%w+)" },
  { 1, "code" }
)
feed_key "z"
eq("view: z again = the panes back", #vim.api.nvim_tabpage_list_wins(0), 3)
feed_key "l"
eq("view: l hides the list", vim.fn.bufwinnr "build://files", -1)
feed_key "l"
local before_win = vim.api.nvim_get_current_win()
feed_key "<Tab>"
ok("view: Tab moves to another pane", vim.api.nvim_get_current_win() ~= before_win)
build.toggle_skip "README.md"
eq("build: x skips a file", bstate.run.files[2].state, "skipped")
build.toggle_skip "README.md"
build.cycle "files"
eq("build: 2 switches the files' tier", bstate.run.tiers.files, "light")
build.go()
eq(
  "build: an Enter right as the review appears does not build (typed ahead, pressed twice)",
  bstate.run.phase,
  "review"
)
build.show_plan()
eq(
  "build: P shows the plan in the code pane",
  vim.api.nvim_buf_get_lines(vim.fn.bufnr "build://code", 0, 1, false)[1],
  "# Plan · t"
)
vim.wait(1600)
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
local bview = require "agent.kit.build.view"
vim.o.columns = 200
ok(
  "build statusline: wide = every figure, % escaped for the statusline",
  bview.status_figures():find("%% cached", 1, true)
)
vim.o.columns = 60
ok(
  "build statusline: narrow = the short figures",
  not bview.status_figures():find("cached", 1, true) and bview.status_figures():find("$", 1, true)
)
ok("build statusline: narrow = fewer keys", #bview.status_keys() < 60)
vim.o.columns = 80
ok(
  "build statusline: the phase and the keys of the moment",
  bview.status_phase() == "done"
    and bview.status_color() == "KitBuildStateOk"
    and bview.status_keys():find("r recheck", 1, true)
)

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
vim.wait(1600) -- past the review guard
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
-- n: a new plan right away (no Enter), said in the feed; X: the build's files to the trash, the run forgotten
build.restart()
ok("replan: plans right away", bstate.run.phase == "review")
ok(
  "replan: said in the feed",
  vim.iter(bstate.run.feed):any(function(e)
    return e.title == "Replan"
  end)
)
build.clean()
eq(
  "clean: the files the build wrote are in the trash",
  { read(broot .. "/one.txt"), read(broot .. "/two.txt") },
  { nil, nil }
)
ok("clean: the documents stay", read(broot .. "/AGENTS.md") ~= nil and read(broot .. "/SPEC.md") ~= nil)
eq("clean: the saved run is forgotten", bstate.load(broot), nil)
eq("clean: back to the pre-flight", bstate.run.phase, "ready")
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
  kinds.stack and kinds.design and kinds["stack add-on"] and kinds["design add-on"] and kinds.principle and kinds.recipe
)
eq(
  "library: as many as the folders hold",
  #all,
  #presets.all "stack"
    + #presets.all "design"
    + kinds["stack add-on"]
    + kinds["design add-on"]
    + #principles
    + #require("agent.kit.recipes").all()
)
local libroot = project("library", {
  ["STACK.md"] = "# STACK.md: x\n\n## Stack\n\n| Layer | Choice | Why |\n| --- | --- | --- |\n| Language | Go | x |\n\n## Rules for agents\n\n- r\n",
})
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

-- fixes: the API carries what a declaration promises; diagnose before fixing; a fix that weakens a test is refused
local api = bprompt.api({
  ["keypad.go"] = 'package c\n\n// NewKeypad builds the keypad.\n// The highlight opens on "=".\nfunc NewKeypad() Keypad {\n}\n\nfunc helper() {}\n',
}, "x")
ok(
  "api: the doc comment above a declaration",
  api:find('// NewKeypad builds the keypad. The highlight opens on "=".\n  func NewKeypad() Keypad', 1, true)
)
ok("api: no comment, no line", not api:find "//%s*\n  func helper")
local bdiag = require "agent.kit.build.diagnose"
local dplan = {
  name = "t",
  files = {
    { path = "calc.go", purpose = "c", docs = { "spec" }, needs = {} },
    { path = "calc_test.go", purpose = "t", docs = { "spec" }, needs = { "calc.go" } },
  },
}
local dreq = bdiag.request(
  "calc_test.go:10: want 11",
  { ["calc_test.go"] = { "calc_test.go:10: want 11" } },
  dplan,
  { spec = "S" },
  { ["calc.go"] = "package c\nfunc Add() {}", ["calc_test.go"] = "package c\n" }
)
ok(
  "diagnose request: the output, the test and the code it uses",
  dreq.prompt:find("<output>", 1, true)
    and dreq.prompt:find('<file path="calc.go">', 1, true)
    and dreq.prompt:find('<file path="calc_test.go">', 1, true)
)
eq("diagnose request: the same cached system prompt as the files", dreq.system, bprompt.system(dplan, { spec = "S" }))
local parsed_diag = bdiag.parse(
  '{"diagnosis":"d","files":[{"path":"calc.go","change":"x"},{"path":"/etc/passwd","change":"y"}]}',
  { "calc.go", "calc_test.go" }
)
eq("diagnose parse: only planned paths", parsed_diag and #parsed_diag.files, 1)
eq("diagnose parse: nothing usable", bdiag.parse("sorry", { "calc.go" }), nil)
ok("weakened: a removed assertion", bverify.weakened('t.Errorf("a")\nt.Fatal("b")', 't.Errorf("a")'))
ok("weakened: a new skip", bverify.weakened('t.Errorf("a")', 't.Skip("later")\nt.Errorf("a")'))
eq("weakened: same strength", bverify.weakened('t.Errorf("a")', 'x := 1\nt.Errorf("a")'), nil)

-- the whole fix flow with a fake model and a fake check
local froot = project(
  "fixflow",
  { ["AGENTS.md"] = "# A\n", ["STACK.md"] = "# S\n", ["SPEC.md"] = "# P\n", ["DESIGN.md"] = "# D\n" }
)
vim.system({ "git", "init", "-q" }, { cwd = froot }):wait()
local real_checks = bverify.checks
bverify.checks = function()
  return {
    {
      label = "fake test",
      fn = function()
        local code = read(froot .. "/calc.go") or ""
        if code:find("fixed", 1, true) then
          return true, ""
        end
        return false, "calc_test.go:10: Enter evaluated nothing"
      end,
    },
  }
end
local fasked = {}
package.loaded["agent"].complete = function(r, cb)
  fasked[#fasked + 1] = r.action
  local answers = {
    kit_build_plan = '{"name":"t","files":[{"path":"calc.go","purpose":"c"},{"path":"calc_test.go","purpose":"t","needs":["calc.go"]}]}',
    kit_build_diagnose = '{"diagnosis":"the keypad opens on 7","files":[{"path":"calc.go","change":"open on ="},{"path":"calc_test.go","change":"relax it"}]}',
  }
  local text = answers[r.action]
  if not text then
    local path = r.prompt:match "Write `([^`]+)`"
      or r.prompt:match "Fix `([^`]+)`"
      or r.prompt:match "exercises `([^`]+)`"
      or r.prompt:match "`([^`]+)` is a test"
    if r.action == "kit_build_file" then
      text = path == "calc_test.go" and 'package c\nfunc TestX(t *testing.T) { t.Errorf("x") }' or "package c"
    elseif path == "calc.go" then
      text = "package c // fixed"
    else
      text = "package c\nfunc TestX(t *testing.T) {}" -- the weakening the guard must refuse
    end
  end
  cb(true, text, { tokens_in = 10, tokens_out = 2 })
  return { kill = function() end }
end
vim.cmd "silent! tabonly"
vim.cmd.edit(vim.fn.fnameescape(froot .. "/AGENTS.md"))
bstate.run = nil
build.open()
build.go()
vim.wait(1600) -- past the review guard
build.go()
vim.wait(2000, function()
  return bstate.run.phase == "done" or bstate.run.phase == "failed"
end)
bverify.checks = real_checks
ok("fix flow: diagnosed before fixing", vim.tbl_contains(fasked, "kit_build_diagnose"))
eq("fix flow: the code the diagnosis named was fixed", read(froot .. "/calc.go"), "package c // fixed\n")
ok(
  "fix flow: the weakened test was refused (it keeps its assertion)",
  (read(froot .. "/calc_test.go") or ""):find("t.Errorf", 1, true)
)
ok(
  "fix flow: the refusal is in the feed",
  vim.iter(bstate.run.feed):any(function(e)
    return e.text:find("fix refused", 1, true) ~= nil
  end)
)
eq("fix flow: then the check passes", bstate.run.phase, "done")
vim.cmd "silent! tabonly"

-- design: toolkit add-ons follow the project's STACK.md; Screens merged into DESIGN.md; the look at rendered screens
do
  local kit_presets = require "agent.kit.presets"
  local ascii = vim.iter(kit_presets.all "design"):find(function(p)
    return p.id == "ascii-art"
  end)
  local function toolkit_pick(stack, preset, category)
    local tags = kit_presets.with_stack(kit_presets.design_tags(preset, category), stack)
    local addons = kit_presets.addons(tags, nil, "design")
    local out = {}
    for a in pairs(kit_presets.preselect(addons, tags, preset.id, category)) do
      if a.axis == "toolkit" then
        out[#out + 1] = a.id
      end
    end
    local offered = vim.tbl_map(
      function(a)
        return a.id
      end,
      vim.tbl_filter(function(a)
        return a.axis == "toolkit"
      end, addons)
    )
    table.sort(offered)
    return out, offered
  end
  local go_stack =
    "# S\n## Summary\nA terminal app.\n## Stack\n| Layer | Choice | Why |\n| --- | --- | --- |\n| Language | Go 1.25 | x |\n## Project layout\n"
  local picked, offered = toolkit_pick(go_stack, ascii, "terminal")
  eq("toolkit: a Go STACK.md checks Charm for a terminal design", picked, { "charm" })
  eq("toolkit: a terminal design offers only terminal toolkits", offered, { "charm", "ink", "ratatui", "textual" })
  eq(
    "toolkit: Rust → Ratatui",
    (toolkit_pick(go_stack:gsub("Go 1.25", "Rust 1.90"), ascii, "terminal")),
    { "ratatui" }
  )
  eq(
    "toolkit: Python → Textual",
    (toolkit_pick(go_stack:gsub("Go 1.25", "Python 3.13"), ascii, "terminal")),
    { "textual" }
  )
  eq("toolkit: no STACK.md, nothing checked", (toolkit_pick(nil, ascii, "terminal")), {})
  local linear = vim.iter(kit_presets.all "design"):find(function(p)
    return p.category ~= "terminal"
  end)
  local web =
    "# S\n## Summary\nA React app with Tailwind.\n## Stack\n| Layer | Choice | Why |\n| --- | --- | --- |\n| Language | TypeScript 7 | x |\n## Project layout\n"
  eq("toolkit: a Tailwind stack checks Tailwind", (toolkit_pick(web, linear, linear.category)), { "tailwind" })
  eq(
    "toolkit: React without Tailwind → CSS variables",
    (toolkit_pick(web:gsub(" with Tailwind", ""), linear, linear.category)),
    { "css-variables" }
  )
  eq(
    "toolkit: a terminal stack's `tui` never makes a GUI design offer terminal toolkits",
    vim.tbl_contains(select(2, toolkit_pick(go_stack, linear, linear.category)), "charm"),
    false
  )

  -- Screens: inserted before "Rules for agents", replaced in place, a fenced answer unwrapped
  local d = "# DESIGN.md: X\n\n## Components\n\n- a\n\n## Rules for agents\n\n- r\n"
  local with = compose.set_screens(d, "## Screens\n\n### Main\n\n```\n[ 7 ]\n```\n")
  eq(
    "screens: before the rules",
    with,
    "# DESIGN.md: X\n\n## Components\n\n- a\n\n## Screens\n\n### Main\n\n```\n[ 7 ]\n```\n\n## Rules for agents\n\n- r\n"
  )
  eq(
    "screens: replaced, not added twice",
    compose.set_screens(with, "### Main\n\n```\n[ = ]\n```"),
    "# DESIGN.md: X\n\n## Components\n\n- a\n\n## Screens\n\n### Main\n\n```\n[ = ]\n```\n\n## Rules for agents\n\n- r\n"
  )
  eq(
    "screens: at the end when there are no rules",
    compose.set_screens("# D\n\n## Color\n\n- c\n", "### A"),
    "# D\n\n## Color\n\n- c\n\n## Screens\n\n### A\n"
  )
  local kit = require "agent.kit"
  eq(
    "screens: chatter before the heading dropped",
    kit.screens_of "Sure!\n\n## Screens\n\n### A\n",
    "## Screens\n\n### A"
  )
  eq(
    "screens: a fence around the answer dropped",
    kit.screens_of "```markdown\n## Screens\n\n### A\n```",
    "## Screens\n\n### A"
  )
  eq("screens: a ### Screens heading is not the section", kit.screens_of "### Screens\n", nil)
  local sreq = require("agent.kit.prompts").screens("# SPEC", "# DESIGN", "## Summary\nA TUI.\n## Stack\n")
  ok(
    "screens: the request carries SPEC, DESIGN and the stack's summary",
    sreq.prompt:find("<spec>", 1, true)
      and sreq.prompt:find("<design>", 1, true)
      and sreq.prompt:find("A TUI.", 1, true)
  )
  ok("screens: answers a section, not a file", sreq.system:find("`## ` heading", 1, true) ~= nil)

  -- look: control sequences out, golden files found, tests never fixed
  local look = require "agent.kit.build.look"
  eq(
    "look: CSI/OSC/modes stripped, blank rows around trimmed",
    look.clean "\27[?25l\27[?2004h   \n\27[1;35m 7 \27[0m  \n  \n\27]0;title\7\27[2K\27[?25h",
    " 7"
  )
  local lroot = project("look", { ["internal/ui/testdata/TestA.golden"] = "\27[1m[ 7 ]\27[0m\n", ["x.golden"] = "no" })
  local renders = look.renders(lroot)
  eq(
    "look: the testdata golden files, as shown",
    renders,
    { { path = "internal/ui/testdata/TestA.golden", text = "[ 7 ]" } }
  )
  eq(
    "look: tests and goldens are never the fix",
    look.parse(
      '{"diagnosis":"not centered","files":[{"path":"ui.go","change":"Place"},{"path":"ui_test.go","change":"x"}]}',
      { "ui.go", "ui_test.go" }
    ).files,
    { { path = "ui.go", change = "Place" } }
  )
  eq("look: files [] = the screens match", look.parse('{"diagnosis":"matches","files":[]}', { "ui.go" }), nil)

  -- look flow: checks pass → a look → the named file fixed → the golden written again → a second look confirms → done
  local groot = project(
    "lookflow",
    { ["AGENTS.md"] = "# A\n", ["STACK.md"] = "# S\n", ["SPEC.md"] = "# P\n", ["DESIGN.md"] = "# D\n" }
  )
  vim.system({ "git", "init", "-q" }, { cwd = groot }):wait()
  local golden = groot .. "/testdata/TestMain.golden"
  local saved_checks = bverify.checks
  bverify.checks = function()
    return {
      {
        label = "fake test",
        fn = function() -- like `go test -update` on a missing golden: the screen as the code draws it now
          if not vim.uv.fs_stat(golden) then
            write(golden, (read(groot .. "/ui.go") or ""):find("centered", 1, true) and "   [ 7 ]\n" or "[ 7 ]\n")
          end
          return true, ""
        end,
      },
    }
  end
  local lasked = {}
  package.loaded["agent"].complete = function(r, cb)
    lasked[#lasked + 1] = r.action
    local answers = {
      kit_build_plan = '{"name":"t","files":[{"path":"ui.go","purpose":"the screen"}]}',
      kit_build_look = '{"diagnosis":"the keypad is not centered","files":[{"path":"ui.go","change":"lipgloss.Place it"}]}',
    }
    local text = answers[r.action] or (r.action == "kit_build_file" and "package ui" or "package ui // centered")
    if r.action == "kit_build_look" then
      lasked.renders = lasked.renders or {}
      table.insert(lasked.renders, r.prompt:match '<render path="testdata/TestMain.golden">\n(.-)\n</render>')
      if #lasked.renders > 1 then
        text = '{"diagnosis":"matches","files":[]}'
      end
    end
    cb(true, text, { tokens_in = 10, tokens_out = 2 })
    return { kill = function() end }
  end
  vim.cmd "silent! tabonly"
  vim.cmd.edit(vim.fn.fnameescape(groot .. "/AGENTS.md"))
  bstate.run = nil
  build.open()
  build.go()
  vim.wait(1600)
  build.go()
  vim.wait(3000, function()
    return bstate.run.phase == "done" or bstate.run.phase == "failed"
  end)
  bverify.checks = saved_checks
  eq(
    "look flow: a look after the checks pass, another after its fix",
    vim.tbl_filter(function(a)
      return a == "kit_build_look"
    end, lasked),
    { "kit_build_look", "kit_build_look" }
  )
  eq("look flow: the model saw the screen, then the fixed one", lasked.renders, { "[ 7 ]", "   [ 7 ]" })
  eq("look flow: the file it named was fixed", read(groot .. "/ui.go"), "package ui // centered\n")
  eq("look flow: the golden written again from the fixed code", read(golden), "   [ 7 ]\n")
  eq("look flow: done, looked twice", { bstate.run.phase, bstate.run.looked, bstate.run.looks }, { "done", true, 2 })
  build.recheck()
  vim.wait(1000, function()
    return not bstate.run.running
  end)
  eq("look flow: a recheck does not look again (0 tokens)", #vim.tbl_filter(function(a)
    return a == "kit_build_look"
  end, lasked), 2)
  vim.cmd "silent! tabonly"
end

-- menu: keys and the Service level moved to aU
local menu = require "menus.agent_setup"
eq("menu: prefix", menu.prefix, "aS")
eq(
  "menu: keys",
  vim.tbl_map(function(m)
    return m[1]
  end, menu.maps),
  { "bb", "bt", "bs", "bd", "bf", "r", "v", "P", "B", "/", "o", "a", "A", "c", "t", "T", "k", "p", "d", "D", "w", "s" }
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
