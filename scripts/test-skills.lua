-- Tests of agent skills (nvim/lua/skills, <leader>aK): frontmatter parsing, inference
-- (0-config suggestions per model/stack), discovery + CRUD on disk, matching and
-- the marketplace UI (windows, keys, back navigation). No network.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-skills.lua"
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
    notes[#notes + 1] = m
  end,
  warn = function(m)
    notes[#notes + 1] = m
  end,
  error = function(m)
    notes[#notes + 1] = m
  end,
}

local parse = require "skills.parse"
local infer = require "skills.infer"
local store = require "skills.store"

-- ── parse ────────────────────────────────────────────────────────────────────
local caveman = [[
---
name: caveman
description: >
  Ultra-compressed communication mode. Cuts token usage ~75% by speaking like caveman.
  Use when user says "caveman mode" or "be brief".
---

Respond terse like smart caveman.
]]
local p = parse.parse(caveman, "caveman")
eq("parse: id from frontmatter", p.id, "caveman")
ok("parse: description folds lines", p.description:find("Ultra-compressed", 1, true) ~= nil)
ok("parse: body without frontmatter", p.body:find("Respond terse", 1, true) ~= nil)
eq("parse: valid", p.valid, true)
eq("parse: autoinvoke on by default", p.autoinvoke, true)

local off = parse.parse("---\nname: x\ndescription: >\n  dormant\nmetadata:\n  opencode/autoinvoke: false\n---\nbody\n", "x")
eq("parse: autoinvoke off", off.autoinvoke, false)

local nod = parse.parse("---\nname: x\n---\nbody\n", "x")
eq("parse: missing description is invalid", nod.valid, false)
ok("parse: error names the trigger", nod.errors[1]:find("description", 1, true) ~= nil)

eq("validate: missing body", #parse.validate({ id = "x", description = "d" }) > 0, true)
eq("validate: bad id", #parse.validate({ id = "a b", description = "d", body = "b" }) > 0, true)
local rendered = parse.render("my-skill", "Do a thing when asked", "## Workflow\n1. Do it.")
local round = parse.parse(rendered, "my-skill")
eq("render+parse roundtrip: id", round.id, "my-skill")
ok("render+parse roundtrip: desc", round.description:find("Do a thing", 1, true) ~= nil)
ok("render+parse roundtrip: body", round.body:find("Do it", 1, true) ~= nil)

-- ── infer ────────────────────────────────────────────────────────────────────
eq("languages: go", infer.languages({ "go.mod" }), { "go" })
eq("languages: dart+ts", infer.languages({ "pubspec.yaml", "package.json" }), { "dart", "typescript" })
eq("languages: none", infer.languages({ "README.md" }), {})
eq("languages: csharp via .sln", infer.languages({ "MyApp.sln" }), { "dotnet" })
eq("languages: csharp via .csproj", infer.languages({ "MyApp.csproj" }), { "dotnet" })
eq("languages: cloudflare", infer.languages({ "wrangler.toml" }), { "cloudflare" })
eq("languages: docker", infer.languages({ "Dockerfile" }), { "docker" })
eq("languages: terraform via .tf", infer.languages({ "main.tf" }), { "terraform" })
eq("languages: stack+env deduped", infer.languages({ "go.mod", "Dockerfile", "go.mod" }), { "go", "docker" })

local small = infer.suggest({ class = "small", markers = { "go.mod" }, installed = {}, enabled = {}, auto = true })
local small_ids = {}
for _, s in ipairs(small) do
  small_ids[s.id] = s.action
end
eq("infer small: caveman install", small_ids.caveman, "install")
eq("infer small: go-pro install (stack)", small_ids["go-pro"], "install")

local strong = infer.suggest({ class = "strong", markers = { "go.mod" }, installed = {}, enabled = {}, auto = true })
local strong_ids = {}
for _, s in ipairs(strong) do
  strong_ids[s.id] = true
end
eq("infer strong: no caveman (saves nothing on strong)", strong_ids.caveman, nil)
eq("infer strong: still stack", strong_ids["go-pro"], true)

local dotnet = infer.suggest({ class = "strong", markers = { "MyApp.sln" }, installed = {}, enabled = {}, auto = true })
local dotnet_ids = {}
for _, s in ipairs(dotnet) do
  dotnet_ids[s.id] = true
end
eq("infer dotnet: dotnet-pro", dotnet_ids["dotnet-pro"], true)

local cloud = infer.suggest({ class = "strong", markers = { "wrangler.toml", "Dockerfile" }, installed = {}, enabled = {}, auto = true })
local cloud_ids = {}
for _, s in ipairs(cloud) do
  cloud_ids[s.id] = true
end
eq("infer cloudflare+docker: cloudflare-expert", cloud_ids["cloudflare-expert"], true)
eq("infer cloudflare+docker: docker-pro", cloud_ids["docker-pro"], true)
eq("infer cloudflare+docker: devops-engineer", cloud_ids["devops-engineer"], true)

local installed = infer.suggest({
  class = "small",
  markers = {},
  installed = { caveman = true },
  enabled = { caveman = true },
  auto = true,
})
eq("infer: installed+enabled is keep", installed[1].action, "keep")

local asleep = infer.suggest({
  class = "small",
  markers = {},
  installed = { caveman = true },
  enabled = {},
  auto = true,
})
eq("infer: installed but dormant is enable", asleep[1].action, "enable")

local opted = infer.suggest({ class = "small", markers = {}, installed = {}, enabled = {}, disabled = { caveman = true }, auto = true })
for _, s in ipairs(opted) do
  ok("infer: disabled never appears", s.id ~= "caveman")
end
eq("infer: auto=false suggests nothing", #infer.suggest({ class = "small", markers = { "go.mod" }, auto = false }), 0)

ok("score: caveman wins on 'be brief'", infer.score({ id = "caveman", description = "be brief caveman mode" }, " be brief caveman mode ") > 0)

-- ── store: discovery + CRUD on a temp root ───────────────────────────────────
local base = vim.fn.tempname()
vim.fn.mkdir(base .. "/demo", "p")
local demo = base .. "/demo"
vim.system({ "git", "init", "-q" }, { cwd = demo }):wait()
local skill_text = "---\nname: demo-skill\ndescription: >\n  Does a demo thing when asked\n---\n\n## Workflow\n\nDo the thing.\n"
vim.fn.mkdir(demo .. "/.agents/skills/demo-skill", "p")
local f = assert(io.open(demo .. "/.agents/skills/demo-skill/SKILL.md", "w"))
f:write(skill_text)
f:close()
vim.fn.mkdir(demo .. "/.agents/skills", "p")
local f2 = assert(io.open(demo .. "/.agents/skills/flat.md", "w"))
f2:write("---\nname: flat\ndescription: >\n  flat skill\n---\n\nflat body\n")
f2:close()

local list = store.list({ root = demo .. "/.agents/skills" })
eq("store: 2 skills found (dir + flat)", #list, 2)
local demo_skill = store.get("demo-skill", { root = demo .. "/.agents/skills" })
ok("store: demo resolved", demo_skill ~= nil)
eq("store: on by default", demo_skill.autoinvoke, true)

local ok_on, err_on = store.set_enabled(demo_skill, false)
ok("store: toggle off writes", ok_on == true)
local after = store.get("demo-skill", { root = demo .. "/.agents/skills" })
eq("store: now dormant", after.autoinvoke, false)
local reread = assert(io.open(demo_skill.path, "r")):read "*a"
ok("store: frontmatter kept autoinvoke off", reread:find("autoinvoke: false", 1, true) ~= nil)

local created, create_err = store.create("new-skill", "New trigger line", "New body", {
  root = demo .. "/.agents/skills",
  lock_path = demo .. "/skills-lock.json",
})
ok("store: create in temp root", created ~= nil)
eq("store: created parses", store.get("new-skill", { root = demo .. "/.agents/skills" }).id, "new-skill")
eq("store: duplicate refused", store.create("new-skill", "again", "again", { root = demo .. "/.agents/skills", lock_path = demo .. "/skills-lock.json" }) == nil, true)

-- ── adopt (tolerance: legacy / already-worked) ──────────────────────────────
local adopt = require "skills.adopt"
local worked = adopt.analyze {
  files = { "AGENTS.md", "STACK.md", "DESIGN.md", "README.md", "main.py", "legacy.py", "old.php", "a.txt", "b.txt" },
  markers = { "README.md" },
  skills = {
    { id = "ok-skill", valid = true, autoinvoke = true },
    { id = "broken", valid = false, autoinvoke = true },
    { id = "sleepy", valid = true, autoinvoke = false },
  },
  docs = { ["STACK.md"] = true, ["DESIGN.md"] = true },
  agents = { "AGENTS.md", "CLAUDE.md" },
  has_lock = true,
}
eq("adopt: counts skills", worked.skills_total, 3)
eq("adopt: broken counted, not announced", #worked.invalid, 1)
eq("adopt: dormant counted", #worked.dormant, 1)
eq("adopt: legacy without modern markers", worked.legacy, true)
ok("adopt: hints mention existing skills", table.concat(worked.hints, " "):find("ya hay 3", 1, true) ~= nil)
ok("adopt: hints warn invalid", table.concat(worked.hints, " "):find("inválida", 1, true) ~= nil)
ok("adopt: hints respect STACK", table.concat(worked.hints, " "):find("STACK.md", 1, true) ~= nil)

local clean = adopt.analyze { files = { "go.mod" }, markers = { "go.mod" }, skills = {}, docs = {}, agents = {}, has_lock = false }
eq("adopt: modern repo not legacy", clean.legacy, false)

local legacy_sug = adopt.adjust({
  { id = "caveman", action = "install" },
  { id = "go-pro", action = "install" },
  { id = "aws-pro", action = "keep" },
}, worked)
eq("adopt adjust: legacy keeps caveman only", #legacy_sug, 2)
eq("adopt adjust: legacy drops stack installs", legacy_sug[2].id, "aws-pro")

-- curated search
eq("catalog: curated has caveman", require("skills.catalog").curated_search("caveman")[1].id, "caveman")
eq("catalog: curated empty for nonsense", #require("skills.catalog").curated_search("zzz-no-match"), 0)
eq("catalog: go finds go-pro", require("skills.catalog").curated_search("go")[1].id, "go-pro")
eq("catalog: csharp finds dotnet-pro", require("skills.catalog").curated_search("csharp")[1].id, "dotnet-pro")
eq("catalog: cloudflare finds cloudflare-expert", require("skills.catalog").curated_search("cloudflare")[1].id, "cloudflare-expert")
eq("catalog: deploy finds devops-engineer", require("skills.catalog").curated_search("deploy")[1].id == "devops-engineer" or require("skills.catalog").curated_search("deploy")[1].id == "docker-pro", true)

-- ── marketplace ──────────────────────────────────────────────────────────────
vim.o.columns, vim.o.lines = 140, 40
package.loaded["utils.log"] = {
  info = function(m)
    notes[#notes + 1] = m
  end,
  warn = function(m)
    notes[#notes + 1] = m
  end,
  error = function(m)
    notes[#notes + 1] = m
  end,
}
local market = require "utils.market"
local skillmarket = require "skills.market"
local st = skillmarket.open()
ok("market: three windows open", vim.api.nvim_win_is_valid(st.wins.list))
local function text_of(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end
ok("market: title present", text_of(st.bufs.list):find("SKILLS", 1, true) ~= nil)
ok("market: summary shows counts", text_of(st.bufs.summary):find("ON", 1, true) ~= nil)

local function press(buf, key)
  local lhs = vim.api.nvim_replace_termcodes(key, true, true, true)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if vim.api.nvim_replace_termcodes(map.lhs, true, true, true) == lhs then
      return map.callback()
    end
  end
  error("no mapping " .. key)
end

-- filter: only cab in list
st.filter = "caveman"
market.refresh(st)
ok("market: filter narrows list", text_of(st.bufs.list):find("caveman", 1, true) ~= nil)
st.filter = ""
market.refresh(st)

-- navigate into a row and read its pane, Esc back
local at = nil
for i, r in ipairs(st.rows) do
  if r.skill or r.entry or r.suggestion then
    at = i
    break
  end
end
ok("market: at least one selectable row", at ~= nil)
if at then
  vim.api.nvim_win_set_cursor(st.wins.list, { at, 0 })
  market.refresh(st)
  press(st.bufs.list, "<CR>")
  eq("market: ⏎ reads (pane focused)", vim.api.nvim_get_current_win(), st.wins.pane)
  press(st.bufs.pane, "<Esc>")
  eq("market: Esc back to list", vim.api.nvim_get_current_win(), st.wins.list)
end

-- help opens and closes
local wins_before = #vim.api.nvim_list_wins()
press(st.bufs.list, "?")
eq("market: ? opens help", #vim.api.nvim_list_wins(), wins_before + 1)
press(vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win()), "<Esc>")
eq("market: Esc closes help", #vim.api.nvim_list_wins(), wins_before)
vim.api.nvim_set_current_win(st.wins.list)

market.close(st)
ok("market: close shuts windows", not vim.api.nvim_win_is_valid(st.wins.list))

-- menu registered
local found = false
for _, ctx in ipairs(require("menus").contexts()) do
  if ctx.prefix == "aK" then
    found = true
  end
end
eq("menu: <leader>aK registered", found, true)

-- provider shape
local provider = require "agent.context.providers.skills"
eq("provider: cap", provider.cap, 1200)
eq("provider: stability", provider.stability, 1)

print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd "qa!"
