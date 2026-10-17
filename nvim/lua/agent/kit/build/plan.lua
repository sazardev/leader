-- ── Build with agent: the plan (pure) ────────────────────────────────────────
-- One request turns the four documents into the build's contract: how it works (summary, architecture, decisions) and an
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
---@field needs string[]  earlier files of the plan it must see
---@field exports string[] what other files use from it, each with its contract ("NewKeypad(unicode bool) Keypad — highlight starts on =")
---@field verifies string? tests: what behaviour they check

---@class BuildPlan
---@field name string
---@field summary string        how the project will be built, in a few sentences
---@field architecture string   layers and the direction of dependencies
---@field decisions string[]    the choices that shape the code (libraries, patterns, data flow)
---@field files BuildFile[]

local SYSTEM =
  [[You plan how a coding agent builds a project from its documents, one small file at a time. The plan is the
contract every file is then written against, so it must say what each file does and what it promises to the others.
Output ONLY one JSON object, no prose, no ``` fence:
{"name": "<short project name>",
 "summary": "<3-5 sentences: what gets built and how it works end to end>",
 "architecture": "<the layers or modules, what each owns, and the allowed dependency direction>",
 "decisions": ["<a choice that shapes the code: library, pattern, data flow, state handling, error model>"],
 "files": [{"path": "<relative path>",
            "purpose": "<what this file does and the behaviour it is responsible for, 1-2 sentences>",
            "exports": ["<Name(signature) — the contract others rely on: initial state, return values, errors, units>"],
            "verifies": "<tests only: the behaviours from SPEC.md this test proves>",
            "docs": ["spec", "stack", "design", "agents"],
            "needs": ["<earlier path>"]}]}
Rules:
- Follow STACK.md's project layout and conventions exactly: one file = one responsibility, small files.
- Order files so every file comes after the files it needs (domain first, then adapters/UI, the entry point last). Include the manifest (go.mod, package.json, Cargo.toml, pubspec.yaml…) first, with no dependency versions you are unsure of: the package manager resolves them.
- `exports`: every name another file will call, with the behaviour it promises (e.g. "NewKeypad(unicode bool) Keypad — the highlight starts on the = button"; "Evaluate(expr string) (float64, error) — returns ErrDivisionByZero for x/0"). Two files that touch the same behaviour must agree here.
- `verifies` (tests): name the SPEC.md requirements (FR-n) the test proves.
- `docs`: only the documents that file really needs (UI files need "design"; domain files rarely do).
- `needs`: only earlier files whose API this file uses.
- Every screen or component that DESIGN.md styles gets the style files STACK.md's styling approach needs, next to it (CSS Modules: one `name.module.css` per view; plain CSS: one stylesheet per feature, loaded by the page; utility classes: none), and the page loads every stylesheet: what the user sees must match DESIGN.md (sizes, layout, colors), not only work.
- Include tests where STACK.md says tests live, after the code they test. Include a short README.md last.
- At most 25 files: the smallest project that satisfies SPEC.md.]]

---@param docs table<string, string> id → text
---@return table req
function M.request(docs)
  local parts = {}
  for _, id in ipairs(M.DOCS) do
    if docs[id] then
      parts[#parts + 1] = ("<%s>\n%s\n</%s>"):format(id, vim.trim(docs[id]), id)
    end
  end
  return {
    action = "kit_build_plan",
    tier = "main",
    timeout_ms = 300000, -- the whole contract of ~25 files is a long answer
    system = SYSTEM,
    prompt = table.concat(parts, "\n\n") .. "\n\nPlan the files to build this project.",
  }
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

--- The plan from the model's answer, or nil and why
---@param text string
---@return BuildPlan?, string?
function M.parse(text)
  local json = (text or ""):match "%b{}"
  if not json then
    return nil, "the answer has no JSON object"
  end
  local ok, data = pcall(vim.json.decode, json)
  if not ok or type(data) ~= "table" or type(data.files) ~= "table" then
    return nil, "the plan is not valid JSON with a `files` list"
  end
  local files, seen = {}, {}
  for _, f in ipairs(data.files) do
    if type(f) == "table" and M.safe(f.path) and not seen[f.path] then
      seen[f.path] = true
      local docs = vim.tbl_filter(function(d)
        return vim.tbl_contains(M.DOCS, d)
      end, type(f.docs) == "table" and f.docs or {})
      local needs = vim.tbl_filter(function(p)
        return type(p) == "string" and seen[p] == true -- only files planned BEFORE it
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
  if #files > M.MAX_FILES then
    return nil, ("the plan has %d files (max %d)"):format(#files, M.MAX_FILES)
  end
  local decisions = vim.tbl_filter(function(d)
    return type(d) == "string" and d ~= ""
  end, type(data.decisions) == "table" and data.decisions or {})
  return {
    name = type(data.name) == "string" and data.name or "project",
    summary = type(data.summary) == "string" and data.summary or "",
    architecture = type(data.architecture) == "string" and data.architecture or "",
    decisions = vim.list_slice(decisions, 1, 12),
    files = files,
  }
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
