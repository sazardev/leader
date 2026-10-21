-- ── What a finished build can honestly claim (pure, 0 tokens) ────────────────
-- "✓ built · checks pass" used to be the whole report, and checks are compilers and unit tests: they say the files agree with
-- each other, not that the product does what SPEC.md promises. A build of a video editor passed them with a preview that was
-- a labelled placeholder, no way to add a clip and no engine. So the closing line now says what is proven and what is not:
--
--   requirements   how many of SPEC.md's FR-n have a test that names them (coverage.lua), and which core ones have none
--   placeholders   code that says it is not real yet (TODO, UnimplementedError, "placeholder", "coming soon")
--   proof lost     requirements that had a test before this build and have none now
--   removed API    public declarations of the files this build rewrote or deleted that are gone
--
-- A requirement is CORE when SPEC.md's Goals cite it (ranges like "FR-1 to FR-15" included) or the line says `(core)`. A build
-- of the whole project, a feature or a recipe is judged ("◐ built" when anything above is open); a layer (foundation, design,
-- domain) only reports, because most requirements cannot be met by one layer. Tested in test-kit-honesty.lua.
local decls = require "agent.kit.decls"

local M = {}

---@class BuildProof
---@field total integer           requirements in SPEC.md
---@field proven integer          of them with a test that names them
---@field unproven string[]       ids without one
---@field core_unproven string[]  of those, the core ones
---@field regressions string[]    had a test before this build, none now
---@field placeholders { path: string, line: integer, text: string }[]
---@field lost string[]           public declarations that are gone ("Name (file)")

-- ── placeholders ─────────────────────────────────────────────────────────────

--- Lowercased fragments that make a line "not real yet"
local MARKERS = {
  "unimplementederror",
  "notimplementederror",
  "unimplemented!",
  "todo!",
  "not implemented",
  "not yet implemented",
  "coming soon",
  "placeholder",
  "stub implementation",
  "mock engine",
  "fake engine",
}

--- A UI toolkit's own `placeholder` (an input's hint) is not a stand-in for missing code
---@param low string lowercased line
---@return boolean
local function toolkit_placeholder(low)
  return low:find("placeholder=", 1, true) ~= nil
    or low:find("placeholder:", 1, true) ~= nil
    or low:find("::placeholder", 1, true) ~= nil
    or low:find("placeholders", 1, true) ~= nil
    or low:find("setplaceholder", 1, true) ~= nil
end

--- Is this line a TODO/FIXME in a comment?
---@param line string
---@return boolean
local function todo_comment(line)
  local comment = line:match "//%s*(.*)$"
    or line:match "#%s*(.*)$"
    or line:match "/%*%s*(.*)$"
    or line:match "^%s*%*%s*(.*)$"
  if not comment then
    return false
  end
  local c = comment:lower()
  return c:match "^todo%f[%W]" ~= nil or c:match "^fixme%f[%W]" ~= nil or c:match "^hack%f[%W]" ~= nil
end

--- Code that says it is not real yet (pure). Tests, generated files and tool scaffolds are not scanned
---@param sources table<string, string> path → text
---@param max integer?
---@return { path: string, line: integer, text: string }[]
function M.placeholders(sources, max)
  local out = {}
  local paths = vim.tbl_keys(sources)
  table.sort(paths)
  for _, path in ipairs(paths) do
    if decls.is_source(path) then
      local n = 0
      for line in (sources[path] .. "\n"):gmatch "([^\n]*)\n" do
        n = n + 1
        local low = line:lower()
        local hit = todo_comment(line)
        if not hit and not toolkit_placeholder(low) then
          for _, m in ipairs(MARKERS) do
            if low:find(m, 1, true) then
              hit = true
              break
            end
          end
        end
        if hit then
          out[#out + 1] = { path = path, line = n, text = vim.trim(line):sub(1, 100) }
          if #out >= (max or 40) then
            return out
          end
        end
      end
    end
  end
  return out
end

-- ── core requirements ────────────────────────────────────────────────────────

--- The section of a Markdown document (without its heading), "" when absent
---@param text string
---@param title string
---@return string
local function section(text, title)
  return ("\n" .. (text or "") .. "\n## "):match("\n## " .. title .. "%s*\n(.-)\n## ") or ""
end

--- The ids SPEC.md's Goals cite, ranges expanded, plus the requirements marked `(core)` (pure)
---@param spec string
---@return table<string, boolean>
function M.core_ids(spec)
  local core = {}
  local goals = section(spec, "Goals")
  local function range(a, b)
    a, b = tonumber(a), tonumber(b)
    if a and b and b >= a and b - a <= 200 then
      for i = a, b do
        core["FR-" .. i] = true
      end
    end
  end
  for a, b in goals:gmatch "FR%-(%d+)%s*[–—%-]%s*FR%-(%d+)" do
    range(a, b)
  end
  for a, b in goals:gmatch "FR%-(%d+)%s+to%s+FR%-(%d+)" do
    range(a, b)
  end
  for id in goals:gmatch "FR%-%d+" do
    core[id] = true
  end
  for line in (spec or ""):gmatch "[^\n]+" do
    local id = line:match "^[%s#%-*|]*%**(FR%-%d+)"
    if id and (line:lower():find("(core)", 1, true) or line:lower():find("[core]", 1, true)) then
      core[id] = true
    end
  end
  return core
end

-- ── the summary ──────────────────────────────────────────────────────────────

--- The ids of the requirements a test names now (what "before" is made of)
---@param reqs CoverageReq[]
---@return string[]
function M.proven_ids(reqs)
  local out = {}
  for _, r in ipairs(reqs) do
    if #r.tests > 0 then
      out[#out + 1] = r.id
    end
  end
  return out
end

---@param reqs CoverageReq[]
---@param core table<string, boolean>
---@param before string[]? requirements a test named before this build
---@param placeholders { path: string, line: integer, text: string }[]
---@param lost string[]
---@return BuildProof
function M.summary(reqs, core, before, placeholders, lost)
  local proof = {
    total = #reqs,
    proven = 0,
    unproven = {},
    core_unproven = {},
    regressions = {},
    placeholders = placeholders or {},
    lost = lost or {},
  }
  local had = {}
  for _, id in ipairs(before or {}) do
    had[id] = true
  end
  for _, r in ipairs(reqs) do
    if #r.tests > 0 then
      proof.proven = proof.proven + 1
    else
      proof.unproven[#proof.unproven + 1] = r.id
      if core[r.id] then
        proof.core_unproven[#proof.core_unproven + 1] = r.id
      end
      if had[r.id] then
        proof.regressions[#proof.regressions + 1] = r.id
      end
    end
  end
  return proof
end

--- The public declarations the files in `baseline` had that are gone now (pure). `now` = path → current text (nil = deleted)
---@param baseline table<string, string>
---@param now table<string, string?>
---@return string[] "Name (file)"
function M.removed_api(baseline, now)
  local out = {}
  local paths = vim.tbl_keys(baseline)
  table.sort(paths)
  for _, path in ipairs(paths) do
    if decls.is_source(path) then
      local before = decls.of(path, baseline[path])
      local after = now[path] and decls.of(path, now[path]) or {}
      for _, name in ipairs(decls.lost(before, after)) do
        out[#out + 1] = ("%s (%s)"):format(name, path)
      end
    end
  end
  return out
end

--- "judged" for a build that is supposed to deliver requirements, "layer" for one that cannot
---@param scope string?
---@return "judged"|"layer"
function M.kind(scope)
  if scope == nil or scope == "all" or scope == "feature" or scope == "recipe" then
    return "judged"
  end
  return "layer"
end

--- Is the project proven complete as far as free checks can tell? "ok" or "partial"
---@param proof BuildProof
---@param scope string?
---@return "ok"|"partial"
function M.verdict(proof, scope)
  if M.kind(scope) == "layer" then
    return "ok"
  end
  if
    #proof.core_unproven > 0
    or #proof.unproven > 0
    or #proof.placeholders > 0
    or #proof.regressions > 0
    or #proof.lost > 0
  then
    return "partial"
  end
  return "ok"
end

---@param ids string[]
---@param max integer
---@return string
local function few(ids, max)
  if #ids <= max then
    return table.concat(ids, ", ")
  end
  return table.concat(vim.list_slice(ids, 1, max), ", ") .. (" +%d"):format(#ids - max)
end

--- What goes after "built · N files · checks pass": " · 5/17 requirements have a test · 2 placeholders"
---@param proof BuildProof
---@return string
function M.line(proof)
  local parts = {}
  if proof.total > 0 then
    parts[#parts + 1] = ("%d/%d requirements have a test"):format(proof.proven, proof.total)
  end
  if #proof.core_unproven > 0 then
    parts[#parts + 1] = ("core without one: %s"):format(few(proof.core_unproven, 3))
  end
  if #proof.placeholders > 0 then
    parts[#parts + 1] = ("%d placeholder%s"):format(#proof.placeholders, #proof.placeholders == 1 and "" or "s")
  end
  if #proof.regressions > 0 then
    parts[#parts + 1] = ("lost the test of %s"):format(few(proof.regressions, 3))
  end
  if #proof.lost > 0 then
    parts[#parts + 1] = ("removed %d public declaration%s"):format(#proof.lost, #proof.lost == 1 and "" or "s")
  end
  return #parts > 0 and (" · " .. table.concat(parts, " · ")) or ""
end

--- The closing line of a build: the icon says whether anything is open, the rest says what
---@param files integer
---@param proof BuildProof
---@param scope string?
---@return string
function M.outcome(files, proof, scope)
  local icon = M.verdict(proof, scope) == "ok" and "✓" or "◐"
  return ("%s built · %d files · checks pass%s"):format(icon, files, M.line(proof))
end

--- The lines PROGRESS.md's Open section gets from the proof
---@param proof BuildProof
---@return string[]
function M.open_lines(proof)
  local out = {}
  if #proof.core_unproven > 0 then
    out[#out + 1] = ("- core requirements no test names yet: %s"):format(table.concat(proof.core_unproven, ", "))
  end
  for i, p in ipairs(proof.placeholders) do
    if i > 8 then
      out[#out + 1] = ("- … and %d more placeholders"):format(#proof.placeholders - 8)
      break
    end
    out[#out + 1] = ("- not real yet: `%s:%d` %s"):format(p.path, p.line, p.text)
  end
  if #proof.regressions > 0 then
    out[#out + 1] = ("- requirements that lost their test in this build: %s"):format(
      table.concat(proof.regressions, ", ")
    )
  end
  if #proof.lost > 0 then
    out[#out + 1] = ("- public declarations removed by this build: %s"):format(few(proof.lost, 8))
  end
  return out
end

-- ── reading the project ──────────────────────────────────────────────────────

---@param root string
---@param baseline table<string, string>? the project's files before this build (path → text)
---@param before string[]? requirements proven before it
---@return BuildProof, CoverageReq[]
function M.collect(root, baseline, before)
  local coverage = require "agent.kit.coverage"
  local facts = coverage.collect(root)
  local report = coverage.report(facts)
  local now = {}
  local read = require("utils.project").read
  for path in pairs(baseline or {}) do
    now[path] = facts.sources[path] or read(root .. "/" .. path)
  end
  local core = M.core_ids(facts.docs.spec or "")
  local proof =
    M.summary(report.requirements, core, before, M.placeholders(facts.sources), M.removed_api(baseline or {}, now))
  return proof, report.requirements
end

return M
