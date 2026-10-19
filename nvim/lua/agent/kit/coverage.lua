-- ── Spec coverage and document drift (<leader>aSv), 0 tokens ─────────────────
-- What the documents promise against what the code has, without a model:
--   requirements  every FR-n of SPEC.md, with the tests that prove it (a test that names it, or a build plan's `verifies`)
--   tools         what STACK.md's Stack table names that the manifest lacks (npm packages, pub/cargo/pip names, Go modules)
--   tokens        DESIGN.md's color tokens no source file uses (in any spelling: text-muted, text_muted, textMuted)
--   folders       the project's folders no document mentions (the layout drifted, or STACK.md never knew)
-- The checks are pure (tested in test-kit-records.lua); `collect` reads the project, `open` shows the report: ⏎ on a
-- requirement builds it as a feature (<leader>aSbf), on anything else opens where it is. PROGRESS.md's "Next" comes from
-- here too.
local M = {}

---@class CoverageReq
---@field id string     "FR-3"
---@field title string
---@field line integer  where it is in SPEC.md
---@field tests string[] files that prove it

--- The requirements of SPEC.md (in its Requirements section when it has one): the first line that names each id
---@param spec string
---@return CoverageReq[]
function M.requirements(spec)
  local out, seen = {}, {}
  local lines = vim.split(spec or "", "\n", { plain = true })
  local from, to = 1, #lines
  for i, l in ipairs(lines) do
    if l:match "^##%s+Requirements%s*$" then
      from, to = i + 1, #lines
      for j = i + 1, #lines do
        if lines[j]:match "^##%s" and not lines[j]:match "^###" then
          to = j - 1
          break
        end
      end
      break
    end
  end
  for i = from, to do
    local l = lines[i]
    -- `### FR-3: Title`, `- **FR-3** Title: …`, `**FR-3.** The system must…`, `| FR-3 | … |`
    local id, rest = l:match "^[%s#%-*|]*%**(FR%-%d+)%**[%s:.)|%-–—]*(.*)$"
    if id and not seen[id] then
      seen[id] = true
      local title = vim.trim((rest or ""):gsub("%*%*", ""):gsub("|.*$", ""))
      out[#out + 1] = { id = id, title = title ~= "" and title or id, line = i, tests = {} }
    end
  end
  return out
end

--- Does the text name this requirement? (FR-3 but not FR-30)
---@param text string
---@param id string
---@return boolean
local function names(text, id)
  return text:find(id:gsub("%-", "%%-") .. "%f[%D]") ~= nil
end

--- The tests of every requirement (pure): a test file whose text names it, or a planned file whose `verifies` does
---@param reqs CoverageReq[]
---@param tests table<string, string> test path → text
---@param verifies { path: string, text: string }[] from the builds' plans (files that exist)
---@return CoverageReq[]
function M.cover(reqs, tests, verifies)
  local paths = vim.tbl_keys(tests)
  table.sort(paths)
  for _, r in ipairs(reqs) do
    local found = {}
    for _, p in ipairs(paths) do
      if names(tests[p], r.id) then
        found[p] = true
      end
    end
    for _, v in ipairs(verifies) do
      if names(v.text, r.id) then
        found[v.path] = true
      end
    end
    r.tests = vim.tbl_keys(found)
    table.sort(r.tests)
  end
  return reqs
end

--- The names in STACK.md's Stack table the manifest lacks (pure). package.json: the tools the build knows
--- (verify.missing_tools); other manifests: the package names the table spells in backticks (`go_router`,
--- `github.com/go-chi/chi/v5`, `serde_json`), when they look like that manifest's packages
---@param stack string
---@param manifests table<string, string> name → text (package.json, pubspec.yaml, go.mod, Cargo.toml, pyproject.toml…)
---@return { name: string, manifest: string }[]
function M.missing_tools(stack, manifests)
  local out = {}
  if manifests["package.json"] then
    for _, pkg in ipairs(require("agent.kit.build.verify").missing_tools(stack, manifests["package.json"])) do
      out[#out + 1] = { name = pkg, manifest = "package.json" }
    end
  end
  local table_text = (stack or ""):match "\n## Stack%s*\n(.-)\n## " or (stack or ""):match "\n## Stack%s*\n(.*)$" or ""
  local looks = {
    ["pubspec.yaml"] = function(n)
      return n:match "^[a-z][a-z0-9]*_[a-z0-9_]+$" ~= nil
    end,
    ["go.mod"] = function(n)
      return n:match "^[%w%-]+%.[%w%.%-]+/[%w%-%._/]+$" ~= nil and not n:match "%.go$"
    end,
    ["Cargo.toml"] = function(n)
      return n:match "^[a-z][a-z0-9]*[_%-][a-z0-9_%-]+$" ~= nil
    end,
    ["pyproject.toml"] = function(n)
      return n:match "^[a-z][a-z0-9]*[_%-][a-z0-9_%-]+$" ~= nil
    end,
  }
  local seen = {}
  for name, text in pairs(manifests) do
    local fits = looks[name]
    if fits then
      for row in table_text:gmatch "[^\n]+" do
        if row:match "^|" and not row:match "^|%s*%-" then
          for pkg in row:gmatch "`([^`%s]+)`" do
            local base = name == "go.mod" and pkg:gsub("@.*$", "") or pkg
            if fits(base) and not seen[base] and not text:find(base, 1, true) then
              seen[base] = true
              out[#out + 1] = { name = base, manifest = name }
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

--- DESIGN.md's color tokens (pure): the first column of the tables in its Color section, and every `--css-variable`
---@param design string
---@return string[]
function M.tokens(design)
  local out, seen = {}, {}
  local function add(t)
    if t ~= "" and not seen[t] and #t >= 3 then
      seen[t] = true
      out[#out + 1] = t
    end
  end
  local color = (design or ""):match "\n## Color%s*\n(.-)\n## " or ""
  for row in color:gmatch "[^\n]+" do
    local first = row:match "^|%s*([^|]-)%s*|"
    if first and not row:match "^|%s*%-" then
      local name = first:gsub("[`*]", "")
      if name:match "^[%w%-%._]+$" and not name:lower():match "^token$" and not name:lower():match "^role$" then
        add(name)
      end
    end
  end
  for var in (design or ""):gmatch "`(%-%-[%w%-]+)`" do
    add(var)
  end
  return out
end

--- The ways code spells a token: text-muted, text_muted, textMuted, TextMuted, --text-muted
---@param token string
---@return string[]
local function spellings(token)
  local base = token:gsub("^%-%-", "")
  local words = vim.split(base:gsub("[%._]", "-"), "-", { trimempty = true })
  local camel = words[1] or ""
  for i = 2, #words do
    camel = camel .. words[i]:sub(1, 1):upper() .. words[i]:sub(2)
  end
  return {
    base,
    table.concat(words, "-"),
    table.concat(words, "_"),
    camel,
    camel:sub(1, 1):upper() .. camel:sub(2),
  }
end

--- The tokens no source file uses, in any of their spellings (pure)
---@param tokens string[]
---@param sources table<string, string> path → text
---@return string[]
function M.unused_tokens(tokens, sources)
  local out = {}
  for _, t in ipairs(tokens) do
    local used = false
    for _, text in pairs(sources) do
      for _, s in ipairs(spellings(t)) do
        if s ~= "" and text:find(s, 1, true) then
          used = true
          break
        end
      end
      if used then
        break
      end
    end
    if not used then
      out[#out + 1] = t
    end
  end
  return out
end

-- folders whose sub-folders are the layout (lib/features/notes, internal/domain, src/components)
local LAYOUT_ROOTS =
  { src = true, lib = true, internal = true, cmd = true, app = true, pkg = true, packages = true, apps = true }
local NEVER = { docs = true, test = true, tests = true, testdata = true, assets = true, scripts = true, build = true }

--- The project's folders no document mentions (pure): top-level ones, and those one level under src/, lib/, internal/…
---@param paths string[]
---@param docs string the documents' text, together
---@return string[]
function M.unmentioned(paths, docs)
  local dirs = {}
  for _, p in ipairs(paths) do
    local top, second = p:match "^([^/]+)/([^/]+)/"
    local only = p:match "^([^/]+)/"
    if only and not only:match "^%." and not NEVER[only] then
      dirs[only] = true
      if top and LAYOUT_ROOTS[top] and not second:match "^%." then
        dirs[top .. "/" .. second] = true
      end
    end
  end
  local out = {}
  for d in pairs(dirs) do
    local base = vim.fs.basename(d)
    local said = docs:find(d .. "/", 1, true) or docs:find("`" .. d .. "`", 1, true)
    if not said and d:find("/", 1, true) then -- `features/notes/` or `notes/` in a layout tree counts too
      said = docs:find(base .. "/", 1, true)
    end
    if not said then
      out[#out + 1] = d .. "/"
    end
  end
  table.sort(out)
  return out
end

-- source files (where tokens are used): code and styles, not documents
local SOURCE = {
  "dart",
  "go",
  "ts",
  "tsx",
  "js",
  "jsx",
  "mjs",
  "vue",
  "svelte",
  "astro",
  "css",
  "scss",
  "sass",
  "less",
  "html",
  "rs",
  "py",
  "kt",
  "swift",
  "java",
  "templ",
}

---@class CoverageFacts
---@field name string
---@field docs table<string, string> id → text
---@field paths string[]
---@field tests table<string, string>
---@field sources table<string, string>
---@field manifests table<string, string>
---@field verifies { path: string, text: string }[]

--- What the report reads: the documents, the files (git's list), the tests and sources (small ones), the manifests, the
--- `verifies` of every saved build plan of the project whose file still exists
---@param root string
---@return CoverageFacts
function M.collect(root)
  local read = require("utils.project").read
  local verify = require "agent.kit.build.verify"
  local docs = {}
  for _, d in ipairs(require("agent.kit.compose").DOCS) do
    docs[d.id] = read(root .. "/" .. d.file)
  end
  local facts = {
    name = vim.fs.basename(root),
    docs = docs,
    paths = require("agent.kit.snapshot").list_files(root),
    tests = {},
    sources = {},
    manifests = {},
    verifies = {},
  }
  local count = 0
  for _, p in ipairs(facts.paths) do
    local stat = count < 600 and vim.uv.fs_stat(root .. "/" .. p)
    if stat and stat.size <= 96 * 1024 then
      local ext = (p:match "%.([%w]+)$" or ""):lower()
      if verify.is_test(p) then
        facts.tests[p], count = read(root .. "/" .. p) or "", count + 1
      elseif vim.tbl_contains(SOURCE, ext) and not p:match "%.g%.dart$" and not p:match "%.freezed%.dart$" then
        facts.sources[p], count = read(root .. "/" .. p) or "", count + 1
      end
    end
    if p:find("/", 1, true) == nil and (verify.is_manifest(p) or p == "pyproject.toml") then
      facts.manifests[p] = read(root .. "/" .. p) or ""
    end
  end
  local state = require "agent.kit.build.state"
  local scope = require "agent.kit.build.scope"
  for _, name in ipairs(vim.list_extend(vim.deepcopy(scope.NAMES), scope.TASKS)) do
    local run = state.load(root, name ~= "all" and name or nil)
    for _, f in ipairs(run and run.plan and run.plan.files or {}) do
      if f.verifies and vim.uv.fs_stat(root .. "/" .. f.path) then
        facts.verifies[#facts.verifies + 1] = { path = f.path, text = f.verifies }
      end
    end
  end
  return facts
end

---@class CoverageReport
---@field requirements CoverageReq[]
---@field tools { name: string, manifest: string }[]
---@field tokens string[]?   nil: no DESIGN.md or no source file to look in
---@field folders string[]

--- Every check on the facts (pure)
---@param facts CoverageFacts
---@return CoverageReport
function M.report(facts)
  local docs = facts.docs
  local all = table.concat(vim.tbl_values(docs), "\n")
  return {
    requirements = M.cover(M.requirements(docs.spec or ""), facts.tests, facts.verifies),
    tools = docs.stack and M.missing_tools(docs.stack, facts.manifests) or {},
    tokens = (docs.design and next(facts.sources)) and M.unused_tokens(M.tokens(docs.design), facts.sources) or nil,
    folders = M.unmentioned(facts.paths, all),
  }
end

--- The requirements no test proves yet (PROGRESS.md's "Next")
---@param report CoverageReport
---@return CoverageReq[]
function M.uncovered(report)
  return vim.tbl_filter(function(r)
    return #r.tests == 0
  end, report.requirements)
end

--- The report as Markdown, and what ⏎ does on each line (pure)
---@param report CoverageReport
---@param name string
---@return string[] lines, table<integer, table> actions
function M.render(report, name)
  local lines, actions = {}, {}
  local function add(text, action)
    lines[#lines + 1] = text
    actions[#lines] = action
  end
  add("# Coverage · " .. name)
  add ""
  add "0 tokens: SPEC.md, STACK.md and DESIGN.md against the code · ⏎ acts on the line · r reads again · q closes"
  add ""
  local reqs = report.requirements
  local done = #reqs - #M.uncovered(report)
  add(("## Requirements · %d/%d with a test"):format(done, #reqs))
  add ""
  if #reqs == 0 then
    add "No FR-n in SPEC.md (<leader>aSs writes it)."
  end
  for _, r in ipairs(reqs) do
    if #r.tests > 0 then
      add(
        ("- ● %s %s · %s"):format(r.id, r.title, table.concat(r.tests, ", ")),
        { kind = "open", path = r.tests[1] }
      )
    else
      add(("- ○ %s %s · no test proves it · ⏎ builds it"):format(r.id, r.title), { kind = "feature", req = r })
    end
  end
  add ""
  add("## STACK.md names the manifest lacks · " .. #report.tools)
  add ""
  if #report.tools == 0 then
    add "Nothing: every tool STACK.md names is in the manifest (or none can be checked)."
  end
  for _, t in ipairs(report.tools) do
    add(("- `%s`: not in %s"):format(t.name, t.manifest), { kind = "open", path = t.manifest })
  end
  add ""
  if report.tokens then
    add("## DESIGN.md tokens no code uses · " .. #report.tokens)
    add ""
    if #report.tokens == 0 then
      add "Nothing: the code uses every color token."
    end
    for _, t in ipairs(report.tokens) do
      add(("- `%s`"):format(t), { kind = "open", path = "DESIGN.md", search = t })
    end
    add ""
  end
  add("## Folders no document mentions · " .. #report.folders)
  add ""
  if #report.folders == 0 then
    add "Nothing: the documents know every folder."
  end
  for _, f in ipairs(report.folders) do
    add(
      ("- `%s` · ⏎ STACK.md's layout"):format(f),
      { kind = "open", path = "STACK.md", search = "## Project layout" }
    )
  end
  return lines, actions
end

--- <leader>aSv: the report of this project, in a split
function M.open()
  local root = require("agent.kit.snapshot").root()
  local report = M.report(M.collect(root))
  local lines, actions = M.render(report, vim.fs.basename(root))
  local buf = vim.fn.bufnr "kit://coverage"
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "kit://coverage")
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].filetype = "markdown"
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if vim.fn.bufwinid(buf) == -1 then
    vim.cmd "botright vsplit"
    vim.api.nvim_win_set_buf(0, buf)
  else
    vim.api.nvim_set_current_win(vim.fn.bufwinid(buf))
  end
  local function act()
    local a = actions[vim.api.nvim_win_get_cursor(0)[1]]
    if not a then
      return
    end
    if a.kind == "feature" then
      return require("agent.kit.feature").build(root, a.req)
    end
    vim.cmd "wincmd p"
    vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. a.path))
    if a.search then
      vim.fn.search(vim.fn.escape(a.search, "\\/.*$^~[]"), "cw")
    end
  end
  vim.keymap.set("n", "<CR>", act, { buffer = buf, nowait = true, desc = "Coverage act on the line" })
  vim.keymap.set("n", "r", M.open, { buffer = buf, nowait = true, desc = "Coverage read again" })
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, desc = "Coverage close" })
end

return M
