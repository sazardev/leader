-- ── Build with agent: the screens as they render, against DESIGN.md ──────────
-- Passing checks say the program works, not that it looks as designed: the keypad stuck to the left edge, a help bar cut
-- off, a frame DESIGN.md asks for and nobody drew. When every check passes, the screens the tests rendered (Go teatest golden
-- files: the exact text a terminal shows) go to the model with DESIGN.md (its Screens wireframes first) in one request; it
-- answers like a diagnosis (what differs, which files change, with what), and those files are fixed. Once per build.
-- Pure but for reading the files.
local diagnose = require "agent.kit.build.diagnose"
local prompt = require "agent.kit.build.prompt"

local M = {}

local MAX_RENDERS = 8
local MAX_CHARS = 24000

local TASK =
  [[Every check of this project passes. <render> blocks are its screens exactly as the terminal shows them (the tests' golden snapshots, colors stripped). Compare them with DESIGN.md: its `## Screens` wireframes first (layout, alignment, centering, frames, sizes, labels), then its rules (spacing, borders, glyphs, help bar, components).
Output ONLY one JSON object, no prose, no ``` fence:
{"diagnosis": "<one or two sentences: what differs from DESIGN.md, or 'matches'>", "files": [{"path": "<a path from the plan>", "change": "<concretely what to change in that file so the screen matches>"}]}
Rules:
- Only real differences a user would see (misaligned, not centered, cut off, missing frame or region, wrong order, overflow); colors cannot be seen here, ignore them.
- When the screens match DESIGN.md, answer with "files": [].
- Change code, never tests or golden files (they are regenerated); keep every behaviour SPEC.md states.
- At most 4 files; only paths from the plan; the smallest change that makes the screen match.]]

--- Terminal control sequences out (CSI, OSC, the cursor/mode switches teatest records), trailing spaces trimmed
---@param text string
---@return string
function M.clean(text)
  text = text:gsub("\27%][^\7\27]*\7", ""):gsub("\27%][^\27]*\27\\", "") -- OSC
  text = text:gsub("\27%[[%d;?]*[%a@`]", ""):gsub("\27[%(%)][%w]", ""):gsub("\27[=>78]", "") -- CSI, charset, modes
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = vim.split(text, "\n", { plain = true })
  for i, l in ipairs(lines) do
    lines[i] = l:gsub("%s+$", "")
  end
  -- the blank rows above and below the composition say nothing about it
  while lines[1] == "" do
    table.remove(lines, 1)
  end
  while lines[#lines] == "" do
    lines[#lines] = nil
  end
  return table.concat(lines, "\n")
end

---@class BuildRender
---@field path string relative to the root
---@field text string as the terminal shows it

--- The rendered screens of the project: Go golden files under a testdata folder (teatest), largest first, within a budget
---@param root string
---@return BuildRender[]
function M.renders(root)
  local found = vim.fs.find(function(name, dir)
    return name:match "%.golden$" ~= nil and dir:find("/testdata", 1, true) ~= nil
  end, { path = root, type = "file", limit = 50 })
  local out = {}
  for _, full in ipairs(found) do
    local raw = require("utils.project").read(full)
    if raw then
      local text = M.clean(raw)
      if text:match "%S" then
        out[#out + 1] = { path = full:sub(#root + 2), text = text }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.path < b.path
  end)
  local kept, used = {}, 0
  for _, r in ipairs(out) do
    if #kept < MAX_RENDERS and used + #r.text <= MAX_CHARS then
      kept[#kept + 1] = r
      used = used + #r.text
    end
  end
  return kept
end

--- The request: the build's cached system prompt (documents + plan), the API, the screens and the task
---@param renders BuildRender[]
---@param plan BuildPlan
---@param docs table<string, string>
---@param written table<string, string>
---@return table req
function M.request(renders, plan, docs, written)
  local parts = {}
  local api = prompt.api(written)
  if api ~= "" then
    parts[#parts + 1] = api
  end
  for _, r in ipairs(renders) do
    parts[#parts + 1] = ('<render path="%s">\n%s\n</render>'):format(r.path, r.text)
  end
  parts[#parts + 1] = TASK
  return {
    action = "kit_build_look",
    tier = "main",
    system = prompt.system(plan, docs),
    prompt = table.concat(parts, "\n\n"),
    cache = true,
  }
end

--- What to change; nil when the screens match (or the answer is not usable)
---@param text string
---@param planned string[]
---@return BuildDiagnosis?
function M.parse(text, planned)
  local parsed = diagnose.parse(text, planned)
  if not parsed then
    return nil
  end
  parsed.files = vim.tbl_filter(function(f) -- code only: tests and snapshots follow the code
    return not require("agent.kit.build.verify").is_test(f.path) and not f.path:match "%.golden$"
  end, parsed.files)
  return #parsed.files > 0 and parsed or nil
end

return M
