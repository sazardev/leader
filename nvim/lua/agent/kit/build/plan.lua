-- ── Build with agent: the plan (pure) ────────────────────────────────────────
-- One request turns the four documents into the build's contract: how it works (summary, architecture, decisions), how
-- each requirement reaches the user (wiring: action → code → what they see; the use phase drives the same paths) and an
-- ordered list of files, each with what it does, what it exports and promises to the others, what a test verifies, the
-- documents it needs and the earlier files it uses. The contract goes to every file request (prompt.lua's outline), so
-- files written apart still agree. Tested in test-kit.lua.
local M = {}

M.MAX_FILES = 40
M.DOCS = { "agents", "stack", "design", "spec" }

---@class BuildFile
---@field path string
---@field purpose string
---@field docs string[]   which of agents/stack/design/spec it needs
---@field needs string[]  files of the plan it uses (the plan is ordered so they come first: plancheck.lua)
---@field exports string[] what other files use from it, each with its contract ("NewKeypad(unicode bool) Keypad — highlight starts on =")
---@field verifies string? tests: what behaviour they check

---@class BuildPlan
---@field name string
---@field summary string        how the project will be built, in a few sentences
---@field architecture string   layers and the direction of dependencies
---@field decisions string[]    the choices that shape the code (libraries, patterns, data flow)
---@field risks BuildRisk[]?    the requirements most likely to fail, riskiest first: the real path through the first one is built first
---@field deferred BuildDeferred[]? requirements this build does NOT deliver, each with what is missing (never a silent stand-in)
---@field warnings string[]?    what the free checks of the plan found that is not a reason to replan (plancheck.warnings)
---@field wiring BuildWiring[]?  how each requirement reaches the user (action → code → what they see)
---@field examples BuildExample[]? SPEC.md made concrete: what the user does → exactly what they see
---@field files BuildFile[]
---@field problems string[]?  what cannot be built as planned (plancheck.lua); empty when it can
---@field scope string?       a layer or task build ("foundation", "domain", "design", "feature", "recipe"; nil = the whole project, scope.lua)
---@field task BuildTask?     the requirement or recipe of a task build (set by the build after parsing)

---@class BuildRisk
---@field req string   "FR-16"
---@field why string   why it is the hard one ("native decode, nothing in the project does it yet")

---@class BuildDeferred
---@field req string
---@field why string   what is missing that makes it impossible in this build ("needs the platform channel, ADR 0003 leaves it open")

---@class BuildExample
---@field req string     "FR-2"
---@field input string   what the user does, exactly ("12 + 7 =", "click 7, +, 3, =", "calc 6 / 0")
---@field expect string  exactly what they then see ("19", "the expression line shows 12 +", "error: division by zero")

---@class BuildWiring
---@field req string     "FR-2"
---@field action string  what the user does ("presses + between two numbers")
---@field code string    what runs ("ui.Update → domain.Calculator.ChooseOperator")
---@field shows string   what the user then sees, and where ("view.go: the expression line shows `12 +`")

local SYSTEM =
  [[You plan how a coding agent builds a project from its documents, one small file at a time. The plan is the
contract every file is then written against, so it must say what each file does and what it promises to the others.
Output ONLY one JSON object, no prose, no ``` fence:
{"name": "<short project name>",
 "summary": "<3-5 sentences: what gets built and how it works end to end>",
 "architecture": "<the layers or modules, what each owns, and the allowed dependency direction>",
 "decisions": ["<a choice that shapes the code: library, pattern, data flow, state handling, error model>"],
 "risks": [{"req": "<FR-n>", "why": "<why it is the hardest or least known: native or FFI code, media, network, concurrency, performance, a library nobody in the project used yet>"}],
 "deferred": [{"req": "<FR-n>", "why": "<what exactly is missing that makes it impossible to deliver in this build>"}],
 "wiring": [{"req": "<FR-n>", "action": "<what the user does>", "code": "<the functions that run, file by file>", "shows": "<what the user then sees, and in which file it is drawn or printed>"}],
 "examples": [{"req": "<FR-n>", "input": "<exactly what the user does, in order>", "expect": "<exactly what they then see>"}],
 "files":[{"path": "<relative path>",
            "purpose": "<what this file does and the behaviour it is responsible for, 1-2 sentences>",
            "exports": ["<Name(signature) — the contract others rely on: initial state, return values, errors, units>"],
            "verifies": "<tests only: the behaviours from SPEC.md this test proves>",
            "docs": ["spec", "stack", "design", "agents"],
            "needs": ["<a planned path this file imports or calls>"]}]}
Rules:
- Follow STACK.md's project layout and conventions exactly: one file = one responsibility, small files.
- Order files so every file comes after the files it needs (domain first, then adapters/UI, the entry point last). Include the manifest (go.mod, package.json, Cargo.toml, pubspec.yaml…) first, with no dependency versions you are unsure of: the package manager resolves them.
- `risks`: the 1-3 requirements most likely to fail (the hardest, the least known: native/FFI code, media, network, concurrency, performance, a library the project never used), riskiest first. Order the files so the thinnest REAL path through the first risk (its engine or adapter, one real use of it, a test that proves it) comes right after the manifest and before the layers that only present or store things (screens, onboarding, templates, settings, themes). A project whose hard part is built last is not built.
- Never plan a placeholder, stub, mock engine or sample-data stand-in for a requirement SPEC.md's Goals call core: plan the real thing, or list the requirement in `deferred` with exactly what is missing. A stand-in is allowed only for something SPEC.md does not ask for.
- `exports`: every name another file will call, with the behaviour it promises (e.g. "NewKeypad(unicode bool) Keypad — the highlight starts on the = button"; "Evaluate(expr string) (float64, error) — returns ErrDivisionByZero for x/0"). Two files that touch the same behaviour must agree here.
- `verifies` (tests): name the SPEC.md requirements (FR-n) the test proves.
- `wiring`: one row per SPEC.md requirement and edge case the user meets, from their action to what they see. Every row ends in a file that shows it (a view, a page, printed output); a domain function no row reaches the user through is not finished. State the user needs mid-flow (what they typed, a pending operation, a selection) is shown too, not only the final result.
- `examples`: SPEC.md made exact, 8-20 rows: every main flow, every edge case it lists, and what is on screen mid-flow (after each kind of input, not only the final result). Each row is the exact input (keys, clicks, arguments) and exactly what the user sees. Where SPEC.md leaves a choice open (an open question: precedence, rounding, an error text), decide it here once. These rows are the behaviour: tests assert exactly them and the code satisfies exactly them, so a test and the code can never disagree.
- `docs`: only the documents that file really needs (UI files need "design"; domain files rarely do).
- `needs`: every planned file whose API this file imports or calls, wherever it is in the list (the files are reordered so each comes after what it needs).
- Dependencies are one way: two files never need each other, and in Go two packages (folders) never import each other (Go refuses import cycles). A parent package that composes child packages (a root model that owns screens) never shares its styles, keys or messages with them through itself: what both use lives in its own package that both import.
- Every screen or component that DESIGN.md styles gets the style files STACK.md's styling approach needs, next to it (CSS Modules: one `name.module.css` per view; plain CSS: one stylesheet per feature, loaded by the page; utility classes: none), and the page loads every stylesheet: what the user sees must match DESIGN.md (sizes, layout, colors), not only work.
- Include tests where STACK.md says tests live, after the code they test. Include a short README.md last.
- Never plan files that tools generate: golden snapshots (*.golden), lockfiles (go.sum, package-lock.json, …), build output. The tests and the package manager write them.
- At most 25 files: the smallest project that satisfies SPEC.md.]]

--- What the plan does with the decisions earlier builds accepted (their ADRs)
M.DECISIONS_RULE =
  [[- <decisions> are the choices earlier builds accepted: follow them (libraries, patterns, layers, data flow) and never contradict one silently. List in `decisions` only choices that are new. When this build truly must reverse one, say it as a decision of its own: "Supersedes ADR NNNN: <the new choice> because <why>", and plan for the new choice.]]

--- The plan request. A layer build (scope.lua) adds its rules to the system prompt and the project's files as <project>.
---@param docs table<string, string> id → text
---@param scope string? "all" (default), "foundation", "domain", "design"
---@param existing table<string, string>? the project's files a layer builds on (path → text)
---@param task BuildTask? the requirement or recipe of a task scope (feature, recipe)
---@param decisions string? the <decisions> earlier builds accepted (adr.summary), followed unless one is superseded
---@return table req
function M.request(docs, scope, existing, task, decisions)
  local s = require("agent.kit.build.scope").get(scope)
  local rules = require("agent.kit.build.scope").rules(scope, task)
  local parts = {}
  for _, id in ipairs(M.DOCS) do
    if docs[id] then
      parts[#parts + 1] = ("<%s>\n%s\n</%s>"):format(id, vim.trim(docs[id]), id)
    end
  end
  local builds_on = s.existing or M.has_code(existing)
  if builds_on then
    parts[#parts + 1] = require("agent.kit.build.scope").project(existing or {})
  end
  if decisions and decisions ~= "" then
    parts[#parts + 1] = decisions
  end
  local system = SYSTEM
  if decisions and decisions ~= "" then
    system = system .. "\n" .. M.DECISIONS_RULE
  end
  if builds_on and not s.existing then
    system = system .. "\n" .. M.EXISTING_RULE
  end
  return {
    action = "kit_build_plan",
    tier = "main",
    timeout_ms = 300000, -- the whole contract of ~25 files is a long answer
    system = rules.plan
        and (system .. "\n\nScope of this build (it overrides the rules above where they differ):\n" .. rules.plan)
      or system,
    prompt = table.concat(parts, "\n\n") .. "\n\n" .. rules.ask,
  }
end

--- Files a tool writes, never the model: snapshots, lockfiles, build output (a plan that lists them wastes a request
--- and the model's version is wrong by construction)
---@param path string
---@return boolean
function M.generated(path)
  local base = vim.fs.basename(path)
  return path:match "%.golden$" ~= nil
    or path:match "%.snap$" ~= nil
    or vim.tbl_contains({
      "go.sum",
      "package-lock.json",
      "pnpm-lock.yaml",
      "yarn.lock",
      "bun.lock",
      "bun.lockb",
      "Cargo.lock",
      "uv.lock",
      "poetry.lock",
      "pubspec.lock",
    }, base)
    or path:match "^dist/" ~= nil
    or path:match "^build/" ~= nil
    or path:match "^node_modules/" ~= nil
end

--- Is a path safe to write under the project? (relative, no `..`, no home or drive)
---@param path string
---@return boolean
function M.safe(path)
  if type(path) ~= "string" or path == "" or #path > 200 then
    return false
  end
  if path:match "^/" or path:match "^~" or path:match "^%a:[/\\]" or path:find("\\", 1, true) then
    return false
  end
  for part in path:gmatch "[^/]+" do
    if part == ".." or part == "." then
      return false
    end
  end
  return not path:match "^%.git/" and path ~= ".git"
end

--- The wiring rows that say all four things (at most 30, each part capped)
---@param list any
---@return BuildWiring[]
function M.wiring(list)
  local out = {}
  local function str(v)
    return type(v) == "string" and vim.trim(v) ~= "" and (#v > 200 and (v:sub(1, 199) .. "…") or vim.trim(v)) or nil
  end
  for _, w in ipairs(type(list) == "table" and list or {}) do
    if type(w) == "table" and #out < 30 then
      local row = { req = str(w.req), action = str(w.action), code = str(w.code), shows = str(w.shows) }
      if row.req and row.action and row.code and row.shows then
        out[#out + 1] = row
      end
    end
  end
  return out
end

--- The examples that say all three things (at most 24, each part capped)
---@param list any
---@return BuildExample[]
function M.examples(list)
  local out = {}
  local function str(v)
    return type(v) == "string" and vim.trim(v) ~= "" and (#v > 240 and (v:sub(1, 239) .. "…") or vim.trim(v)) or nil
  end
  for _, e in ipairs(type(list) == "table" and list or {}) do
    if type(e) == "table" and #out < 24 then
      local row = { req = str(e.req) or "", input = str(e.input), expect = str(e.expect) }
      if row.input and row.expect then
        out[#out + 1] = row
      end
    end
  end
  return out
end

--- Rows of a list of { req, why } (risks, deferred): both parts non-empty, at most 8, capped
---@param list any
---@return { req: string, why: string }[]
function M.reasons(list)
  local out = {}
  local function str(v)
    return type(v) == "string" and vim.trim(v) ~= "" and (#v > 240 and (v:sub(1, 239) .. "…") or vim.trim(v)) or nil
  end
  for _, e in ipairs(type(list) == "table" and list or {}) do
    if type(e) == "table" and #out < 8 then
      local row = { req = str(e.req), why = str(e.why) }
      if row.req and row.why then
        out[#out + 1] = row
      end
    end
  end
  return out
end

--- Does the project already have code of its own? (a manifest, a document or a lockfile is not code)
---@param existing table<string, any>?
---@return boolean
function M.has_code(existing)
  local decls = require "agent.kit.decls"
  for path in pairs(existing or {}) do
    if decls.is_source(path) then
      return true
    end
  end
  return false
end

--- What a build of the whole project adds to its plan request when the project already has code: it was written by
--- earlier builds the new plan cannot see unless it is shown, and a plan that cannot see it writes it again
M.EXISTING_RULE =
  [[- The project already has code: <project> lists its files and <api> what they declare. Build on it. Use exactly the names <api> shows (never a name you remember from <decisions> or from the documents: those are intentions, <api> is what exists). Plan an existing file again only when it must change, with the same path and everything the rest of the project uses from it kept. Never plan a second version of something that already exists: not the same type under another folder, not the same screen under another name. When two existing files already say the same thing, plan the merge of them, not a third.]]

--- The request asked again, after a plan with problems: the plan it answered and what to correct
---@param req table the first plan request
---@param answer string the plan it answered
---@param problems string[]
---@return table
function M.again(req, answer, problems)
  local copy = vim.deepcopy(req)
  copy.prompt = req.prompt
    .. "\n\n<previous_plan>\n"
    .. vim.trim(answer)
    .. "\n</previous_plan>\n\nThat plan cannot be built as it is:\n- "
    .. table.concat(problems, "\n- ")
    .. "\nAnswer the whole corrected plan, same format: change only what these problems need."
  return copy
end

--- The plan from the model's answer, or nil and why
---@param text string
---@param existing table<string, any>? files already in the project (a layer build): a file may need them
---@param scope string? the build's scope, kept in the plan (prompt.lua adds its line to every file request)
---@return BuildPlan?, string?
function M.parse(text, existing, scope)
  existing = existing or {}
  if not (text or ""):find("{", 1, true) then
    return nil, "the answer has no JSON object"
  end
  local data = require("agent.kit.build.clean").json(text)
  if not data or type(data.files) ~= "table" then
    return nil, "the plan is not valid JSON with a `files` list"
  end
  local files, seen = {}, {}
  for _, f in ipairs(data.files) do
    if type(f) == "table" and M.safe(f.path) and not M.generated(f.path) and not seen[f.path] then
      seen[f.path] = true
      local docs = vim.tbl_filter(function(d)
        return vim.tbl_contains(M.DOCS, d)
      end, type(f.docs) == "table" and f.docs or {})
      local needs = vim.tbl_filter(function(p)
        return type(p) == "string" and p ~= f.path
      end, type(f.needs) == "table" and f.needs or {})
      local exports = {}
      for _, e in ipairs(type(f.exports) == "table" and f.exports or {}) do
        if type(e) == "string" and e ~= "" and #exports < 12 then
          exports[#exports + 1] = #e > 200 and (e:sub(1, 199) .. "…") or e
        end
      end
      files[#files + 1] = {
        path = f.path,
        purpose = type(f.purpose) == "string" and f.purpose or "",
        exports = exports,
        verifies = type(f.verifies) == "string" and f.verifies ~= "" and f.verifies or nil,
        docs = #docs > 0 and docs or { "spec", "stack" },
        needs = needs,
      }
    end
  end
  if #files == 0 then
    return nil, "the plan has no usable files"
  end
  -- every need kept (a file written without what it uses invents its API); one the plan does not have is a problem
  local planned, missing = {}, {}
  for _, f in ipairs(files) do
    planned[f.path] = true
  end
  for _, f in ipairs(files) do
    f.needs = vim.tbl_filter(function(p)
      if planned[p] or existing[p] ~= nil then -- planned, or already in the project (it is shown, not written)
        return true
      end
      if not M.generated(p) then
        missing[#missing + 1] = ("%s needs %s, which the plan does not have"):format(f.path, p)
      end
      return false
    end, f.needs)
  end
  local check = require "agent.kit.build.plancheck"
  files = check.order(files)
  if #files > M.MAX_FILES then
    return nil, ("the plan has %d files (max %d)"):format(#files, M.MAX_FILES)
  end
  local decisions = vim.tbl_filter(function(d)
    return type(d) == "string" and d ~= ""
  end, type(data.decisions) == "table" and data.decisions or {})
  local plan = {
    name = type(data.name) == "string" and data.name or "project",
    summary = type(data.summary) == "string" and data.summary or "",
    architecture = type(data.architecture) == "string" and data.architecture or "",
    decisions = vim.list_slice(decisions, 1, 12),
    risks = M.reasons(data.risks),
    deferred = M.reasons(data.deferred),
    wiring = M.wiring(data.wiring),
    examples = M.examples(data.examples),
    files = files,
    scope = scope and scope ~= "all" and scope or nil,
  }
  plan.problems = check.problems(plan, missing)
  return plan
end

-- ── The plan while it is being written ───────────────────────────────────────

--- The JSON string that starts at `pos` (just after its opening quote): its text, and where it ends; nil when it is not
--- complete yet
---@param text string
---@param pos integer
---@return string?, integer?
local function read_string(text, pos)
  local out, i = {}, pos
  while i <= #text do
    local c = text:sub(i, i)
    if c == '"' then
      return table.concat(out), i
    elseif c == "\\" then
      local n = text:sub(i + 1, i + 1)
      if n == "" then
        return nil
      end
      out[#out + 1] = ({ n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" })[n] or n
      i = i + 2
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
end

--- The value of `"key": "…"` after `from`, when complete
---@param text string
---@param key string
---@param from integer?
---@param to integer?
---@return string?
local function field(text, key, from, to)
  local _, e = text:find('"' .. key .. '"%s*:%s*"', from or 1)
  if not e or (to and e > to) then
    return nil
  end
  return (read_string(text, e + 1))
end

--- The complete strings of `"key": [ … ]` after `from`
---@param text string
---@param key string
---@param from integer
---@param to integer?
---@return string[]
local function list(text, key, from, to)
  local out = {}
  local _, e = text:find('"' .. key .. '"%s*:%s*%[', from)
  if not e or (to and e > to) then
    return out
  end
  local i = e + 1
  while true do
    local q = text:find('[%]"]', i)
    if not q or (to and q > to) or text:sub(q, q) == "]" then
      return out
    end
    local value, close = read_string(text, q + 1)
    if not value then
      return out
    end
    out[#out + 1] = value
    i = close + 1
  end
end

--- What the plan says so far, from the JSON the model is still writing (pure): the parts already complete, the files
--- whose path has arrived (with their purpose and contracts when those have too)
---@param text string
---@return BuildPlan
function M.partial(text)
  text = text or ""
  local files_at = text:find '"files"%s*:%s*%[' or #text + 1
  local plan = {
    name = field(text, "name", 1, files_at) or "",
    summary = field(text, "summary", 1, files_at) or "",
    architecture = field(text, "architecture", 1, files_at) or "",
    decisions = list(text, "decisions", 1, files_at),
    files = {},
  }
  local starts = {}
  local pos = files_at
  while true do
    local s, e = text:find('"path"%s*:%s*"', pos)
    if not s then
      break
    end
    starts[#starts + 1] = { s = s, e = e }
    pos = e + 1
  end
  for k, st in ipairs(starts) do
    local path = read_string(text, st.e + 1)
    if path then
      local to = starts[k + 1] and starts[k + 1].s or nil
      plan.files[#plan.files + 1] = {
        path = path,
        purpose = field(text, "purpose", st.e, to) or "",
        exports = list(text, "exports", st.e, to),
        verifies = field(text, "verifies", st.e, to),
        docs = list(text, "docs", st.e, to),
        needs = list(text, "needs", st.e, to),
      }
    end
  end
  return plan
end

return M
