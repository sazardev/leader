-- ── Build with agent: diagnose before fixing (pure) ──────────────────────────
-- When a check fails, one request looks at everything at once (the tool's output, the API of every file, the files the
-- errors name and the files they use) and says what is wrong and which files must change, with what, including files the
-- errors do not name (a test fails, the bug is in the code it tests). Each fix then carries that diagnosis. Without it a
-- fix only sees one file and the error, and "make the error go away" can mean weakening a test.
local prompt = require "agent.kit.build.prompt"

local M = {}

M.MAX_FILES = 6
M.MAX_NEW = 2 -- files a diagnosis may ask to create (an asset the code embeds, a config it reads)
local MAX_OUTPUT = 6000
local MAX_SHOWN = 40000

local TASK =
  [[A check of this project failed (its output is in <output>). Find the ROOT CAUSE across the files, then say what to change.
Output ONLY one JSON object, no prose, no ``` fence:
{"diagnosis": "<one or two sentences: what is wrong and why>", "files": [{"path": "<a path from the plan>", "change": "<concretely what to change in that file>"}]}
A file that does not exist yet and must (an asset or a config the code reads, `go:embed` or a loader finds missing) is listed with "new": true, its path relative to the project and its whole content described in "change"; never invent one when a planned file can hold it.
Rules:
- List every file that must change, including files the errors do not name when the cause is there (a test fails because the code it tests is wrong: change the code).
- A test whose expectation follows SPEC.md is right: never propose deleting or weakening assertions, waits or cases, nor skipping a test.
- Change a test only when the test itself is wrong (a wrong API, an expectation SPEC.md does not state).
- Files that tools generate (golden snapshots, lockfiles, generated code) are not yours to write: never list them nor ask to run a command; when such a file is the only cause, answer with "files": [].
- At most 6 files; only paths from the plan; the smallest change that fixes the cause.]]

---@param written table<string, string>
---@param paths string[]
---@return string
local function shown(written, paths)
  local out, used = {}, 0
  for _, p in ipairs(paths) do
    local text = written[p]
    if text and used + #text <= MAX_SHOWN then
      used = used + #text
      out[#out + 1] = ('<file path="%s">\n%s\n</file>'):format(p, text)
    end
  end
  return table.concat(out, "\n\n")
end

--- The request: the build's cached system prompt, then the output, the API, the files involved and the task
---@param output string the failing check's output
---@param blamed table<string, string[]> files the errors name (and the code a failing test uses)
---@param plan BuildPlan
---@param docs table<string, string>
---@param written table<string, string>
---@param user string? what using the app showed (the use phase), when this failure follows one of its fixes
---@return table req
function M.request(output, blamed, plan, docs, written, user)
  local paths = vim.tbl_keys(blamed)
  table.sort(paths)
  -- the files they use too: the cause is often one step away from where the error shows
  local seen = {}
  for _, p in ipairs(paths) do
    seen[p] = true
  end
  for _, f in ipairs(plan.files) do
    if blamed[f.path] then
      for _, n in ipairs(f.needs) do
        if not seen[n] then
          seen[n] = true
          paths[#paths + 1] = n
        end
      end
    end
  end
  if #output > MAX_OUTPUT then
    output = output:sub(1, MAX_OUTPUT) .. "\n…"
  end
  local parts = { "<output>\n" .. vim.trim(output) .. "\n</output>" }
  if user and user ~= "" then
    parts[#parts + 1] = "<user>\nThis failure follows a fix of what using the app showed (SPEC.md's behaviour as the user meets it):\n"
      .. vim.trim(user)
      .. "\nA test that expects the opposite of what the user must get locks the bug in: change that test's expectation to what SPEC.md says, never the code back.\n</user>"
  end
  local api = prompt.api(written)
  if api ~= "" then
    parts[#parts + 1] = api
  end
  local files = shown(written, paths)
  if files ~= "" then
    parts[#parts + 1] = files
  end
  parts[#parts + 1] = TASK
  return {
    action = "kit_build_diagnose",
    tier = "main",
    system = prompt.system(plan, docs), -- the same as every file request: read from the cache
    prompt = table.concat(parts, "\n\n"),
    cache = true,
  }
end

---@class BuildDiagnosis
---@field diagnosis string
---@field files { path: string, change: string, new: boolean? }[]

--- The diagnosis from the model's answer; nil when it is not usable (the fix then goes to the files the errors name)
---@param text string
---@param planned string[]
---@return BuildDiagnosis?
function M.parse(text, planned)
  local data = require("agent.kit.build.clean").json(text)
  if not data or type(data.files) ~= "table" then
    return nil
  end
  local known = {}
  for _, p in ipairs(planned) do
    known[p] = true
  end
  local files, seen, new = {}, {}, 0
  for _, f in ipairs(data.files) do
    local fresh = type(f) == "table"
      and f.new == true
      and not known[f.path]
      and require("agent.kit.build.plan").safe(f.path)
      and new < M.MAX_NEW
    if type(f) == "table" and (known[f.path] or fresh) and not seen[f.path] and #files < M.MAX_FILES then
      seen[f.path] = true
      files[#files + 1] = { path = f.path, change = type(f.change) == "string" and f.change or "", new = fresh or nil }
      new = new + (fresh and 1 or 0)
    end
  end
  if #files == 0 then
    return nil
  end
  return { diagnosis = type(data.diagnosis) == "string" and data.diagnosis or "", files = files }
end

return M
