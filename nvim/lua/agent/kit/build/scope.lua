-- ── Build with agent: what one build covers (pure, except `existing`) ────────
-- A build is the whole project (all four documents) or one layer of it, each from the document that describes it:
--   foundation  STACK.md   manifest, layout, tooling, a minimal entry point that runs (<leader>aSbt)
--   domain      SPEC.md    entities, rules, use cases and their tests, no interface (<leader>aSbs)
--   design      DESIGN.md  theme, styles, components and screens, wired to the domain that exists (<leader>aSbd)
--   all         the four   everything at once, the original build (<leader>aSbb)
-- and two task scopes, whose rules come from the task they carry (`run.task`: id, title, text):
--   feature     one requirement of SPEC.md, end to end: its domain, the interface that reaches it, its tests (<leader>aSbf)
--   recipe      one prefab task from kit/presets/recipes (a screen, an endpoint, an entity…), filled in (<leader>aSr)
-- Task scopes are additive: each one adds to the project, so one never sends another's files to the trash.
-- A layer is built on top of what the project already has: its files go to the plan as <project> (paths, manifests,
-- the API they declare) and to every file request (they are in `written`), so the domain uses the foundation's module
-- and the screens call the domain instead of writing it again. Each scope keeps its own saved run and its own list of
-- written files, so replanning one never sends another's files to the trash. Tested in test-kit-scope.lua.
local M = {}

M.NAMES = { "all", "foundation", "domain", "design" }
--- The scopes that carry a task (their rules are functions of it)
M.TASKS = { "feature", "recipe" }

---@class BuildTask
---@field id string     "FR-8", "flutter/screen-riverpod:Profile"
---@field title string  what the view and the notices call it
---@field text string   the requirement or the recipe, filled in: what the plan and every file request get

---@class BuildScope
---@field name string
---@field label string      what the view and the notices call it
---@field key string        its key under <leader>aS (the document's own letter there, after the build's `b`)
---@field from string?      the document it is built from ("SPEC.md")
---@field docs string[]     the documents it reads (when they exist)
---@field required string[] the documents it cannot start without
---@field existing boolean  builds on the project's files (they go to the plan and the file requests)
---@field additive boolean? adds to the project: no list of its own files, no stale files, nothing of the project skipped
---@field wiring boolean    the check that what the plan exports is used by the interface
---@field use boolean       the app is used like its user would (needs SPEC.md)
---@field max_files integer?
---@field plan string|fun(task: BuildTask): string|nil   the plan request's rules for this scope
---@field file string|fun(task: BuildTask): string|nil   the line every file request of this scope adds to the system prompt
---@field ask string|fun(task: BuildTask): string        the plan request's last line

---@type table<string, BuildScope>
M.SCOPES = {
  all = {
    name = "all",
    label = "everything",
    key = "bb",
    docs = { "agents", "stack", "design", "spec" },
    required = { "agents", "stack", "design", "spec" },
    existing = false,
    wiring = true,
    use = true,
    ask = "Plan the files to build this project.",
  },
  foundation = {
    name = "foundation",
    label = "foundation",
    key = "bt",
    from = "STACK.md",
    docs = { "agents", "stack" },
    required = { "stack" },
    existing = true,
    wiring = false,
    use = false,
    max_files = 15,
    plan = [[This build is ONLY the project's foundation, from STACK.md: the manifest, the folder layout STACK.md describes, the configuration and tooling it names (formatter, linter, test runner, Makefile or scripts, environment example), a minimal entry point that builds and runs (it starts and shows or prints the project's name, nothing more), one smoke test where STACK.md says tests live, and README.md.
No domain logic, no screens, no features: a domain build (from SPEC.md) and a design build (from DESIGN.md) come later on top of it, so keep their places in the layout ready (a folder needs no placeholder file).
The files in <project>, when there is one, already exist: plan one of them again only when it must change, with the same path.
`wiring` and `examples`: empty lists. At most 15 files.]],
    file = "This build is the foundation only: manifest, layout, tooling and a minimal entry point that runs. Write no domain logic and no screens.",
    ask = "Plan the files of the project's foundation.",
  },
  domain = {
    name = "domain",
    label = "domain",
    key = "bs",
    from = "SPEC.md",
    docs = { "agents", "stack", "spec" },
    required = { "stack", "spec" },
    existing = true,
    wiring = false,
    use = false,
    max_files = 20,
    plan = [[This build is ONLY the domain, from SPEC.md: the entities, value objects, rules, errors and use cases (services) its requirements describe, and the ports (interfaces) they need, where STACK.md's layout puts the domain, each with tests that prove its FR-n.
No user interface, no screens, no styles; no adapters except in-memory ones the tests need; leave the entry point as it is.
The files in <project> already exist (the foundation): build on them (the module, the layout, the test setup), and plan one of them again only when it must change (the manifest needs a dependency), with the same path. Without a manifest in <project>, plan it first.
`wiring`: an empty list. `examples`: the domain's behaviour as calls, the exact call and its exact result or error. At most 20 files.]],
    file = "This build is the domain only: the code SPEC.md describes and its tests, no user interface. Build on the project's existing files exactly as they are shown.",
    ask = "Plan the files of the project's domain.",
  },
  design = {
    name = "design",
    label = "design",
    key = "bd",
    from = "DESIGN.md",
    docs = { "agents", "stack", "design", "spec" },
    required = { "stack", "design" },
    existing = true,
    wiring = true,
    use = true,
    max_files = 25,
    plan = [[This build is ONLY what the user sees, from DESIGN.md: the theme or tokens, styles, components and screens (exactly as its `## Screens` draws them, when it has them), wired into the entry point so the app opens on them.
The files in <project> already exist: call the domain they declare (its API is in <project>) for every behaviour, never write it again; plan an existing file again only when it must change (the entry point now opens the interface), with the same path. When <project> has no domain yet, the screens take their data from one small sample-data file planned here.
`wiring`: one row per SPEC.md requirement the screens reach (per interaction DESIGN.md describes when there is no SPEC.md). At most 25 files.]],
    file = "This build is the interface only: follow DESIGN.md exactly and call the existing domain through the names in <api>; never write its rules again.",
    ask = "Plan the files of the project's interface.",
  },
  feature = {
    name = "feature",
    label = "feature",
    key = "bf",
    from = "SPEC.md",
    docs = { "agents", "stack", "design", "spec" },
    required = { "stack", "spec" },
    existing = true,
    additive = true,
    wiring = true,
    use = true,
    max_files = 12,
    plan = function(t)
      return ([[This build is ONLY %s of SPEC.md (%s), added to the project as it is:
<requirement>
%s
</requirement>
Plan the smallest set of files that makes it work end to end for the user: the domain it needs (new entities or rules, or a change to existing ones), the interface that reaches it when the project has one (screen, route, command, endpoint) and the tests that prove its acceptance criteria.
Follow the patterns the existing code in <project> already uses: the same folders, naming, state management, error handling and test style. Plan an existing file again only when it must change, with the same path; its new version keeps everything the rest of the project uses from it. Never rewrite, rename or move what this requirement does not need.
`wiring`: rows for %s only. `examples`: its acceptance criteria made exact. At most 12 files.]]):format(
        t.id,
        t.title,
        vim.trim(t.text),
        t.id
      )
    end,
    file = function(t)
      return ("This build adds %s (%s) only: follow the patterns of the existing code and change no behaviour other requirements rely on."):format(
        t.id,
        t.title
      )
    end,
    ask = function(t)
      return ("Plan the files that add %s."):format(t.id)
    end,
  },
  recipe = {
    name = "recipe",
    label = "recipe",
    key = "r",
    from = "a recipe",
    docs = { "agents", "stack", "design", "spec" },
    required = { "stack" },
    existing = true,
    additive = true,
    wiring = false,
    use = false,
    max_files = 10,
    plan = function(t)
      return ([[This build is ONLY the recipe below (%s), applied to the project as it is:
<recipe>
%s
</recipe>
The recipe says what to make; STACK.md and the existing code in <project> say how: put every file where STACK.md's layout and the existing code put that kind of file, with their naming, patterns and test style (the recipe's paths are only a hint when the project already does it differently). Plan an existing file again only when it must change (a route registered, a provider wired), with the same path; its new version keeps everything the rest of the project uses from it. Nothing the recipe does not ask for.
`wiring`: rows for what the recipe makes reach the user, else an empty list. `examples`: what its tests check, made exact. At most 10 files.]]):format(
        t.title,
        vim.trim(t.text)
      )
    end,
    file = function(t)
      return ("This build applies one recipe (%s): follow the patterns of the existing code and change nothing it does not ask for."):format(
        t.title
      )
    end,
    ask = function(t)
      return ("Plan the files of the recipe: %s."):format(t.title)
    end,
  },
}

--- A scope by name ("all" for nil or an unknown name)
---@param name string?
---@return BuildScope
function M.get(name)
  return M.SCOPES[name or "all"] or M.SCOPES.all
end

--- "<leader>aSbs": the key that opens a scope's build view
---@param name string?
---@return string
function M.keys(name)
  return "<leader>aS" .. M.get(name).key
end

--- A scope's rules for a task: what the plan request adds, the line of every file request, the plan's last line
---@param name string?
---@param task BuildTask?
---@return { plan: string?, file: string?, ask: string }
function M.rules(name, task)
  local s = M.get(name)
  local function value(v)
    if type(v) == "function" then
      return task and v(task) or nil
    end
    return v
  end
  return { plan = value(s.plan), file = value(s.file), ask = value(s.ask) or M.SCOPES.all.ask }
end

--- "domain · from SPEC.md", "feature FR-8 · Export notes" (what the view's header and the notices say); "" for the whole
--- build
---@param name string?
---@param task BuildTask?
---@return string
function M.title(name, task)
  local s = M.get(name)
  if s.name == "all" then
    return ""
  elseif s.name == "feature" then
    return task and ("feature %s · %s"):format(task.id, task.title) or "feature · from SPEC.md"
  elseif s.name == "recipe" then
    return task and ("recipe · %s"):format(task.title) or "recipe"
  end
  return ("%s · from %s"):format(s.label, s.from)
end

-- Files that are never project code to show the plan: the kit's documents, the agents' own files, binaries
local DOCS =
  { "AGENTS.md", "STACK.md", "DESIGN.md", "SPEC.md", "CLAUDE.md", ".agent.md", "PROGRESS.md", "CHANGELOG.md" }
local BINARY = {
  "png",
  "jpg",
  "jpeg",
  "gif",
  "webp",
  "ico",
  "bmp",
  "svgz",
  "pdf",
  "zip",
  "gz",
  "tgz",
  "tar",
  "7z",
  "jar",
  "class",
  "exe",
  "dll",
  "so",
  "dylib",
  "a",
  "o",
  "wasm",
  "woff",
  "woff2",
  "ttf",
  "otf",
  "eot",
  "mp3",
  "mp4",
  "wav",
  "ogg",
  "mov",
  "webm",
  "db",
  "sqlite",
  "lock",
  "lockb",
}

--- Is this one of the project's own text files worth showing a layer build? (pure)
---@param path string
---@return boolean
function M.keep(path)
  if
    vim.tbl_contains(DOCS, path)
    or path:match "^docs/adr/" -- the decisions are records, not code (the ADRs: agent/kit/adr.lua)
    or require("agent.kit.build.plan").generated(path)
  then
    return false
  end
  if path:match "^%." or path:find "/%." then -- .git, .github, .vscode, .env: not what the layer builds on
    return path == ".gitignore" or path == ".editorconfig"
  end
  local ext = path:match "%.([%w]+)$"
  return not (ext and vim.tbl_contains(BINARY, ext:lower()))
end

M.MAX_EXISTING = 150
M.MAX_BYTES = 48 * 1024

--- The project's files a layer builds on: path → text (git's list when it is a repository; small text files only; the
--- paths in `skip` are left out: the files this scope wrote last time, which its new plan replaces)
---@param root string
---@param skip string[]?
---@return table<string, string>
function M.existing(root, skip)
  local skipped = {}
  for _, p in ipairs(skip or {}) do
    skipped[p] = true
  end
  local out, count = {}, 0
  local paths = require("agent.kit.snapshot").list_files(root)
  table.sort(paths)
  for _, path in ipairs(paths) do
    if count >= M.MAX_EXISTING then
      break
    end
    local stat = not skipped[path] and M.keep(path) and vim.uv.fs_stat(root .. "/" .. path)
    if stat and stat.type == "file" and stat.size <= M.MAX_BYTES then
      local text = require("utils.project").read(root .. "/" .. path)
      if text and not text:find("\0", 1, true) then
        out[path], count = text, count + 1
      end
    end
  end
  return out
end

--- The <project> block of a layer's plan request: the files already there, the manifests whole, the API the code
--- declares (pure)
---@param existing table<string, string>
---@return string
function M.project(existing)
  local paths = vim.tbl_keys(existing)
  if #paths == 0 then
    return "<project>\nThe project has no files yet.\n</project>"
  end
  table.sort(paths)
  local out = { "<project>", "Files already in the project (build on them; plan one again only to change it):" }
  for _, p in ipairs(paths) do
    out[#out + 1] = "- " .. p
  end
  local verify = require "agent.kit.build.verify"
  for _, p in ipairs(paths) do
    if verify.is_manifest(p) then
      local text = vim.trim(existing[p])
      out[#out + 1] = ('<file path="%s">\n%s\n</file>'):format(
        p,
        #text > 3000 and (text:sub(1, 3000) .. "\n…") or text
      )
    end
  end
  local api = require("agent.kit.build.prompt").api(existing)
  if api ~= "" then
    out[#out + 1] = api
  end
  out[#out + 1] = "</project>"
  return table.concat(out, "\n")
end

return M
