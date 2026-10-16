-- ── Build with agent: the plan (pure) ────────────────────────────────────────
-- One request turns the four documents into an ordered list of files: path, what it does, which documents it needs and
-- which earlier files it must see. Small steps, so each file request carries only what it needs. Tested in test-kit.lua.
local M = {}

M.MAX_FILES = 40
M.DOCS = { "agents", "stack", "design", "spec" }

---@class BuildFile
---@field path string
---@field purpose string
---@field docs string[]   which of agents/stack/design/spec it needs
---@field needs string[]  earlier files of the plan it must see

---@class BuildPlan
---@field name string
---@field files BuildFile[]

local SYSTEM = [[You plan how a coding agent builds a project from its documents, one small file at a time.
Output ONLY one JSON object, no prose, no ``` fence:
{"name": "<short project name>", "files": [{"path": "<relative path>", "purpose": "<one line: what this file holds>", "docs": ["spec", "stack", "design", "agents"], "needs": ["<earlier path>"]}]}
Rules:
- Follow STACK.md's project layout and conventions exactly: one file = one responsibility, small files.
- Order files so every file comes after the files it needs (domain first, then adapters/UI, the entry point last). Include the manifest (go.mod, package.json, Cargo.toml, pubspec.yaml…) first, with no dependency versions you are unsure of: the package manager resolves them.
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
      files[#files + 1] = {
        path = f.path,
        purpose = type(f.purpose) == "string" and f.purpose or "",
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
  return { name = type(data.name) == "string" and data.name or "project", files = files }
end

return M
