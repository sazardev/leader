-- ── Build with agent · use: what a user will try, written before looking (pure)
-- One request turns SPEC.md (its flows, Given/When/Then and edge cases) and DESIGN.md (its sizes) into scenarios: steps
-- a driver can perform and what each step must show. The expectations come from the documents, never from the code (it
-- is shown only so the steps use the real keys, flags, routes and labels): tests written with the code agree with it,
-- these agree with the user. Asked once per build; every later round replays the same scenarios.
local prompt = require "agent.kit.build.prompt"

local M = {}

M.MAX_SCENARIOS = 8
M.MAX_STEPS = 14
local MAX_CONTROLS = 24000

--- The actions each kind of driver performs, as the model is told them (and as `parse` accepts them)
M.VOCAB = {
  tui = {
    actions = { type = { "text" }, key = { "key" }, resize = { "size" }, wait = { "ms" } },
    text = [[- {"do":"type","text":"12+3"}: types the characters, one key press each
- {"do":"key","key":"Enter"}: one named key: Enter, Esc, Tab, BTab, Up, Down, Left, Right, Backspace, Delete, Space, Home, End, PageUp, PageDown, F1-F12, C-a…C-z (Ctrl)
- {"do":"resize","size":"40x20"}: the terminal changes size
- {"do":"wait","ms":300}
A scenario may set "size": "80x24" (columns x rows, default 80x24): the terminal it starts in.]],
  },
  cli = {
    actions = { run = { "args" } },
    text = [[- {"do":"run","args":["--flag","value"],"stdin":"optional input","exit":0}: runs the program once with those arguments (and that standard input); "exit" is the exit code SPEC.md implies (0 success, non-zero for an error)
The arguments go to the program as they are, without a shell: never add shell quotes; one argument with spaces is one string (["2 + 3"] is one argument, ["2","+","3"] are three). Use the forms SPEC.md, STACK.md and DESIGN.md show.
Each step is a separate run; its screen is standard output + standard error.]],
  },
  web = {
    actions = {
      ["goto"] = { "path" },
      click = { "target" },
      fill = { "target", "value" },
      press = { "key" },
      select = { "target", "value" },
      check = { "target" },
      hover = { "target" },
      viewport = { "size" },
      wait = { "ms" },
    },
    text = [[- {"do":"goto","path":"/"}: opens a page of the app
- {"do":"click","target":{"role":"button","name":"Save"}}: clicks an element
- {"do":"fill","target":{"label":"Amount"},"value":"12"}: types into a field (replacing what it had)
- {"do":"press","key":"Enter"}: a key on the focused element (Enter, Escape, Tab, ArrowDown, Control+K…)
- {"do":"select","target":{"label":"Currency"},"value":"EUR"}, {"do":"check","target":{"label":"Remember me"}}, {"do":"hover","target":{"text":"Help"}}
- {"do":"viewport","size":"375x812"}: the window changes size (phone, tablet, desktop)
- {"do":"wait","ms":300}
A target is one of {"role":"button","name":"…"} (preferred: what a screen reader announces), {"label":"…"}, {"placeholder":"…"}, {"text":"…"}, {"testid":"…"}, {"css":"#id"}.
A scenario may set "viewport": "1280x800" (default). Its first step is usually goto "/".]],
  },
  electron = {
    actions = {
      click = { "target" },
      fill = { "target", "value" },
      press = { "key" },
      select = { "target", "value" },
      check = { "target" },
      hover = { "target" },
      wait = { "ms" },
    },
    text = [[- {"do":"click","target":{"role":"button","name":"Save"}}, {"do":"fill","target":{"label":"Amount"},"value":"12"}, {"do":"press","key":"Enter"}, {"do":"select",…}, {"do":"check",…}, {"do":"hover",…}, {"do":"wait","ms":300}
A target is one of {"role":"button","name":"…"}, {"label":"…"}, {"placeholder":"…"}, {"text":"…"}, {"testid":"…"}, {"css":"#id"}. The app's first window is open when the scenario starts.]],
  },
  android = {
    actions = { tap = { "target" }, type = { "text" }, key = { "key" }, swipe = { "direction" }, wait = { "ms" } },
    text = [[- {"do":"tap","target":{"text":"7"}}: taps an element by its text, {"id":"com.app:id/equals"} (resource id) or {"desc":"Clear"} (content description)
- {"do":"type","text":"12"}: types into the focused field
- {"do":"key","key":"BACK"}: BACK, ENTER, HOME, DEL, TAB
- {"do":"swipe","direction":"up"}: up, down, left, right
- {"do":"wait","ms":500}
The app is started fresh (its data cleared) before every scenario.]],
  },
}

local TASK =
  [[You will use this app as its user, through a driver that performs steps and reads the screen after each. Write the scenarios to try, from SPEC.md and DESIGN.md.
The driver can do:
%s

Output ONLY one JSON object, no prose, no ``` fence:
{"scenarios": [{"name": "<what the user tries>", "covers": ["FR-1"], %s"steps": [{"do": "...", "see": ["<text that must be on the screen after this step>"], "not_see": ["<text that must not be>"], "expect": "<what the user should see or get after this step, per SPEC.md/DESIGN.md>"}]}]}
Rules:
- Expectations come ONLY from SPEC.md and DESIGN.md: what the user must see, never what the code happens to do. The code above is there only so the steps use the app's real keys, flags, routes and labels.
- One scenario per main flow and per requirement the user meets (FR-n), plus the edge cases SPEC.md lists (invalid input, errors, empty states, limits) and the state the user needs mid-flow (what they typed, a pending choice or operation, a selection).
- `see`: short exact texts that must appear (a number, a label, a message); only what SPEC.md or DESIGN.md make certain. `not_see`: a specific text that must be gone (an error message, a stale result), never a lone digit or symbol the screen shows elsewhere (a keypad has every digit). Use `expect` for what cannot be checked as text (layout, alignment, what changed, how clear it is).
- When DESIGN.md names sizes (a minimum terminal, phone and desktop widths), include one scenario at the smallest supported size that checks the main screen fits and is usable.
- Every step has an `expect`; a step with nothing visible to check still says what the user should notice.
- At most %d scenarios of at most %d steps; steps that a user would really do, in order.]]

--- The files a scenario writer needs to operate the app: entry points, key/route/flag definitions, views (capped)
---@param written table<string, string>
---@param plan BuildPlan
---@return string
function M.controls(written, plan)
  local verify = require "agent.kit.build.verify"
  local purposes = {}
  for _, f in ipairs(plan.files or {}) do
    purposes[f.path] = f.purpose
  end
  local scored = {}
  for path, text in pairs(written) do
    if
      not verify.is_test(path)
      and not verify.is_manifest(path)
      and not path:match "%.md$"
      and not path:match "%.golden$"
    then
      local p = path:lower() .. " " .. (purposes[path] or ""):lower()
      local score = 0
      for _, w in ipairs {
        "key",
        "bind",
        "route",
        "cli",
        "flag",
        "arg",
        "command",
        "main",
        "app",
        "page",
        "view",
        "screen",
        "form",
        "button",
        "menu",
        "html",
        "layout",
      } do
        if p:find(w, 1, true) then
          score = score + 1
        end
      end
      -- the wiring first, then the rest of the code while it fits (a verdict that cannot see a file thinks it is missing)
      scored[#scored + 1] = { path = path, text = text, score = score }
    end
  end
  table.sort(scored, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return #a.text == #b.text and a.path < b.path or #a.text < #b.text
  end)
  local out, used = {}, 0
  for _, s in ipairs(scored) do
    if used + #s.text <= MAX_CONTROLS then
      used = used + #s.text
      out[#out + 1] = ('<file path="%s">\n%s\n</file>'):format(s.path, s.text)
    end
  end
  return table.concat(out, "\n\n")
end

--- The request: the build's cached system prompt (documents + plan + wiring), the code that says how to operate the app,
--- the driver's actions and the task
---@param kind string a key of VOCAB
---@param plan BuildPlan
---@param docs table<string, string>
---@param written table<string, string>
---@return table req
function M.request(kind, plan, docs, written)
  local parts = {}
  local api = prompt.api(written)
  if api ~= "" then
    parts[#parts + 1] = api
  end
  local controls = M.controls(written, plan)
  if controls ~= "" then
    parts[#parts + 1] = "How the app is operated (keys, flags, routes, labels):\n" .. controls
  end
  local size = (kind == "tui" and '"size": "80x24", ') or (kind == "web" and '"viewport": "1280x800", ') or ""
  parts[#parts + 1] = TASK:format(M.VOCAB[kind].text, size, M.MAX_SCENARIOS, M.MAX_STEPS)
  return {
    action = "kit_build_scenarios",
    tier = "main",
    system = prompt.system(plan, docs),
    prompt = table.concat(parts, "\n\n"),
    cache = true,
  }
end

---@class UseStep
---@field do string
---@field text string?   tui/android type
---@field key string?
---@field size string?
---@field ms integer?
---@field args string[]? cli
---@field stdin string?
---@field exit integer?
---@field path string?   web goto
---@field target table?  web/android
---@field value string?
---@field direction string?
---@field see string[]
---@field not_see string[]
---@field expect string

---@class UseScenario
---@field name string
---@field covers string[]
---@field size string?     tui: "80x24"
---@field viewport string? web: "1280x800"
---@field steps UseStep[]

---@param v any
---@return string[]
local function strings(v)
  local out = {}
  for _, s in ipairs(type(v) == "table" and v or {}) do
    if type(s) == "string" and vim.trim(s) ~= "" and #out < 8 then
      out[#out + 1] = s
    end
  end
  return out
end

---@param v any
---@return string?
local function size(v)
  return type(v) == "string" and v:match "^%d+x%d+$" and v or nil
end

--- One step, if the driver can do it (its action known, its fields there)
---@param kind string
---@param s table
---@return UseStep?
local function step(kind, s)
  if type(s) ~= "table" or type(s["do"]) ~= "string" then
    return nil
  end
  local spec = M.VOCAB[kind].actions[s["do"]]
  if not spec then
    return nil
  end
  local out = {
    ["do"] = s["do"],
    see = strings(s.see),
    not_see = strings(s.not_see),
    expect = type(s.expect) == "string" and s.expect or "",
  }
  for _, field in ipairs(spec) do
    local v = s[field]
    if field == "args" then
      if type(v) ~= "table" then
        v = {}
      end
      local args = {}
      for _, a in ipairs(v) do
        if type(a) == "string" or type(a) == "number" then
          args[#args + 1] = tostring(a)
        end
      end
      v = args
    elseif field == "target" then
      if type(v) ~= "table" or next(v) == nil then
        return nil
      end
    elseif field == "ms" then
      v = math.max(0, math.min(5000, tonumber(v) or 300))
    elseif field == "size" then
      v = size(v)
      if not v then
        return nil
      end
    elseif type(v) ~= "string" or v == "" then
      if field == "path" then
        v = "/"
      else
        return nil
      end
    end
    out[field] = v
  end
  if kind == "cli" then
    out.stdin = type(s.stdin) == "string" and s.stdin or nil
    out.exit = tonumber(s.exit)
  end
  if kind == "web" and s["do"] == "viewport" then
    out.size = size(s.size)
  end
  return out
end

--- The scenarios from the model's answer (the steps the driver cannot do dropped; a scenario left empty dropped); nil
--- when none is usable
---@param text string
---@param kind string
---@return UseScenario[]?
function M.parse(text, kind)
  local data = require("agent.kit.build.clean").json(text, { luanil = { object = true, array = true } })
  if not data or type(data.scenarios) ~= "table" then
    return nil
  end
  local out = {}
  for _, sc in ipairs(data.scenarios) do
    if type(sc) == "table" and #out < M.MAX_SCENARIOS then
      local steps = {}
      for _, s in ipairs(type(sc.steps) == "table" and sc.steps or {}) do
        local st = #steps < M.MAX_STEPS and step(kind, s)
        if st then
          steps[#steps + 1] = st
        end
      end
      if #steps > 0 then
        out[#out + 1] = {
          name = type(sc.name) == "string" and sc.name ~= "" and sc.name or ("scenario " .. (#out + 1)),
          covers = strings(sc.covers),
          size = kind == "tui" and (size(sc.size) or "80x24") or nil,
          viewport = kind == "web" and (size(sc.viewport) or "1280x800") or nil,
          steps = steps,
        }
      end
    end
  end
  return #out > 0 and out or nil
end

--- A step as one line for the feed and the judge: `type "12+3"`, `key Enter`, `click button "Save"`
---@param s UseStep
---@return string
function M.describe(s)
  local d = s["do"]
  local function target(t)
    if type(t) ~= "table" then
      return "?"
    end
    if t.role then
      return ('%s "%s"'):format(t.role, t.name or "")
    end
    local k, v = next(t)
    return ('%s "%s"'):format(k, tostring(v))
  end
  if d == "type" then
    return ("type %q"):format(s.text)
  elseif d == "key" or d == "press" then
    return "key " .. s.key
  elseif d == "resize" or d == "viewport" then
    return "resize to " .. (s.size or "?")
  elseif d == "wait" then
    return ("wait %d ms"):format(s.ms or 0)
  elseif d == "run" then
    local cmd = "run "
      .. table.concat(
        vim.tbl_map(function(a)
          return a:find "%s" and ("%q"):format(a) or a
        end, s.args or {}),
        " "
      )
    return s.stdin and (cmd .. (" < %q"):format(s.stdin:sub(1, 60))) or cmd
  elseif d == "goto" then
    return "open " .. s.path
  elseif d == "fill" then
    return ("fill %s with %q"):format(target(s.target), s.value)
  elseif d == "select" then
    return ("choose %q in %s"):format(s.value, target(s.target))
  elseif d == "swipe" then
    return "swipe " .. s.direction
  end
  return d .. " " .. target(s.target)
end

return M
