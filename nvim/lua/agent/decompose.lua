-- ── One instruction, several small steps ─────────────────────────────────────
-- A model that is told "rename it, then use a comprehension, then use sum()" tends to do two of the three. A smaller model
-- is far more reliable asked for ONE edit at a time, on the code the previous step produced. So when the instruction the
-- user typed is clearly several (a list, `;`-separated clauses, "then"), a profile with `decompose` runs it as a chain
-- on the SAME job: each step is one request over the current code, checked like any answer (agent/sampling.lua), and the
-- last one becomes the proposal, diffed against the ORIGINAL code, so accepting, undoing and verifying work as always.
-- Splitting is free (text rules, no model): the cost of a chain is that of its steps, and the budget guard sees all of them.
local protocol = require "agent.protocol"

local M = {}

local MAX_STEPS = 5

---@param s string
---@return string
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Splits on a separator that is not inside (), [], {}, quotes or backticks
---@param text string
---@param sep string one character
---@return string[]
local function split_top(text, sep)
  local parts, depth, quote, from = {}, 0, nil, 1
  for i = 1, #text do
    local c = text:sub(i, i)
    if quote then
      if c == quote then
        quote = nil
      end
    elseif c == '"' or c == "'" or c == "`" then
      quote = c
    elseif c == "(" or c == "[" or c == "{" then
      depth = depth + 1
    elseif c == ")" or c == "]" or c == "}" then
      depth = math.max(0, depth - 1)
    elseif c == sep and depth == 0 then
      parts[#parts + 1] = text:sub(from, i - 1)
      from = i + 1
    end
  end
  parts[#parts + 1] = text:sub(from)
  return parts
end

---@param parts string[]
---@return string[]
local function clean(parts)
  local out = {}
  for _, p in ipairs(parts) do
    p = trim(p):gsub("^[Aa]nd%s+", ""):gsub("^[Tt]hen%s+", ""):gsub("[%.;]+$", "")
    p = trim(p)
    if p ~= "" then
      out[#out + 1] = p
    end
  end
  return out
end

--- The steps an instruction is made of, or nil when it is one thing. Order is the order written
---@param input string?
---@return string[]?
function M.steps(input)
  if not input or not input:match "%S" then
    return nil
  end
  local text = trim(input)
  -- "do three things: …", "steps: …"
  text = trim(text:gsub("^[Dd]o%s+[%w]+%s+things?%s*:%s*", ""):gsub("^[Ss]teps?%s*:%s*", ""))

  local lines = vim.tbl_filter(function(l)
    return l:match "%S"
  end, vim.split(text, "\n", { plain = true }))
  local listed = vim.tbl_filter(function(l)
    return l:match "^%s*%d+[%.%)]%s+" or l:match "^%s*[%-%*]%s+"
  end, lines)
  local steps
  if #listed >= 2 then
    steps = clean(vim.tbl_map(function(l)
      return (l:gsub("^%s*%d+[%.%)]%s+", ""):gsub("^%s*[%-%*]%s+", ""))
    end, listed))
  else
    local flat = table.concat(lines, " ")
    steps = clean(split_top(flat, ";"))
    if #steps < 2 then
      -- "A, then B" / "A then B": only the word makes the split, a bare comma is part of a sentence
      steps = clean(vim.split((flat:gsub(",%s+then%s+", "\0"):gsub("%s+then%s+", "\0")), "\0", { plain = true }))
    end
  end
  if #steps < 2 then
    return nil
  end
  while #steps > MAX_STEPS do
    local last = table.remove(steps)
    steps[#steps] = steps[#steps] .. "; " .. last
  end
  return steps
end

--- Will this job run as a chain? Only an action that opts in (it takes an instruction and replaces code), with a profile that
--- decomposes and an instruction that is several things
---@param action table
---@param input string?
---@param profile AgentProfile?
---@return string[]? steps
function M.plan(action, input, profile)
  if not (action.decomposable and profile and profile.decompose) then
    return nil
  end
  return M.steps(input)
end

--- The instruction of step `i`: the whole request for context, then the one thing to do now
---@param full string
---@param steps string[]
---@param i integer
---@return string
function M.step_input(full, steps, i)
  local lines = {
    ("Overall request (context only): %s"):format(full),
    ("Do ONLY step %d of %d now: %s"):format(i, #steps, steps[i]),
  }
  if i > 1 then
    lines[#lines + 1] = "The earlier steps are already applied in <target>: keep them."
  end
  if i < #steps then
    lines[#lines + 1] = "The later steps come after this one: do not do them yet."
  end
  return table.concat(lines, "\n")
end

--- A job's chain moves on after a good answer. Returns "retry" when there is a next step (the job's prompt is already
--- the next one); on the last step it turns the result into the whole chain's answer and returns nil
---@param job AgentJob
---@param result table backend result: { text, usage }
---@return "retry"?
function M.advance(job, result)
  if not job.steps then
    return nil
  end
  local code, needs, _, _, note = protocol.extract_code(result.text, job.working or job.target.lines)
  if not code then
    return nil -- the checks before this already caught it; whatever is left is shown as it is
  end
  job.working = code
  job.needs = job.needs or {}
  if needs then
    job.needs[#job.needs + 1] = needs
  end
  job.note = note or job.note
  if job.step < #job.steps then
    job.step = job.step + 1
    job.attempt = 1
    local target = vim.tbl_extend("force", job.target, { lines = job.working })
    job.system, job.prompt =
      require("agent.prompt").build(job.action, target, job.sections, M.step_input(job.input, job.steps, job.step))
    job.base_prompt = job.prompt
    return "retry"
  end
  local out = { "```", table.concat(code, "\n"), "```" }
  if #job.needs > 0 then
    out[#out + 1] = "needs-import: " .. table.concat(job.needs, ", ")
  end
  if job.note then
    out[#out + 1] = "note: " .. job.note
  end
  result.text = table.concat(out, "\n")
  return nil
end

return M
