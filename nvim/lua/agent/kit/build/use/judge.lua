-- ── Build with agent · use: did the user get what SPEC.md promises? (pure) ──
-- Two levels. Free: every frame is checked against its step (the texts it must and must not show, the exit code, a step
-- the driver could not do, a crash, an action with no visible effect). Then one request reads every scenario as the user
-- lived it (each step, what SPEC.md expected, what the checks found, the screen) and answers like a diagnosis: what is
-- wrong for the user and which files change, with what. A failed free check is never overruled by the model.
local diagnose = require "agent.kit.build.diagnose"
local prompt = require "agent.kit.build.prompt"

local M = {}

M.MAX_CHARS = 48000

---@class UseFrame
---@field step integer      0 = the screen it starts on
---@field did string
---@field screen string
---@field image string?     a screenshot (web, android), for you; the model reads the text
---@field error string?     the step could not be done (element not found, unknown key)
---@field exit integer?     cli: the exit code
---@field failures string[]? what the free checks found
---@field unchanged boolean? the step changed nothing on screen

---@class UseResult
---@field scenario UseScenario
---@field frames UseFrame[]
---@field error string?    the scenario could not run at all
---@field failures integer

---@param text string
---@return string
local function norm(text)
  return ((text or ""):lower():gsub("%s+", " "))
end

--- What a crash looks like on a screen
local CRASH = {
  "%[exited with [1-9]%d*%]",
  "\npanic: ",
  "^panic: ",
  "goroutine %d+ %[running%]",
  "Traceback %(most recent call last%)",
  "thread '[^']+' panicked",
  "Unhandled exception",
  "Uncaught %u%a+Error",
  "FATAL EXCEPTION",
}

--- The free checks of one frame against its step (pure): the failures, in words the fix can act on
---@param step UseStep?
---@param frame UseFrame
---@param previous UseFrame?
---@return string[]
function M.check(step, frame, previous)
  local out = {}
  local screen = norm(frame.screen)
  if frame.error then
    out[#out + 1] = "the step could not be done: " .. frame.error
  end
  for _, pat in ipairs(CRASH) do
    if (frame.screen or ""):find(pat) then
      out[#out + 1] = "the app crashed or exited with an error"
      break
    end
  end
  if step then
    for _, s in ipairs(step.see or {}) do
      if not screen:find(norm(s), 1, true) then
        out[#out + 1] = ("%q is not on the screen"):format(s)
      end
    end
    for _, s in ipairs(step.not_see or {}) do
      -- a digit or a symbol is on every keypad: only a real text can be "must not show"
      if #vim.trim(s) >= 3 and screen:find(norm(s), 1, true) then
        out[#out + 1] = ("%q is on the screen and must not be"):format(s)
      end
    end
    if step.exit and frame.exit and step.exit ~= frame.exit then
      out[#out + 1] = ("exit code %d, SPEC.md implies %d"):format(frame.exit, step.exit)
    end
  end
  frame.unchanged = step ~= nil
    and previous ~= nil
    and step["do"] ~= "wait"
    and step["do"] ~= "run"
    and previous.screen == frame.screen
  return out
end

--- Applies the free checks to a scenario's frames (frame k is step k; frame 0 is the start)
---@param scenario UseScenario
---@param frames UseFrame[]
---@return integer failures
function M.score(scenario, frames)
  local n = 0
  local by_step = {}
  for _, f in ipairs(frames) do
    by_step[f.step] = f
  end
  for _, f in ipairs(frames) do
    f.failures = M.check(scenario.steps[f.step], f, f.step > 0 and by_step[f.step - 1] or nil)
    n = n + #f.failures
  end
  return n
end

---@param results UseResult[]
---@return integer passed, integer total
function M.tally(results)
  local passed = 0
  for _, r in ipairs(results) do
    if not r.error and r.failures == 0 then
      passed = passed + 1
    end
  end
  return passed, #results
end

--- A screen for the model: runs of 3+ blank rows become one line that counts them (the layout stays readable, the
--- tokens of an 80×24 terminal that is mostly empty do not)
---@param screen string
---@return string
function M.compact(screen)
  local out, blanks = {}, 0
  local function flush()
    if blanks >= 3 then
      out[#out + 1] = ("⋮ %d blank rows"):format(blanks)
    else
      for _ = 1, blanks do
        out[#out + 1] = ""
      end
    end
    blanks = 0
  end
  for line in ((screen or "") .. "\n"):gmatch "([^\n]*)\n" do
    if vim.trim(line) == "" then
      blanks = blanks + 1
    else
      flush()
      out[#out + 1] = line
    end
  end
  blanks = 0 -- the blank rows below the last line say nothing
  return table.concat(out, "\n")
end

--- What a step changed on a screen, as its rows ("row 9: │ 12 + │", "row 12 gone"), when that is much shorter than the
--- screen (most steps change a display line or two: the rest, a keypad or a page, is not sent again); nil otherwise
---@param before string
---@param after string
---@return string?
function M.delta(before, after)
  local a = vim.split(before or "", "\n", { plain = true })
  local b = vim.split(after or "", "\n", { plain = true })
  local out = {}
  for row = 1, math.max(#a, #b) do
    if a[row] ~= b[row] then
      if b[row] == nil then
        out[#out + 1] = ("row %d gone"):format(row)
      else
        out[#out + 1] = ("row %d: %s"):format(row, b[row])
      end
    end
  end
  if #out == 0 or #out * 2 > #b then
    return nil
  end
  return "only these rows changed (the rest as in the step before):\n" .. table.concat(out, "\n")
end

--- Every scenario as the user lived it; when it does not fit, the screens of steps that passed (and did change
--- something) are left out first
---@param results UseResult[]
---@param brief boolean
---@return string
local function transcript(results, brief)
  local out = {}
  for i, r in ipairs(results) do
    local sc = r.scenario
    local head = ('<scenario n="%d" name="%s"%s%s>'):format(
      i,
      sc.name:gsub('"', "'"),
      #sc.covers > 0 and (' covers="' .. table.concat(sc.covers, " ") .. '"') or "",
      (sc.size or sc.viewport) and (' size="' .. (sc.size or sc.viewport) .. '"') or ""
    )
    out[#out + 1] = head
    if r.error then
      out[#out + 1] = "The scenario could not run: " .. r.error
    end
    local last
    for _, f in ipairs(r.frames or {}) do
      local step = sc.steps[f.step]
      out[#out + 1] = ("step %d · %s"):format(f.step, f.did or "?")
      if step and step.expect ~= "" then
        out[#out + 1] = "expected: " .. step.expect
      end
      if f.failures and #f.failures > 0 then
        out[#out + 1] = "checks FAILED: " .. table.concat(f.failures, "; ")
      end
      local passed = not f.failures or #f.failures == 0
      if f.unchanged then
        out[#out + 1] = "(the screen did not change: the action had no visible effect)"
      elseif brief and passed and f.step > 0 and f.screen == last then
        out[#out + 1] = "(screen as above)"
      elseif brief and passed and f.step > 0 then
        out[#out + 1] = "(screen left out: its checks passed)"
      else
        local delta = last and f.step > 0 and M.delta(last, f.screen)
        if delta then
          out[#out + 1] = "<changed>\n" .. delta .. "\n</changed>"
        else
          local shown = M.compact(f.screen)
          out[#out + 1] = "<screen>\n" .. (shown ~= "" and shown or "(empty)") .. "\n</screen>"
        end
      end
      last = f.screen
    end
    out[#out + 1] = "</scenario>"
  end
  return table.concat(out, "\n")
end

local TASK =
  [[You are the user of this app and its designer at once. Above is what happened when each scenario was tried: every step, what SPEC.md expected, what the automatic checks found and the screen right after.
Judge it like a demanding user:
1. Does every step do what SPEC.md says? A failed check is a real failure.
2. Can the user always tell what is going on: what they entered, a pending operation or choice, the result, an error with what to do next? Does every action give visible feedback?
3. Does every screen follow DESIGN.md at the size it was shown: layout, alignment, frames, help line, nothing cut off, overlapping or out of the window?
4. Is something the plan built (see <unwired>) missing from what the user can reach?
<api> lists every declaration of the project and <code> shows a selection of its files: a file or function not shown in <code> still exists; never conclude something is missing because it is not shown.
When something fails, read <code> (what turns the user's actions into behaviour and draws the result) and find WHERE the chain breaks: a control wired to a name no handler knows, a handler never registered, a state the view never draws, the logic itself. Name that file, not only the one the symptom suggests.
Output ONLY one JSON object, no prose, no ``` fence:
{"verdict": "pass" | "fail", "issues": [{"scenario": <n>, "step": <n>, "severity": "blocker" | "major" | "minor", "problem": "<what the user meets>"}], "diagnosis": "<the root causes in one or two sentences>", "files": [{"path": "<a path from the plan>", "change": "<concretely what to change in that file>"}]}
Rules:
- blocker: a SPEC.md behaviour does not work or cannot be reached. major: the user cannot tell what happened, or DESIGN.md's layout is broken. minor: polish.
- "files" fixes the blockers and majors (minors only when the same file changes anyway); "verdict" is "pass" only with none of them.
- A failure the scenario caused (a step no user would do, input SPEC.md does not ask the app to accept, an expectation SPEC.md does not state) is not the app's fault: report it as minor and change no code for it.
- Change code, never tests or golden files; keep every behaviour SPEC.md states; the smallest changes that fix the causes, at most 6 files, only paths from the plan.]]

--- The request: the build's cached system prompt, what the plan built that nobody reaches, the scenarios lived, the task
---@param results UseResult[]
---@param unwired string facts from wiring.lua (values and behaviours nobody uses), "" when none
---@param plan BuildPlan
---@param docs table<string, string>
---@param code string? the files that wire the interface (scenario.controls), "" or nil when none
---@param api string? every declaration of the project (prompt.api)
---@return table req
function M.request(results, unwired, plan, docs, code, api)
  local text = transcript(results, false)
  if #text > M.MAX_CHARS then
    text = transcript(results, true)
  end
  if #text > M.MAX_CHARS then
    text = text:sub(1, M.MAX_CHARS) .. "\n…"
  end
  local parts = {}
  if unwired ~= "" then
    parts[#parts + 1] = "<unwired>\n" .. unwired .. "\n</unwired>"
  end
  if code and code ~= "" then
    parts[#parts + 1] = "<code>\n" .. code .. "\n</code>"
  end
  if api and api ~= "" then
    parts[#parts + 1] = api
  end
  parts[#parts + 1] = text
  parts[#parts + 1] = TASK
  return {
    action = "kit_build_use",
    tier = "main",
    system = prompt.system(plan, docs),
    prompt = table.concat(parts, "\n\n"),
    cache = true,
  }
end

---@class UseVerdict
---@field pass boolean
---@field issues { scenario: integer, step: integer, severity: string, problem: string }[]
---@field diagnosis string
---@field files { path: string, change: string }[]

--- The verdict from the model's answer (nil when unusable). Free failures make it a fail whatever the model says.
---@param text string
---@param planned string[]
---@param failures integer free checks failed
---@return UseVerdict?
function M.parse(text, planned, failures)
  local data = require("agent.kit.build.clean").json(text)
  if not data then
    return nil
  end
  local issues = {}
  for _, i in ipairs(type(data.issues) == "table" and data.issues or {}) do
    if type(i) == "table" and type(i.problem) == "string" and #issues < 20 then
      issues[#issues + 1] = {
        scenario = tonumber(i.scenario) or 0,
        step = tonumber(i.step) or 0,
        severity = (i.severity == "blocker" or i.severity == "major") and i.severity or "minor",
        problem = i.problem,
      }
    end
  end
  local files = {}
  local d = diagnose.parse(text, planned)
  for _, f in ipairs(d and d.files or {}) do
    if not require("agent.kit.build.verify").is_test(f.path) and not f.path:match "%.golden$" then
      files[#files + 1] = f
    end
  end
  local serious = vim.iter(issues):any(function(i)
    return i.severity ~= "minor"
  end)
  return {
    pass = failures == 0 and not serious and data.verdict ~= "fail",
    issues = issues,
    diagnosis = type(data.diagnosis) == "string" and data.diagnosis or "",
    files = files,
  }
end

return M
