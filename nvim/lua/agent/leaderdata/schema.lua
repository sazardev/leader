-- ── What may be written to .leader/, and nothing else (pure) ─────────────────
-- The folder exists so Leader can be measured and improved from real use: how builds end, which checks fail, what a model costs,
-- which actions people accept. It is NOT a copy of the work: no code, no prompts, no model answers, no file names, no diagnostics
-- text, no document text. That promise is enforced here, not by care at each call site: an event is passed through a schema,
-- and anything the schema does not name, or names with another type, or whose value is not one of the allowed ones, is dropped.
-- A new field is a line below, which is also the list of what is recorded (the README of the folder is generated from it).
--
--   num        a number (rounded)                  bool       true/false
--   id         8 hex digits (a random build id, or a salted hash: never reversible to a name)
--   model      "backend/model" (letters, digits, . - _ : / only, 60 at most)
--   ext        a file extension (letters and digits, 8 at most)
--   enum:a,b   one of the listed words, else "other"
--   { list = { field = type, … }, max = n }   a list of small records
local M = {}

local SCOPES = "all,foundation,design,domain,feature,recipe"
local TIERS = "main,light"
local ACTIONS =
  "implement,review,explain,ask,fix,fix_block,fixall,errors,errors_run,plan,docs,convert,next,refactor,handoff,verify_fix,plan_step,errors_fix"
local OUTCOMES = "done,error,cancelled,denied"
local DECISIONS = "accepted,rejected,refined,discarded"

---@type table<string, table<string, any>>
M.KINDS = {
  ["build.finish"] = {
    build = "id",
    scope = "enum:" .. SCOPES,
    outcome = "enum:done,partial,failed,stopped",
    strict = "bool",
    files = "num",
    files_done = "num",
    files_failed = "num",
    fix_rounds = "num",
    seconds = "num",
    requests = "num",
    tokens_in = "num",
    tokens_out = "num",
    tokens_cached = "num",
    cost = "num",
    tier_plan = "enum:" .. TIERS,
    tier_files = "enum:" .. TIERS,
    tier_fixes = "enum:" .. TIERS,
    tier_use = "enum:" .. TIERS,
    -- the plan
    risks = "num",
    deferred = "num",
    warnings = "num",
    problems = "num",
    existing = "num",
    replaced = "num",
    stale = "num",
    loss_lines = "num",
    loss_types = "num",
    -- the proof (agent/kit/build/proof.lua)
    req_total = "num",
    req_proven = "num",
    req_core_unproven = "num",
    placeholders = "num",
    regressions = "num",
    removed_api = "num",
    -- using the app
    use_total = "num",
    use_passed = "num",
    use_issues = "num",
    checks = { list = { label = "check", ok = "bool" }, max = 30 },
    per_file = {
      list = {
        id = "id",
        ext = "ext",
        lines = "enum:<50,<200,<500,500+",
        tokens_in = "num",
        tokens_out = "num",
        cost = "num",
        ms = "num",
        model = "model",
        state = "enum:done,failed,fixed,skipped,pending",
      },
      max = 60,
    },
  },
  ["agent.run"] = {
    run = "id",
    action = "enum:" .. ACTIONS,
    backend = "enum:claude,opencode,ollama,openai,command,replay,other",
    model = "model",
    tier = "enum:" .. TIERS,
    profile = "enum:small,medium,strong",
    outcome = "enum:" .. OUTCOMES,
    lang = "enum:dart,ts,go,rust,py,jvm,swift,lua,other",
    target_lines = "enum:<50,<200,<500,500+",
    tokens_in = "num",
    tokens_out = "num",
    cost = "num",
    ms = "num",
    calls = "num",
    steps = "num",
    escalated = "bool",
    cached = "bool",
  },
  ["agent.decision"] = {
    run = "id",
    action = "enum:" .. ACTIONS,
    decision = "enum:" .. DECISIONS,
  },
}

--- The check labels Leader itself knows (tool commands and the builder's own consistency checks): a project's own script name
--- is part of the project, so anything else is recorded as "custom"
local KNOWN_CHECKS = {
  "go mod tidy",
  "gofmt -l .",
  "go build ./...",
  "go vet ./...",
  "go test ./...",
  "cargo build",
  "cargo test",
  "flutter pub get",
  "flutter analyze",
  "flutter test",
  "dart pub get",
  "dart analyze",
  "dart test",
  "npm install",
  "pnpm install",
  "bun install",
  "yarn install",
  "tsc --noEmit",
  "uv sync",
  "compileall",
  "ruff check",
  "pytest",
  "no type is declared twice",
  "the interface uses what the plan exports",
  "package.json has STACK.md's tools",
  "every id the code looks up exists",
  "every control the page declares is handled",
  "every stylesheet and module is used",
} -- stylua: ignore

---@param label string
---@return string
function M.check_label(label)
  for _, known in ipairs(KNOWN_CHECKS) do
    if label == known then
      return label
    end
  end
  local pm, script = label:match "^(%w+) run (%w+)$"
  if
    pm
    and (script == "lint" or script == "build" or script == "test")
    and (pm == "npm" or pm == "pnpm" or pm == "bun" or pm == "yarn")
  then
    return label
  end
  return "custom"
end

--- One value through one type: the cleaned value, or nil when it must not be written
---@param kind any the schema's type
---@param value any
---@return any
local function clean(kind, value)
  if type(kind) == "table" then
    if type(value) ~= "table" then
      return nil
    end
    local out = {}
    for _, item in ipairs(value) do
      if type(item) == "table" and #out < (kind.max or 20) then
        local row = {}
        for field, ftype in pairs(kind.list) do
          local v = clean(ftype, item[field])
          if v ~= nil then
            row[field] = v
          end
        end
        if next(row) then
          out[#out + 1] = row
        end
      end
    end
    return out
  end
  if kind == "num" then
    return type(value) == "number" and value == value and math.abs(value) < 1e12 and math.floor(value * 1e5 + 0.5) / 1e5
      or nil
  elseif kind == "bool" then
    return type(value) == "boolean" and value or (value == false and false) or nil
  elseif kind == "id" then
    return type(value) == "string" and value:match "^%x%x%x%x%x%x%x%x$" and value or nil
  elseif kind == "model" then
    return type(value) == "string" and #value <= 60 and value:match "^[%w%._:/%-]+$" and value or nil
  elseif kind == "ext" then
    return type(value) == "string" and #value <= 8 and value:match "^%w+$" and value:lower() or nil
  elseif kind == "check" then
    return type(value) == "string" and M.check_label(value) or nil
  elseif type(kind) == "string" and kind:sub(1, 5) == "enum:" then
    if type(value) ~= "string" then
      return nil
    end
    for word in kind:sub(6):gmatch "[^,]+" do
      if word == value then
        return value
      end
    end
    return "other"
  end
  return nil
end

--- An event reduced to what the schema allows (pure). nil when the kind is unknown
---@param kind string
---@param fields table
---@return table?
function M.sanitize(kind, fields)
  local schema = M.KINDS[kind]
  if not schema then
    return nil
  end
  local out = {}
  for field, ftype in pairs(schema) do
    local v = clean(ftype, fields[field])
    if v ~= nil then
      out[field] = v
    end
  end
  return out
end

--- Every recorded field, for the README: "build.finish: build (id), scope, outcome…"
---@return string[]
function M.describe()
  local out = {}
  local kinds = vim.tbl_keys(M.KINDS)
  table.sort(kinds)
  for _, kind in ipairs(kinds) do
    local names = vim.tbl_keys(M.KINDS[kind])
    table.sort(names)
    out[#out + 1] = ("- `%s`: %s"):format(kind, table.concat(names, ", "))
  end
  return out
end

return M
