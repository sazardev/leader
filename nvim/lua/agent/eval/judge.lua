-- ── Judges: is the result any good? (pure) ───────────────────────────────────
-- Every judgement here is free and deterministic: no model grades another model. A case declares what it expects in its
-- `check` table; each key below is one question with a yes/no answer, and a result passes when every question the case
-- asked is a yes. The runner adds the one question that needs a process (`cmd`: a command that must exit 0).
--
--   outside      the lines around the target are byte-for-byte what they were (scope discipline: the weak-model failure
--                is rewriting what it was not asked to touch). On by default; `outside = false` opts out
--   contains     substrings that must appear in the new target
--   absent       substrings that must NOT appear in the new target
--   preserves    every code line the target had is still there, in order (docs: the comment changes, the code does not);
--                comment lines are not required to survive
--   findings     { { line, tol? } }: each needs a finding within `tol` (default 2) lines of `line`
--   max_findings the most findings that still counts as focused (a model that flags everything finds the bug by luck)
local M = {}

--- Do the lines around the target survive untouched? `first`/`last` = the target's range in `before` (1-based)
---@param before string[] whole buffer before
---@param after string[]  whole buffer after
---@param first integer
---@param last integer
---@return boolean
function M.outside_unchanged(before, after, first, last)
  for i = 1, first - 1 do
    if before[i] ~= after[i] then
      return false
    end
  end
  local tail = #before - last
  for k = 0, tail - 1 do
    if before[#before - k] ~= after[#after - k] then
      return false
    end
  end
  return #after >= (first - 1) + tail
end

--- The new target: what is between the untouched head and tail
---@param after string[]
---@param first integer
---@param tail integer lines after the target in the original
---@return string[]
function M.new_target(after, first, tail)
  return vim.list_slice(after, first, #after - tail)
end

---@param text string
---@param needles string[]
---@return boolean
function M.contains_all(text, needles)
  for _, needle in ipairs(needles or {}) do
    if not text:find(needle, 1, true) then
      return false
    end
  end
  return true
end

---@param text string
---@param needles string[]
---@return boolean
function M.contains_none(text, needles)
  for _, needle in ipairs(needles or {}) do
    if text:find(needle, 1, true) then
      return false
    end
  end
  return true
end

---@param line string
---@return boolean
local function comment_only(line)
  return line:match "^%s*#" ~= nil
    or line:match "^%s*//" ~= nil
    or line:match "^%s*%-%-" ~= nil
    or line:match "^%s*%*" ~= nil
end

--- Every code line of `original` shows up in `result`, in the same order (a subsequence)
---@param original string[]
---@param result string[]
---@return boolean
function M.preserves_code(original, result)
  local at = 1
  for _, line in ipairs(original) do
    if line:match "%S" and not comment_only(line) then
      local found
      for j = at, #result do
        if result[j] == line then
          found, at = true, j + 1
          break
        end
      end
      if not found then
        return false
      end
    end
  end
  return true
end

--- Is there a finding near each expected line?
---@param findings { line: integer }[]
---@param expected { line: integer, tol: integer? }[]
---@return boolean
function M.findings_near(findings, expected)
  for _, want in ipairs(expected or {}) do
    local hit = false
    for _, f in ipairs(findings) do
      if math.abs(f.line - want.line) <= (want.tol or 2) then
        hit = true
        break
      end
    end
    if not hit then
      return false
    end
  end
  return true
end

---@class AgentEvalSubject
---@field before string[]      whole buffer before
---@field after string[]       whole buffer after (equal to `before` when nothing was applied)
---@field first integer        target range in `before`
---@field last integer
---@field findings { line: integer }[]?

--- Answers every question the case's `check` asked, except `cmd`
---@param check table
---@param s AgentEvalSubject
---@return table<string, boolean> answers
function M.judge(check, s)
  check = check or {}
  local answers = {}
  local tail = #s.before - s.last
  if check.outside ~= false and not check.findings then
    answers.outside = M.outside_unchanged(s.before, s.after, s.first, s.last)
  end
  local new = M.new_target(s.after, s.first, tail)
  local text = table.concat(new, "\n")
  if check.contains then
    answers.contains = M.contains_all(text, check.contains)
  end
  if check.absent then
    answers.absent = M.contains_none(text, check.absent)
  end
  if check.preserves then
    answers.preserves = M.preserves_code(vim.list_slice(s.before, s.first, s.last), new)
  end
  if check.findings then
    answers.findings = M.findings_near(s.findings or {}, check.findings)
    if check.max_findings then
      answers.focused = #(s.findings or {}) <= check.max_findings
    end
  end
  -- a case that asks nothing of the result must at least have changed it: "no changes" is not a pass
  if not check.findings and check.changes ~= false then
    answers.changed = not vim.deep_equal(s.before, s.after)
  end
  return answers
end

--- A result passes when every answer is yes (and there is at least one)
---@param answers table<string, boolean>
---@return boolean
function M.passes(answers)
  local any = false
  for _, ok in pairs(answers) do
    any = true
    if not ok then
      return false
    end
  end
  return any
end

--- The questions that were answered no, sorted (what the report shows next to a failure)
---@param answers table<string, boolean>
---@return string[]
function M.failed(answers)
  local out = {}
  for name, ok in pairs(answers) do
    if not ok then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

return M
