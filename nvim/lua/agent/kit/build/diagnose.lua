-- ── Build with agent: diagnose before fixing (pure) ──────────────────────────
-- When a check fails, one request looks at everything at once (the tool's output, the API of every file, the files the
-- errors name, the files they use and the files the check reads) and answers with a verdict: `fix` (which files must
-- change, with what, including files the errors do not name), `check` (the check's premise is false, so no project file
-- must change to satisfy it) or `none` (nothing can safely change). Each fix then carries that diagnosis. Without it a
-- fix only sees one file and the error, and "make the error go away" can mean weakening a test or inventing a dependency.
local prompt = require "agent.kit.build.prompt"

local M = {}

M.MAX_FILES = 6
M.MAX_NEW = 2 -- files a diagnosis may ask to create (an asset the code embeds, a config it reads)
local MAX_OUTPUT = 6000
local MAX_SHOWN = 40000

local TASK = [[A check of this project failed (its output is in <output>). Find the ROOT CAUSE, then say what to change.
Output ONLY one JSON object, no prose, no ``` fence:
{"verdict": "fix" | "check" | "none", "diagnosis": "<one or two sentences: what is wrong and why>", "files": [{"path": "<a path from the plan>", "change": "<concretely what to change in that file>"}]}
- "fix": project files must change. List every file that must change, including files the errors do not name when the cause is there (a test fails because the code it tests is wrong: change the code).
- "check": the check's premise is false (the documents do not say what it claims, a false positive in the check itself). Put nothing in "files": no project file must change to make a wrong check pass. Quote the row or sentence that proves it.
- "none": no project file can safely change (a missing external artifact, a decision only the user can make). Put nothing in "files" and say why.
A check that is wrong is a real answer, not a failure: answer "check" with the exact contradiction.
A file that does not exist yet and must (an asset or a config the code reads, `go:embed` or a loader finds missing) is listed with "new": true, its path relative to the project and its whole content described in "change"; never invent one when a planned file can hold it.
Rules:
- A test whose expectation follows SPEC.md is right: never propose deleting or weakening assertions, waits or cases, nor skipping a test.
- Change a test only when the test itself is wrong (a wrong API, an expectation SPEC.md does not state).
- Files that tools generate (golden snapshots, lockfiles, generated code) are not yours to write: never list them nor ask to run a command; when such a file is the only cause, answer "none" with "files": [].
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
---@param read string[]? files the failed check judges (its manifest, its page), shown whole even when no line names them
---@param previous string? what earlier rounds tried for the same failure
---@return table req
function M.request(output, blamed, plan, docs, written, user, read, previous)
  local paths = vim.tbl_keys(blamed)
  -- the files they use too: the cause is often one step away from where the error shows
  local seen = {}
  for _, p in ipairs(paths) do
    seen[p] = true
  end
  for _, p in ipairs(read or {}) do
    if written[p] and not seen[p] then
      seen[p] = true
      paths[#paths + 1] = p
    end
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
  table.sort(paths)
  if #output > MAX_OUTPUT then
    output = output:sub(1, MAX_OUTPUT) .. "\n…"
  end
  local parts = { "<output>\n" .. vim.trim(output) .. "\n</output>" }
  if user and user ~= "" then
    parts[#parts + 1] = "<user>\nThis failure follows a fix of what using the app showed (SPEC.md's behaviour as the user meets it):\n"
      .. vim.trim(user)
      .. "\nA test that expects the opposite of what the user must get locks the bug in: change that test's expectation to what SPEC.md says, never the code back.\n</user>"
  end
  if previous and previous ~= "" then
    parts[#parts + 1] = "<previous>\nWhat earlier rounds tried for this same failure (do not repeat a change that did not help):\n"
      .. vim.trim(previous)
      .. "\n</previous>"
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
---@field verdict "fix"|"check"|"none"
---@field diagnosis string
---@field files { path: string, change: string, new: boolean? }[]

--- The role of a file in a fix round: "test" for a test; "subject" only when a failing test named it (the code that
--- test exercises); nil when the file is its own fix (a missing config or asset the diagnosis named)
---@param path string
---@param roles table<string, string> the roles a failing test's `needs` gave
---@param is_test boolean
---@return string?
function M.role(path, roles, is_test)
  return is_test and "test" or roles[path]
end

--- The same request again, after an answer that was not the JSON asked for (once: a broken answer is not a verdict)
---@param req table
---@param why string
---@return table
function M.again(req, why)
  local copy = vim.deepcopy(req)
  copy.cache = false -- the cached answer is the bad one
  copy.prompt = req.prompt
    .. ('\n\nYour previous answer could not be used: %s. Answer again with ONLY the JSON object, with "verdict" (fix, check or none), "diagnosis" and "files".'):format(
      why
    )
  return copy
end

--- The diagnosis from the model's answer; nil when it is not usable (the fix then goes to the files the errors name)
---@param text string
---@param planned string[]
---@return BuildDiagnosis?
function M.parse(text, planned)
  local data = require("agent.kit.build.clean").json(text)
  if not data then
    return nil
  end
  if type(data.files) ~= "table" then
    if data.verdict == "check" or data.verdict == "none" then
      data.files = {} -- a verdict that changes nothing needs no file list
    else
      return nil
    end
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
  local verdict = data.verdict
  if verdict ~= "fix" and verdict ~= "check" and verdict ~= "none" then
    verdict = #files > 0 and "fix" or "none" -- an older answer without a verdict: the files say what it meant
  end
  if verdict ~= "fix" then
    files = {} -- a wrong check or a missing artifact is not fixed by editing the project
  elseif #files == 0 then
    verdict = "none"
  end
  local diagnosis = type(data.diagnosis) == "string" and vim.trim(data.diagnosis) or ""
  if #files == 0 and diagnosis == "" then
    return nil
  end
  return { verdict = verdict, diagnosis = diagnosis, files = files }
end

return M
