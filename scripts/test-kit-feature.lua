-- Tests of feature slices and recipes (nvim/lua/agent/kit/feature.lua, recipes.lua, build scopes `feature`/`recipe`):
-- a new requirement written into SPEC.md in its own style (ids, criteria, edge cases, numbered questions), the text of
-- one requirement, every recipe file (parses, asks something, fits a real stack preset, fills every placeholder), and
-- both builds with a fake model: the requirement/recipe in every request, additive (nothing remembered, nothing stale),
-- one run per task. Hermetic: temp projects, no network or tokens.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-kit-feature.lua"
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
    confirms[#confirms + 1] = { title = opts.title, lines = lines }
    yes()
  end,
}
local drafts = {}
package.loaded["agent.kit.draft"] = {
  open = function(opts, submit)
    drafts[#drafts + 1] = opts
    submit "Users export a note as Markdown"
  end,
  forget = function() end,
}

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

local feature = require "agent.kit.feature"
local recipes = require "agent.kit.recipes"

-- ── a new requirement in SPEC.md ─────────────────────────────────────────────

local heading_spec = table.concat({
  "# SPEC.md: Notes",
  "",
  "## Requirements",
  "",
  "### FR-1: Create a note",
  "",
  "The system must create notes.",
  "",
  "- Given nothing, when I create, then a note",
  "",
  "### FR-2: Delete",
  "",
  "The system must delete.",
  "",
  "## Edge cases",
  "",
  "- (FR-1) empty title: rejected",
  "",
  "## Open questions",
  "",
  "- Q1: sync?",
  "- Q2 (FR-2): undo?",
  "",
  "## Milestones",
  "",
  "1. MVP",
}, "\n")
local data = {
  title = "Export a note",
  statement = "The system must export a note as Markdown.",
  criteria = { "Given a note, when I export it, then a .md file has its title and body" },
  edge_cases = { "an empty note: export is disabled" },
  questions = { "Where is the file saved?" },
  builds_on = { "FR-1" },
}
eq("next id: one after the highest anywhere", feature.next_id(heading_spec), "FR-3")
eq("next id: the first", feature.next_id "# S\n", "FR-1")
eq("style: heading", feature.style(heading_spec).kind, "heading")
local added = feature.add(heading_spec, "FR-3", data)
ok(
  "add heading style: after the last requirement, same shape",
  added:find(
    "The system must delete.\n\n### FR-3: Export a note\n\nThe system must export a note as Markdown. Builds on FR-1.\n\n- Given a note, when I export it, then a .md file has its title and body\n\n## Edge cases",
    1,
    true
  )
)
ok(
  "add: its edge case under Edge cases",
  added:find("- (FR-1) empty title: rejected\n- (FR-3) an empty note: export is disabled\n", 1, true)
)
ok(
  "add: its question numbered on",
  added:find("- Q2 (FR-2): undo?\n- Q3 (FR-3): Where is the file saved?\n\n## Milestones", 1, true)
)
local list_spec =
  "# S\n\n## Requirements\n\n- **FR-1** Create: The system must create.\n    - Given x, when y, then z\n\n## Data\n"
local list_added = feature.add(list_spec, "FR-2", data)
ok(
  "add list style: a bullet with its criteria at the same indent",
  list_added:find(
    "    - Given x, when y, then z\n- **FR-2** Export a note: The system must export a note as Markdown. Builds on FR-1.\n    - Given a note",
    1,
    true
  )
)
ok("add: a section SPEC.md lacks is added", list_added:find("\n## Edge cases\n\n- (FR-2) an empty note", 1, true))
ok(
  "add: unnumbered questions stay unnumbered",
  list_added:find("\n## Open questions\n\n- (FR-2) Where is the file saved?", 1, true)
)
local block = feature.block(added, "FR-3")
ok(
  "block: the requirement from its heading to the next section",
  block:find "^### FR%-3: Export a note\n\nThe system must export" and block:find("then a .md file", 1, true)
)
ok(
  "block: and its lines elsewhere",
  block:find(
    "Elsewhere in SPEC.md:\n- (FR-3) an empty note: export is disabled\n- Q3 (FR-3): Where is the file saved?",
    1,
    true
  )
)
ok("block: not the next requirement", not feature.block(added, "FR-1"):find("FR-2: Delete", 1, true))
eq("block: unknown id", feature.block(added, "FR-9"), nil)
eq("parse: a usable requirement", feature.parse(vim.json.encode(data)).title, "Export a note")
eq(
  "parse: no criteria = not usable",
  select(2, feature.parse '{"title":"x","statement":"y","criteria":[]}'),
  "the requirement has no title, statement or acceptance criteria"
)

-- ── recipes ──────────────────────────────────────────────────────────────────

local all = recipes.all()
ok("recipes: there are some, in groups", #all >= 10 and all[1].group ~= nil)
local presets = require "agent.kit.presets"
local stacks = presets.all "stack"
for _, r in ipairs(all) do
  ok("recipe " .. r.id .. ": asks at least one value", #r.inputs >= 1)
  ok(
    "recipe " .. r.id .. ": has Make, Rules and Tests",
    r.body:find("\n## Make\n", 1, true)
      and r.body:find("\n## Rules\n", 1, true)
      and r.body:find("\n## Tests\n", 1, true)
  )
  local values = {}
  for _, input in ipairs(r.inputs) do
    values[input.key] = "user profile"
  end
  local _, left = recipes.fill(r.body, values)
  eq("recipe " .. r.id .. ": every placeholder filled", left, {})
  local fits = false
  for _, s in ipairs(stacks) do
    fits = fits or recipes.fits(r, presets.tags(s, s.category))
  end
  ok("recipe " .. r.id .. ": fits at least one stack preset", fits)
end
local function stack_named(id)
  for _, s in ipairs(stacks) do
    if s.id == id then
      return s
    end
  end
end
local function ids_for(stack_id)
  local s = stack_named(stack_id)
  local tags = presets.tags(s, s.category)
  return vim.tbl_map(
    function(r)
      return r.id
    end,
    vim.tbl_filter(function(r)
      return recipes.fits(r, tags)
    end, all)
  )
end
local flutter = ids_for((stack_named "flutter-riverpod" and "flutter-riverpod") or "flutter")
ok(
  "fits: a Flutter stack gets the Flutter recipes, not Go's",
  vim.tbl_contains(flutter, "flutter/screen") and not vim.tbl_contains(flutter, "go/http-endpoint")
)
eq(
  "spellings: of a free value",
  recipes.spellings "user profile",
  { snake = "user_profile", kebab = "user-profile", pascal = "UserProfile", camel = "userProfile" }
)
eq("spellings: of a PascalCase value", recipes.spellings("OrderDetails").snake, "order_details")
local tags = { go = true, server = true }
local fake = { fits = { "go+!server" } }
eq(
  "fits: `go+!server` = Go and not a server",
  { recipes.fits(fake, tags), recipes.fits(fake, { go = true }) },
  { false, true }
)
local screen = vim.tbl_filter(function(r)
  return r.id == "flutter/screen"
end, all)[1]
local task = recipes.task(screen, { name = "order details", shows = "the lines of an order" })
eq(
  "recipe task: id and title from the first value",
  { task.id, task.title },
  { "flutter/screen:order-details", "Flutter screen with its state · order details" }
)
ok(
  "recipe task: the body filled",
  task.text:find("`OrderDetailsScreen`", 1, true) and task.text:find("/order-details", 1, true)
)

-- ── the builds ───────────────────────────────────────────────────────────────

local proot = base .. "/notes"
write(proot .. "/STACK.md", "# STACK\n")
write(proot .. "/SPEC.md", heading_spec .. "\n")
write(proot .. "/lib/note.txt", "class Note\n")
vim.system({ "git", "init", "-q" }, { cwd = proot }):wait()
local requests = {}
package.loaded["agent"] = {
  complete = function(r, cb)
    requests[#requests + 1] = r
    if r.action == "kit_feature" then
      return cb(true, "```json\n" .. vim.json.encode(data) .. "\n```")
    end
    if r.action == "kit_build_plan" then
      return cb(
        true,
        vim.json.encode {
          name = "notes",
          files = { { path = "lib/export.txt", purpose = "export", docs = { "spec" }, needs = { "lib/note.txt" } } },
        },
        { tokens_in = 10, tokens_out = 5 }
      )
    end
    cb(true, "hello\n", { tokens_in = 3, tokens_out = 2 })
  end,
}
local build = require "agent.kit.build"
local state = require "agent.kit.build.state"
vim.cmd.edit(vim.fn.fnameescape(proot .. "/SPEC.md"))

-- a new feature: draft → request → confirm → SPEC.md → its build view
package.loaded["tasks.picker"] = {
  choose = function(items, _, on_select)
    on_select(items[1].value) -- "＋ new"
  end,
}
feature.open()
eq("feature new: the draft names the id it will get", drafts[1].title, "FR-3 · describe the feature")
eq("feature new: one request with SPEC.md and the draft", requests[1].action, "kit_feature")
ok(
  "feature new: SPEC.md and the next id in it",
  requests[1].prompt:find("<spec>", 1, true) and requests[1].prompt:find("This requirement will be FR-3", 1, true)
)
eq("feature new: confirmed before SPEC.md changes", confirms[1].title, "Add to SPEC.md and build it")
ok("feature new: SPEC.md has FR-3", (read(proot .. "/SPEC.md") or ""):find("### FR-3: Export a note", 1, true))
eq(
  "feature new: its build view, nothing planned yet",
  { state.run.scope, state.run.task.id, state.run.phase, #requests },
  { "feature", "FR-3", "ready", 1 }
)
ok(
  "feature: the task text is the requirement",
  state.run.task.text:find("The system must export a note as Markdown.", 1, true)
)
build.go()
local plan_req = requests[2]
ok(
  "feature plan: its rules carry the requirement",
  plan_req.system:find("ONLY FR-3 of SPEC.md (Export a note)", 1, true)
    and plan_req.system:find("<requirement>", 1, true)
)
ok("feature plan: its last line", vim.endswith(plan_req.prompt, "Plan the files that add FR-3."))
vim.wait(1600)
build.go()
vim.wait(2000, function()
  return state.run.phase == "done"
end)
eq("feature: done", state.run.phase, "done")
ok(
  "feature file: the line of the requirement in its system prompt",
  requests[3].system:find("This build adds FR-3 (Export a note) only", 1, true)
)
ok("feature: additive, no list of its own files", vim.uv.fs_stat(build.manifest_path(proot, "feature")) == nil)
eq("feature: nothing stale", state.run.stale, {})
-- another requirement: one run per task scope, a fresh one
package.loaded["tasks.picker"] = {
  choose = function(items, _, on_select)
    on_select(items[2].value) -- FR-1
  end,
}
vim.cmd "silent! tabonly"
vim.cmd.edit(vim.fn.fnameescape(proot .. "/SPEC.md"))
feature.open()
eq("feature pick: another requirement, a fresh run", { state.run.task.id, state.run.phase }, { "FR-1", "ready" })
ok("feature pick: its block as the task", state.run.task.text:find "^### FR%-1: Create a note")

-- a recipe
requests = {}
vim.cmd "silent! tabonly"
vim.cmd.edit(vim.fn.fnameescape(proot .. "/SPEC.md"))
build.open("recipe", task)
eq(
  "recipe: its build view",
  { state.run.scope, state.run.task.id, state.run.phase },
  { "recipe", "flutter/screen:order-details", "ready" }
)
build.go()
ok(
  "recipe plan: the filled recipe in its rules",
  requests[1].system:find("<recipe>", 1, true) and requests[1].system:find("OrderDetailsScreen", 1, true)
)
eq(
  "recipe: no use phase, no wiring check",
  { require("agent.kit.build.scope").get("recipe").use, require("agent.kit.build.scope").get("recipe").wiring },
  { false, false }
)
build.open "recipe"
ok("recipe: no task = it asks for one", notes[#notes]:find("needs its recipe", 1, true) or state.run.scope == "recipe")

vim.fn.delete(base, "rf")
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd "qa!"
