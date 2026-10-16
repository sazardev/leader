-- ── Build with agent: one small request per file (pure) ─────────────────────
-- Each file gets only the documents the plan said it needs, the plan's outline (paths and purposes, so names agree) and the
-- earlier files it uses. A fix gets the file, the tool's errors about it and the same context. The answer is the file alone.
local M = {}

local SYSTEM = [[You are a coding agent writing ONE file of a project, following its documents exactly.
Output ONLY the complete file content: no explanation, no ``` fence, nothing before or after.
Follow STACK.md (layout, conventions, rules for agents, engineering principles), DESIGN.md for anything the user sees, SPEC.md for behaviour, AGENTS.md for workflow rules.
Use only the APIs of the files you are shown and of the libraries STACK.md names; keep exported names consistent with the plan. Small, clear functions; no TODOs; no placeholder code.]]

---@param docs table<string, string>
---@param ids string[]
---@return string
local function doc_blocks(docs, ids)
  local out = {}
  local wanted = {}
  for _, id in ipairs(ids) do
    wanted[id] = true
  end
  -- always the same order (whatever order the plan listed them in): requests that share documents share a prefix the
  -- backend can cache
  for _, id in ipairs { "agents", "stack", "design", "spec" } do
    if wanted[id] and docs[id] then
      out[#out + 1] = ("<%s>\n%s\n</%s>"):format(id, vim.trim(docs[id]), id)
    end
  end
  return table.concat(out, "\n\n")
end

---@param plan BuildPlan
---@param current string
---@return string
local function outline(plan, current)
  local rows = {}
  for _, f in ipairs(plan.files) do
    rows[#rows + 1] = ("- %s: %s"):format(f.path, f.purpose) -- no "current" mark: identical in every request (cacheable)
  end
  return "<plan>\n" .. table.concat(rows, "\n") .. "\n</plan>"
end

---@param written table<string, string> path → content
---@param paths string[]
---@return string
local function files(written, paths)
  local out = {}
  for _, p in ipairs(paths) do
    if written[p] then
      out[#out + 1] = ('<file path="%s">\n%s\n</file>'):format(p, written[p])
    end
  end
  return table.concat(out, "\n\n")
end

--- Declarations that start at column 0 in the usual languages: what other files can call (Go func/type, TS/JS export,
--- Rust pub, Python def/class, Dart/Kotlin/Swift class/fun…)
local DECL = {
  "^func ",
  "^type ",
  "^export ",
  "^pub ",
  "^def ",
  "^class ",
  "^abstract class ",
  "^sealed class ",
  "^interface ",
  "^enum ",
  "^fun ",
  "^struct ",
  "^protocol ",
  "^extension ",
  "^mixin ",
}

--- The API of the files written so far: their top-level declarations (signatures, not bodies), so a file uses the names
--- that really exist even when it does not see the whole file. Cheap: a few hundred tokens for a small project.
---@param written table<string, string>
---@param skip string? the file being written or fixed (shown whole elsewhere, or not yet there)
---@return string
function M.api(written, skip)
  local paths = vim.tbl_keys(written)
  table.sort(paths)
  local out = {}
  for _, path in ipairs(paths) do
    if
      path ~= skip
      and not path:match "_test%.go$"
      and not path:match "%.md$"
      and not path:match "%.mod$"
      and not path:match "%.test%.[jt]s$"
    then
      local decls = {}
      for line in written[path]:gmatch "[^\n]+" do
        for _, pat in ipairs(DECL) do
          if line:match(pat) then
            decls[#decls + 1] = (line:gsub("%s*{%s*$", ""):gsub("%s+$", ""))
            break
          end
        end
        if #decls >= 40 then
          break
        end
      end
      if path:match "%.html?$" then -- the DOM contract: the ids scripts look up
        for id in written[path]:gmatch "%sid%s*=%s*[\"']([%w_%-:%.]+)[\"']" do
          decls[#decls + 1] = "#" .. id
          if #decls >= 60 then
            break
          end
        end
      end
      local pkg = written[path]:match "^package (%S+)" or written[path]:match "\npackage (%S+)"
      if #decls > 0 then
        out[#out + 1] = ("%s%s\n  %s"):format(
          path,
          pkg and (" (package " .. pkg .. ")") or "",
          table.concat(decls, "\n  ")
        )
      end
    end
  end
  if #out == 0 then
    return ""
  end
  return "<api>\nWhat the files written so far declare (use exactly these names):\n"
    .. table.concat(out, "\n")
    .. "\n</api>"
end

--- The system prompt of every file and fix request of a build: the instructions, ALL four documents (fixed order) and
--- the plan. Identical for the whole build, so the backend caches it once and every later request reads it at a tenth of
--- the price: cheaper than sending each file only its documents at full price (measured: subsets of documents per file
--- never hit the cache). The plan's per-file `docs` become the message's focus line instead.
---@param plan BuildPlan
---@param docs table<string, string>
---@return string
function M.system(plan, docs)
  return SYSTEM .. "\n\n" .. doc_blocks(docs, { "agents", "stack", "design", "spec" }) .. "\n\n" .. outline(plan, "")
end

--- "Focus on: SPEC.md, DESIGN.md" (what the plan said this file needs most)
---@param ids string[]
---@return string
function M.focus(ids)
  local names = { agents = "AGENTS.md", stack = "STACK.md", design = "DESIGN.md", spec = "SPEC.md" }
  return "Focus on: "
    .. table.concat(
      vim.tbl_map(function(id)
        return names[id] or id
      end, ids),
      ", "
    )
end

--- The request that writes one planned file
---@param file BuildFile
---@param plan BuildPlan
---@param docs table<string, string>
---@param written table<string, string>
---@return table req
function M.file(file, plan, docs, written)
  local system = M.system(plan, docs)
  local parts = { M.focus(file.docs) }
  local api = M.api(written, file.path)
  if api ~= "" then
    parts[#parts + 1] = api
  end
  local shown = files(written, file.needs)
  if shown ~= "" then
    parts[#parts + 1] = shown
  end
  parts[#parts + 1] = ("Write `%s`: %s"):format(file.path, file.purpose)
  return {
    action = "kit_build_file",
    tier = "main",
    system = system,
    prompt = table.concat(parts, "\n\n"),
    cache = true,
  }
end

--- The request that fixes a file the tools rejected
---@param path string
---@param content string
---@param errors string
---@param file BuildFile?
---@param plan BuildPlan
---@param docs table<string, string>
---@param written table<string, string>
---@return table req
function M.fix(path, content, errors, file, plan, docs, written)
  local system = M.system(plan, docs)
  local parts = { M.focus(file and file.docs or { "stack" }) }
  local api = M.api(written, path)
  if api ~= "" then
    parts[#parts + 1] = api
  end
  local shown = files(written, file and file.needs or {})
  if shown ~= "" then
    parts[#parts + 1] = shown
  end
  parts[#parts + 1] = ('<file path="%s">\n%s\n</file>'):format(path, content)
  parts[#parts + 1] = "<errors>\n" .. vim.trim(errors) .. "\n</errors>"
  parts[#parts + 1] = ("Fix `%s` so these errors are gone, using the names in <api> for what other files declare. Return the whole corrected file."):format(
    path
  )
  return { action = "kit_build_fix", tier = "main", system = system, prompt = table.concat(parts, "\n\n"), cache = true }
end

--- A model's answer as file content: the ``` fence some models still add, removed
---@param text string
---@return string
function M.content(text)
  text = (text or ""):gsub("^%s*\n", "")
  local inner = text:match "^```[%w_+%-]*\n(.-)\n```%s*$"
  return ((inner or text):gsub("%s+$", "")) .. "\n"
end

return M
