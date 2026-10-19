-- ── Build with agent: one small request per file (pure) ─────────────────────
-- Each file gets only the documents the plan said it needs, the plan's outline (paths and purposes, so names agree) and the
-- earlier files it uses. A fix gets the file, the tool's errors about it and the same context. The answer is the file alone.
local M = {}

local SYSTEM = [[You are a coding agent writing ONE file of a project, following its documents exactly.
Output ONLY the complete file content (a fix may ask for edit blocks instead: then only those): no explanation, no ``` fence, nothing before or after.
Follow STACK.md (layout, conventions, rules for agents, engineering principles), DESIGN.md for anything the user sees (when it has `## Screens` wireframes, they are the layout: alignment, centering, frames and sizes exactly as drawn; its `## Toolkit`, when present, says how to express it in code), SPEC.md for behaviour, AGENTS.md for workflow rules.
Use only the APIs of the files you are shown and of the libraries STACK.md names; keep exported names consistent with the plan. Small, clear functions; no TODOs; no placeholder code.
Built for a user, not for the tests: every behaviour SPEC.md states must reach the person using it through the path the plan's <wiring> gives (their action → the code → what they see). A screen always shows what the user needs for their next action: what they entered, a pending choice or operation, the result, an error with what to do next. A capability the plan exports for the interface is called by the interface; never leave it reachable only from tests.
Never write explanations, tags or tool-call markup into the file: its first character is the file's first character.]]

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
  -- the plan's whole contract (identical in every request: no "current" mark, so the backend caches it)
  local rows = {}
  if plan.summary and plan.summary ~= "" then
    rows[#rows + 1] = "Summary: " .. plan.summary
  end
  if plan.architecture and plan.architecture ~= "" then
    rows[#rows + 1] = "Architecture: " .. plan.architecture
  end
  if plan.decisions and #plan.decisions > 0 then
    rows[#rows + 1] = "Decisions:\n- " .. table.concat(plan.decisions, "\n- ")
  end
  if plan.wiring and #plan.wiring > 0 then
    rows[#rows + 1] = "Wiring (how each requirement reaches the user; every link must exist in the code):"
    for _, w in ipairs(plan.wiring) do
      rows[#rows + 1] = ("- %s: %s → %s → %s"):format(w.req, w.action, w.code, w.shows)
    end
  end
  rows[#rows + 1] = "Files (each exports what the others rely on; keep every promise):"
  for _, f in ipairs(plan.files) do
    rows[#rows + 1] = ("- %s: %s"):format(f.path, f.purpose)
    for _, e in ipairs(f.exports or {}) do
      rows[#rows + 1] = "    exports " .. e
    end
    if f.verifies then
      rows[#rows + 1] = "    verifies " .. f.verifies
    end
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
      local decls, count, comment = {}, 0, nil
      for line in (written[path] .. "\n"):gmatch "([^\n]*)\n" do
        -- the comment right above a declaration says what it promises ("the keypad opens on =", "returns nil when…"):
        -- the behaviour other files rely on, not only the signature
        local text = line:match "^%s*///?%s*(.-)%s*$"
          or line:match "^%s*/?%*+%s*(.-)%s*%*?/?$"
          or line:match "^%s*#%s+(.-)%s*$"
        local is_decl = false
        for _, pat in ipairs(DECL) do
          if line:match(pat) then
            is_decl = true
            break
          end
        end
        if is_decl then
          if comment and comment ~= "" then
            decls[#decls + 1] = "// " .. (#comment > 140 and (comment:sub(1, 139) .. "…") or comment)
          end
          decls[#decls + 1] = (line:gsub("%s*{%s*$", ""):gsub("%s+$", ""))
          count, comment = count + 1, nil
          if count >= 40 then
            break
          end
        elseif text and text ~= "" then
          comment = comment and (comment .. " " .. text) or text
        elseif not text then
          comment = nil
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
  local line = require("agent.kit.build.scope").rules(plan.scope, plan.task).file
  return SYSTEM
    .. (line and ("\n" .. line) or "")
    .. "\n\n"
    .. doc_blocks(docs, { "agents", "stack", "design", "spec" })
    .. "\n\n"
    .. outline(plan, "")
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
  if written[file.path] then -- already in the project (a layer build changes it): the new version keeps what others use
    parts[#parts + 1] = ('<current path="%s">\n%s\n</current>'):format(file.path, written[file.path])
    parts[#parts + 1] = ("`%s` already exists (above): answer with its whole new version, keeping what the rest of the project uses from it."):format(
      file.path
    )
  end
  parts[#parts + 1] = ("Write `%s`: %s"):format(file.path, file.purpose)
  if file.path:match "go%.mod$" then -- an invented pseudo-version stops every check; tidy writes the real ones
    parts[#parts + 1] =
      "Write only the module line and the go line: no require block (go mod tidy adds every dependency the code imports, with its real version)."
  end
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
---@param role "test"|"subject"|nil  a failing test, or the code a failing test exercises
---@param note string? the diagnosis of the failure and what to change in this file
function M.fix(path, content, errors, file, plan, docs, written, role, note)
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
  if note and note ~= "" then
    parts[#parts + 1] = "<diagnosis>\n" .. vim.trim(note) .. "\n</diagnosis>"
  end
  if role == "test" then
    parts[#parts + 1] = ("`%s` is a test and it fails. Fix the test only if the test itself is wrong (a wrong API, an expectation SPEC.md does not state). Never delete or weaken assertions, waits or cases to make it pass: when the expectation is right the bug is in the code it tests, which is sent separately; then this file is right as it is."):format(
      path
    )
  elseif role == "subject" then
    parts[#parts + 1] = ("A test that exercises `%s` fails with the errors above. If the bug is in this file, fix it so the test's expectation (which follows SPEC.md) holds; otherwise this file is right as it is. Use the names in <api> for what other files declare."):format(
      path
    )
  else
    parts[#parts + 1] = ("Fix `%s` so these errors are gone, using the names in <api> for what other files declare."):format(
      path
    )
  end
  if content == "" then -- a file the diagnosis asked to create
    parts[#parts + 1] = ("`%s` does not exist yet: answer with its whole content."):format(path)
  else
    parts[#parts + 1] = require("agent.kit.build.edits").FORMAT
  end
  return { action = "kit_build_fix", tier = "main", system = system, prompt = table.concat(parts, "\n\n"), cache = true }
end

--- A model's answer as file content: fences, echoed tags, leaked tool-call markup and chatter out (clean.lua)
---@param text string
---@param path string?
---@return string
function M.content(text, path)
  return require("agent.kit.build.clean").file(text, path)
end

--- The same request again, after an answer that was not a clean file: what was wrong, and the rule again
---@param req table
---@param why string
---@param whole boolean? edit blocks failed: this time the whole file (the blocks' format is the hard part for a weak model)
---@return table
function M.again(req, why, whole)
  local copy = vim.deepcopy(req)
  copy.cache = false -- the cached answer is the bad one
  copy.prompt = req.prompt
    .. ("\n\nYour previous answer could not be used: %s. %s no sentence, no fence, no tags."):format(
      why,
      whole and "This time answer with the WHOLE corrected file, every line of it, instead of edit blocks:"
        or "Answer again in exactly the format asked above:"
    )
  return copy
end

return M
