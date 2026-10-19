-- ── The troubleshooting request and its answer ───────────────────────────────
-- Pure. The request is built from the evidence (each piece in its own tag, stable parts first); the answer is ONE JSON object
-- (a diagnosis: summary, cause, confidence, ordered steps, and optionally `need`: more evidence it wants to look at). The parser
-- is strict about the shape and forgiving about the dress (fences, chatter around the object), and it marks dangerous commands so
-- the interface asks twice.
local M = {}

M.SYSTEM = [[You are a senior engineer diagnosing why a project fails to build, start or run. You get evidence in tags: <problem> what the user says, <source> where the output came from, <output> what the tool printed (cut around the errors), <code> files of the project the failure points into (line numbers, `>` on the failing line), <environment> toolchain versions, <changes> what git says changed lately, <known> what free checks already found (build on it, do not repeat it), <tried> what was already attempted (never suggest it again), <tool_results> what you asked to look at, <question> a follow-up.
Find the ROOT cause, not the symptom: read the FIRST error, not the cascade after it. Separate what the evidence shows from what you infer, and give an honest confidence ("high" only when the evidence shows it). Never invent file contents, versions, environment values, secrets or APIs: when you need something, ask for it in "need". Prefer the smallest fix: a command the user can run, or an edit to a file you saw. Commands must be safe and non-destructive (no rm -rf, no force pushes, no dropping data, no sudo unless installing a missing system package, and then say so in why); a fix that is destructive or needs a decision is a "manual" step that says so.
OUTPUT: ONE JSON object and nothing else:
{"summary":"one sentence a person reads first","cause":"2-5 sentences: the root cause and how the evidence shows it","confidence":"high|medium|low","steps":[{"title":"short, imperative","kind":"command|edit|manual","run":"the command (command)","file":"path relative to the project (edit)","line":12,"instruction":"exactly what to change and why (edit)","why":"one sentence"}],"need":[]}
At most 6 steps, in the order to do them. "need" only when you cannot conclude without more evidence (then steps may be empty). Language: English.]]

---@class DoctorEvidence
---@field problem string?
---@field source string?
---@field output string?
---@field code { path: string, lnum: integer, text: string }[]?
---@field versions table<string, string>?
---@field changes string?
---@field known DoctorFinding[]?
---@field tried string[]?
---@field tool_results { call: string, text: string }[]?
---@field question string?

---@param tag string
---@param text string?
---@return string
local function block(tag, text)
  if not text or vim.trim(text) == "" then
    return ""
  end
  return ("<%s>\n%s\n</%s>\n"):format(tag, vim.trim(text), tag)
end

--- The versions as "name: value" lines (the sorted ones; `*_missing` says a tool is absent)
---@param versions table<string, string>?
---@return string
function M.environment(versions)
  local lines = {}
  local names = vim.tbl_keys(versions or {})
  table.sort(names)
  for _, name in ipairs(names) do
    local v = versions[name]
    if name:match "_missing$" then
      lines[#lines + 1] = ("%s: NOT INSTALLED"):format(name:gsub("_missing$", ""))
    elseif name == "docker_error" then
      lines[#lines + 1] = "docker daemon: " .. v
    else
      lines[#lines + 1] = ("%s: %s"):format(name, v)
    end
  end
  return table.concat(lines, "\n")
end

---@param known DoctorFinding[]?
---@return string
local function known_text(known)
  local out = {}
  for _, f in ipairs(known or {}) do
    local steps = vim.tbl_map(function(s)
      return s.run or s.note or s.title
    end, f.steps or {})
    out[#out + 1] = ("- %s: %s%s"):format(f.title, f.cause, #steps > 0 and (" Suggested: " .. table.concat(steps, "; ")) or "")
  end
  return table.concat(out, "\n")
end

--- The request for the evidence (stable parts first, the volatile ones last)
---@param ev DoctorEvidence
---@param tools string? the description of what it may ask for (nil when no more rounds are left)
---@return { action: string, tier: string, system: string, prompt: string, timeout_ms: integer }
function M.request(ev, tools)
  local code = {}
  for _, c in ipairs(ev.code or {}) do
    code[#code + 1] = ("%s:%d\n%s"):format(c.path, c.lnum, c.text)
  end
  local results = {}
  for _, r in ipairs(ev.tool_results or {}) do
    results[#results + 1] = ("%s\n%s"):format(r.call, r.text)
  end
  local prompt = block("environment", M.environment(ev.versions))
    .. block("changes", ev.changes)
    .. block("source", ev.source)
    .. block("code", table.concat(code, "\n\n"))
    .. block("output", ev.output)
    .. block("known", known_text(ev.known))
    .. block("tried", table.concat(ev.tried or {}, "\n"))
    .. block("tool_results", table.concat(results, "\n\n"))
    .. block("problem", ev.problem)
    .. block("question", ev.question)
    .. "Diagnose it: answer with the JSON object."
  return {
    action = "doctor",
    tier = "main",
    system = M.SYSTEM .. (tools and ("\n" .. tools) or ""),
    prompt = prompt,
    timeout_ms = 240000,
  }
end

--- Commands that destroy, rewrite history, pipe the network into a shell or open permissions wide
local DANGER = {
  "rm%s+%-[%a]*[rf]",
  "git%s+push%s+.*%-%-force",
  "git%s+push%s+%-f",
  "git%s+reset%s+%-%-hard",
  "git%s+clean%s+%-[%a]*f",
  "drop%s+database",
  "drop%s+table",
  "truncate%s+table",
  "mkfs",
  "dd%s+if=",
  "chmod%s+%-R%s+777",
  "curl[^|]*|%s*%a*sh",
  "wget[^|]*|%s*%a*sh",
  "sudo%s+rm",
  ">%s*/dev/sd",
  "docker%s+system%s+prune",
  "docker%s+volume%s+rm",
  "%-%-no%-preserve%-root",
}

--- Does a command destroy something?
---@param cmd string
---@return boolean
function M.dangerous(cmd)
  local low = cmd:lower()
  for _, pat in ipairs(DANGER) do
    if low:find(pat) then
      return true
    end
  end
  return false
end

---@class DoctorPlanStep
---@field title string
---@field kind "command"|"edit"|"manual"
---@field run string?
---@field file string?
---@field line integer?
---@field instruction string?
---@field why string?
---@field danger boolean?
---@field state "pending"|"done"|"failed"|nil

---@class DoctorDiagnosis
---@field summary string
---@field cause string
---@field confidence "high"|"medium"|"low"
---@field steps DoctorPlanStep[]
---@field need { tool: string, path: string?, from: integer?, to: integer?, pattern: string?, cmd: string? }[]

local TOOLS = { read = true, search = true, list = true, run = true }

--- The diagnosis in a model's answer; nil and why when it is not one
---@param text string
---@return DoctorDiagnosis?, string?
function M.parse(text)
  local data = require("agent.kit.build.clean").json(text)
  if not data then
    return nil, "the answer was not a diagnosis (no JSON object)"
  end
  if type(data.cause) ~= "string" or vim.trim(data.cause) == "" then
    if not (type(data.need) == "table" and #data.need > 0) then
      return nil, "the diagnosis has no cause"
    end
  end
  local steps = {}
  for _, s in ipairs(type(data.steps) == "table" and data.steps or {}) do
    if type(s) == "table" and type(s.title) == "string" then
      local kind = s.kind
      if kind == "command" and type(s.run) == "string" and vim.trim(s.run) ~= "" then
        steps[#steps + 1] = {
          title = s.title,
          kind = "command",
          run = vim.trim(s.run),
          why = type(s.why) == "string" and s.why or nil,
          danger = M.dangerous(s.run) or nil,
        }
      elseif kind == "edit" and type(s.file) == "string" and type(s.instruction) == "string" then
        steps[#steps + 1] = {
          title = s.title,
          kind = "edit",
          file = s.file,
          line = tonumber(s.line),
          instruction = s.instruction,
          why = type(s.why) == "string" and s.why or nil,
        }
      else
        steps[#steps + 1] = {
          title = s.title,
          kind = "manual",
          instruction = type(s.instruction) == "string" and s.instruction or (type(s.run) == "string" and s.run or nil),
          why = type(s.why) == "string" and s.why or nil,
        }
      end
    end
  end
  local need = {}
  for _, n in ipairs(type(data.need) == "table" and data.need or {}) do
    if type(n) == "table" and TOOLS[n.tool] and #need < 4 then
      need[#need + 1] = n
    end
  end
  local confidence = data.confidence
  return {
    summary = type(data.summary) == "string" and data.summary or "",
    cause = type(data.cause) == "string" and data.cause or "",
    confidence = (confidence == "high" or confidence == "low") and confidence or "medium",
    steps = vim.list_slice(steps, 1, 6),
    need = need,
  }
end

--- A tool call as one line (what the model is shown next to the result)
---@param call table
---@return string
function M.call_label(call)
  if call.tool == "read" then
    return ("read %s %s-%s"):format(call.path or "?", call.from or 1, call.to or "")
  elseif call.tool == "search" then
    return ("search `%s`"):format(call.pattern or "?")
  elseif call.tool == "list" then
    return ("list %s"):format(call.path or ".")
  end
  return "$ " .. (call.cmd or "?")
end

return M
