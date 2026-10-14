-- ── Output protocol ──────────────────────────────────────────────────────────
-- What the model must return and how it is read. The rules (which go into the prompt) and the
-- parsers live TOGETHER on purpose: if one changes, the other changes with it.
-- It is plain text, not JSON: it works the same on all backends and copes with a model
-- that rambles better than with a half-closed JSON.
local M = {}

M.REPLACE_RULES = [=[
OUTPUT: one fenced block with the COMPLETE new <target> (same indentation); then, only if needed, one or both lines:
needs-import: <imports>
note: <max 15 words: what you assumed or added that is absent from the context, e.g. a field that does not exist>
The block is the final answer: no draft, no second block, no prose. Change only what the task needs; keep names, signatures and comments.]=]

M.APPEND_RULES = [=[
OUTPUT: one fenced block with ONLY the new code, which is appended after what <target> already holds (never repeat <target> or any existing code); then, only if needed, one or both lines:
needs-import: <imports>
note: <max 15 words: what you assumed that is absent from the context>
The block is the final answer: no draft, no second block, no prose.]=]

M.FINDINGS_RULES = [[
OUTPUT, one finding per line, nothing else: L<line>|<error|warn|info>|<problem and fix, max 140 chars>
<line> = the absolute line number shown in <target>. At most 8, worst first. Real defects only (bugs, wrong edge cases, unhandled errors, races, leaks, security): no style, no praise. Nothing real: OK]]

M.REVIEW_FILES_RULES = [[
OUTPUT, one finding per line, nothing else: <path>:<line>|<error|warn|info>|<problem and fix, max 140 chars>
<path> is the `## path` of the file; <line> is the number after `+L` of an ADDED line (or ` L` of a context line). At most 10, worst first. Real defects in the CHANGED code only (bugs, wrong edge cases, unhandled errors, races, leaks, security, a change that breaks what calls it): no style, no praise. Nothing real: OK]]

---@param lines string[]
---@return boolean
local function has_fence(lines)
  for _, l in ipairs(lines) do
    if l:match "^%s*```" then
      return true
    end
  end
  return false
end

---@param lines string[]
---@return string
local function first_content(lines)
  for _, l in ipairs(lines) do
    if l:match "%S" then
      return vim.trim(l)
    end
  end
  return ""
end

--- Closed blocks of the response, in order: { open, close } (fence indices)
---@param lines string[]
---@return { open: integer, close: integer }[]
local function blocks_of(lines)
  local blocks, i = {}, 1
  while i <= #lines do
    if lines[i]:match "^%s*```" then
      local j = i + 1
      while j <= #lines and not lines[j]:match "^%s*```%s*$" do
        j = j + 1
      end
      if j > #lines then
        break
      end
      blocks[#blocks + 1] = { open = i, close = j }
      i = j + 1
    else
      i = i + 1
    end
  end
  return blocks
end

--- The code of the response and the imports it says it needs.
--- If the model disobeys and sends several blocks (draft + corrected version), the
--- LAST one that starts like the target is used; if none does, the first. A target that already contains
--- fences (markdown) does not allow this split: there the block goes from the first fence to the last.
---@param response string
---@param target_lines string[]? the original code (to choose among several blocks)
---@return string[]? code, string? needs_import, string? err, integer? blocks, string? note
function M.extract_code(response, target_lines)
  local lines = vim.split(response, "\n", { plain = true })
  local chosen, count

  if target_lines and has_fence(target_lines) then
    local open
    for i, l in ipairs(lines) do
      if l:match "^%s*```" then
        open = i
        break
      end
    end
    if open then
      for i = #lines, open + 1, -1 do
        if lines[i]:match "^%s*```%s*$" then
          chosen, count = { open = open, close = i }, 1
          break
        end
      end
    end
  else
    local blocks = blocks_of(lines)
    count = #blocks
    chosen = blocks[1]
    if target_lines and count > 1 then
      local head = first_content(target_lines)
      for k = count, 1, -1 do
        if first_content(vim.list_slice(lines, blocks[k].open + 1, blocks[k].close - 1)) == head then
          chosen = blocks[k]
          break
        end
      end
    end
  end

  if not chosen then
    local opened = has_fence(lines)
    return nil,
      nil,
      opened and "the code block was never closed (truncated response?)" or "the response has no code block"
  end

  local code = vim.list_slice(lines, chosen.open + 1, chosen.close - 1)
  local needs, note
  for i = chosen.close + 1, #lines do
    needs = needs or lines[i]:match "^%s*needs%-import:%s*(.-)%s*$"
    note = note or lines[i]:match "^%s*note:%s*(.-)%s*$"
  end
  if note == "" or (note and note:lower():match "^[%W]*none[%W]*$") then
    note = nil
  end
  if needs and needs:lower():match "^[%W]*none[%W]*$" or needs == "-" or needs == "" then
    needs = nil
  end
  return code, needs, nil, count, note
end

local SEVERITY = {
  error = vim.diagnostic.severity.ERROR,
  warn = vim.diagnostic.severity.WARN,
  warning = vim.diagnostic.severity.WARN,
  info = vim.diagnostic.severity.INFO,
  hint = vim.diagnostic.severity.HINT,
}

---@class AgentFinding
---@field line integer
---@field severity integer
---@field message string

--- Findings `L<n>|<sev>|<msg>`; lines that do not match the format are ignored
---@param response string
---@return AgentFinding[]
function M.parse_findings(response)
  local list = {}
  for line in response:gmatch "[^\r\n]+" do
    local n, sev, msg = line:match "^%s*[Ll](%d+)%s*|%s*(%a+)%s*|%s*(.-)%s*$"
    if n and msg ~= "" then
      list[#list + 1] = { line = tonumber(n), severity = SEVERITY[sev:lower()] or SEVERITY.info, message = msg }
    end
  end
  return list
end

M.PLAN_RULES = [[
OUTPUT, one step per line, nothing else: <n>|<path>|<symbol>|<what to change, max 20 words>
<path> and <symbol> exactly as listed in <sites> (symbol = the function, method or type name). Order the steps so that what other steps depend on comes first (types and signatures before the code that uses them). Only steps that need a change; at most 12. Nothing needs to change: OK]]

--- A plan: `n|path|symbol|what` per line
---@param response string
---@return { n: integer, path: string, symbol: string, what: string }[]
function M.parse_plan(response)
  local list = {}
  for line in response:gmatch "[^\r\n]+" do
    local n, path, symbol, what = line:match "^%s*(%d+)%s*|%s*([^|]-)%s*|%s*([^|]-)%s*|%s*(.-)%s*$"
    if n and path ~= "" and symbol ~= "" and what ~= "" then
      list[#list + 1] = { n = tonumber(n), path = path, symbol = symbol, what = what }
    end
  end
  return list
end

--- Findings across files: `path:line|sev|message` per line
---@param response string
---@return { path: string, line: integer, severity: integer, message: string }[]
function M.parse_file_findings(response)
  local list = {}
  for line in response:gmatch "[^\r\n]+" do
    local path, n, sev, msg = line:match "^%s*([^|]-):(%d+)%s*|%s*(%a+)%s*|%s*(.-)%s*$"
    if path and msg ~= "" then
      list[#list + 1] = {
        path = vim.trim(path),
        line = tonumber(n),
        severity = SEVERITY[sev:lower()] or SEVERITY.info,
        message = msg,
      }
    end
  end
  return list
end

--- Is the response the findings protocol's "all good"?
---@param response string
---@return boolean
function M.is_ok(response)
  return vim.trim(response):upper() == "OK"
end

return M
