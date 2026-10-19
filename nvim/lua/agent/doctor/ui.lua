-- ── The diagnosis, on the whole screen ───────────────────────────────────────
-- utils/market.lua with a doctor's content: on the left what was found for free (each finding with its steps) and the model's
-- diagnosis (its cause, then its steps); on the right the one under the cursor (the cause, the command, what an edit will do,
-- what a command printed); under both the state of the case. `p` shows exactly what would be sent to the model. The rows, the
-- lines and the summary are pure over the session (tested); `open` wires the keys to the handlers the flow gives.
local market = require "utils.market"
local modal = require "utils.modal"
local steps = require "agent.doctor.steps"

local M = {}

---@class DoctorSession
---@field root string
---@field source { label: string, kind: string, text: string?, command: string? }
---@field problem string?
---@field output string?
---@field code { path: string, lnum: integer, text: string }[]
---@field versions table<string, string>
---@field changes string?
---@field free DoctorFinding[]
---@field diagnosis DoctorDiagnosis?
---@field asking string?        what the agent is doing right now (waiting for the model, looking at a file…)
---@field tool_results { call: string, text: string }[]
---@field rerun string?         the command that reproduces the failure
---@field solved boolean?
---@field model string?
---@field estimate integer?

--- The list (pure)
---@param s DoctorSession
---@return table[]
function M.rows(s)
  local rows = { { title = "DOCTOR · " .. s.source.label }, { spacer = true } }
  for _, f in ipairs(s.free) do
    rows[#rows + 1] = { group = "Found · " .. f.title }
    for i, st in ipairs(f.steps) do
      rows[#rows + 1] = { step = st, finding = f, idx = i }
    end
    rows[#rows + 1] = { spacer = true }
  end
  if #s.free == 0 then
    rows[#rows + 1] = { group = "Found for free" }
    rows[#rows + 1] = { nothing = true }
    rows[#rows + 1] = { spacer = true }
  end
  if s.diagnosis then
    rows[#rows + 1] = { group = "Diagnosis · " .. s.diagnosis.confidence .. " confidence" }
    rows[#rows + 1] = { cause = true }
    for i, st in ipairs(s.diagnosis.steps) do
      rows[#rows + 1] = { step = st, idx = i }
    end
  else
    rows[#rows + 1] = { group = "Diagnosis" }
    rows[#rows + 1] = s.asking and { asking = true } or { ask = true }
  end
  return rows
end

---@param row table
---@return boolean
function M.selectable(row)
  return row.step ~= nil or row.cause == true or row.ask == true or row.asking == true or row.nothing == true
end

---@param row table
---@return MarketLine
function M.list_line(row)
  if row.title then
    return { { "  " .. row.title, modal.hl.key } }
  elseif row.spacer then
    return { { "" } }
  elseif row.group then
    local g = row.group:upper()
    if vim.fn.strdisplaywidth(g) > 38 then
      g = vim.fn.strcharpart(g, 0, 37) .. "…"
    end
    return { { (row.collapsed and "▸ " or "  ") .. g, modal.hl.muted } }
  elseif row.step then
    local st = row.step
    local hl = st.state == "done" and modal.hl.mark or st.state == "failed" and modal.hl.warn or modal.hl.file
    return {
      { " " .. steps.glyph(st) .. " ", st.state and hl or modal.hl.muted },
      { st.title, st.state == "done" and modal.hl.muted or modal.hl.file },
      { st.danger and "  !" or "", modal.hl.warn },
    }
  elseif row.cause then
    return { { " ◆ ", modal.hl.mark }, { "Why it fails", modal.hl.file } }
  elseif row.asking then
    return { { " … ", modal.hl.mark }, { "Asking the model", modal.hl.muted } }
  elseif row.ask then
    return { { " ? ", modal.hl.mark }, { "Ask the model for a diagnosis", modal.hl.file } }
  end
  return { { "   ", modal.hl.muted }, { "Nothing known matched this output", modal.hl.muted } }
end

---@param lines MarketLine[]
---@param text string
---@param hl string
---@param width integer
---@param indent string?
local function para(lines, text, hl, width, indent)
  indent = indent or "  "
  for _, row in ipairs(market.wrap(text, width - #indent - 2)) do
    lines[#lines + 1] = { { indent .. row, hl } }
  end
end

--- Rough tokens of a text
---@param chars integer
---@return integer
local function tokens(chars)
  return math.floor(chars / 4)
end

--- What the model would be sent, section by section (sizes), for the ask pane
---@param s DoctorSession
---@return string[]
function M.sent_summary(s)
  local out = {}
  local function add(name, text)
    if text and vim.trim(text) ~= "" then
      out[#out + 1] = ("%s (%d chars)"):format(name, #text)
    end
  end
  add("the failing output", s.output)
  if #(s.code or {}) > 0 then
    out[#out + 1] = ("%d project file%s the failure points into"):format(#s.code, #s.code == 1 and "" or "s")
  end
  if next(s.versions or {}) then
    out[#out + 1] = "toolchain versions"
  end
  add("what changed in git", s.changes)
  add("what you described", s.problem)
  if #s.free > 0 then
    out[#out + 1] = ("%d thing%s found for free"):format(#s.free, #s.free == 1 and "" or "s")
  end
  return out
end

--- The right pane for the row under the cursor
---@param s DoctorSession
---@param row table?
---@param width integer
---@return MarketLine[]
function M.pane(s, row, width)
  local lines = {}
  if not row then
    return { { { "" } } }
  end
  if row.ask or row.asking then
    lines[#lines + 1] = { { "  DIAGNOSE WITH THE MODEL", modal.hl.key } }
    para(lines, "One request reads the evidence below, finds the root cause and writes the steps. If it needs more it asks to read a file, search or run a read-only command (at most twice more); you never lose control: every step waits for your yes.", modal.hl.muted, width)
    lines[#lines + 1] = { { "" } }
    lines[#lines + 1] = { { "  WHAT IS SENT", modal.hl.muted } }
    for _, l in ipairs(M.sent_summary(s)) do
      lines[#lines + 1] = { { "  · " .. l, modal.hl.file } }
    end
    lines[#lines + 1] = { { "" } }
    para(lines, "Secrets that look like secrets are blacked out before this. `p` shows the exact text.", modal.hl.muted, width)
    if s.model then
      lines[#lines + 1] = { { "" } }
      lines[#lines + 1] = { { ("  %s · about %d tokens in"):format(s.model, s.estimate or 0), modal.hl.muted } }
    end
    if s.asking then
      lines[#lines + 1] = { { "" } }
      lines[#lines + 1] = { { "  " .. s.asking, modal.hl.mark } }
    end
    return lines
  elseif row.nothing then
    lines[#lines + 1] = { { "  NOTHING KNOWN MATCHED", modal.hl.key } }
    para(lines, "The free checks (known errors, dependencies, .env, toolchain versions, git state) found nothing in this evidence. The model can still read it: press ⏎ on “Ask the model”.", modal.hl.muted, width)
    return lines
  elseif row.cause then
    local d = s.diagnosis --[[@as DoctorDiagnosis]]
    lines[#lines + 1] = { { "  " .. (d.summary ~= "" and d.summary or "Diagnosis"):upper(), modal.hl.key } }
    lines[#lines + 1] = { { "  confidence: " .. d.confidence, d.confidence == "high" and modal.hl.mark or modal.hl.muted } }
    lines[#lines + 1] = { { "" } }
    para(lines, d.cause, modal.hl.file, width)
    if #d.steps > 0 then
      lines[#lines + 1] = { { "" } }
      lines[#lines + 1] = { { "  STEPS", modal.hl.muted } }
      for i, st in ipairs(d.steps) do
        lines[#lines + 1] = { { ("  %s %d. %s"):format(steps.glyph(st), i, st.title), modal.hl.file } }
      end
    end
    if #(s.tool_results or {}) > 0 then
      lines[#lines + 1] = { { "" } }
      lines[#lines + 1] = { { "  IT LOOKED AT", modal.hl.muted } }
      for _, r in ipairs(s.tool_results) do
        lines[#lines + 1] = { { "  · " .. r.call, modal.hl.muted } }
      end
    end
    return lines
  end
  local st, f = row.step, row.finding
  if not st then
    return { { { "" } } }
  end
  if f then
    lines[#lines + 1] = { { "  " .. f.title:upper(), modal.hl.key } }
    para(lines, f.cause, modal.hl.muted, width)
    if f.evidence and f.evidence ~= "" then
      lines[#lines + 1] = { { "  » " .. f.evidence, modal.hl.muted } }
    end
    lines[#lines + 1] = { { "" } }
  elseif s.diagnosis then
    lines[#lines + 1] = { { "  " .. s.diagnosis.summary:upper(), modal.hl.key } }
    lines[#lines + 1] = { { "" } }
  end
  lines[#lines + 1] = { { ("  STEP · %s"):format(st.kind), modal.hl.muted } }
  lines[#lines + 1] = { { "  " .. steps.glyph(st) .. " " .. st.title, modal.hl.file } }
  if st.kind == "command" then
    lines[#lines + 1] = { { "" } }
    lines[#lines + 1] = { { "  $ " .. st.run, modal.hl.mark } }
  elseif st.kind == "edit" then
    lines[#lines + 1] = { { "" } }
    lines[#lines + 1] = { { "  " .. st.file .. (st.line and (":" .. st.line) or ""), modal.hl.file } }
    if st.instruction then
      para(lines, st.instruction, modal.hl.muted, width)
    end
  elseif st.instruction or st.note then
    lines[#lines + 1] = { { "" } }
    para(lines, st.instruction or st.note, modal.hl.muted, width)
  end
  local why = st.why or st.note
  if why and st.kind ~= "manual" then
    lines[#lines + 1] = { { "" } }
    para(lines, why, modal.hl.muted, width)
  end
  if st.danger then
    lines[#lines + 1] = { { "" } }
    lines[#lines + 1] = { { "  ! destroys or rewrites something: read it twice", modal.hl.warn } }
  end
  if st.output and st.output ~= "" then
    lines[#lines + 1] = { { "" } }
    lines[#lines + 1] = { { ("  OUTPUT · exit %d"):format(st.exit or 0), st.exit == 0 and modal.hl.mark or modal.hl.warn } }
    for _, l in ipairs(vim.split(st.output, "\n", { plain = true })) do
      lines[#lines + 1] = { { "  " .. l:sub(1, math.max(width - 4, 20)), modal.hl.muted } }
    end
  end
  return lines
end

--- The strip: the state of the case
---@param s DoctorSession
---@return MarketLine[]
function M.summary(s)
  local lines = { { { "  CASE", modal.hl.key } } }
  local done, total = 0, 0
  local function count(list)
    for _, st in ipairs(list) do
      total = total + 1
      done = done + ((st.state == "done") and 1 or 0)
    end
  end
  for _, f in ipairs(s.free) do
    count(f.steps)
  end
  if s.diagnosis then
    count(s.diagnosis.steps)
  end
  lines[#lines + 1] = {
    {
      ("  %s · %d found for free · %s"):format(
        s.source.label,
        #s.free,
        s.diagnosis and ("diagnosis: " .. s.diagnosis.confidence .. " confidence") or (s.asking and "asking the model…" or "no model asked yet")
      ),
      modal.hl.file,
    },
  }
  if s.solved then
    lines[#lines + 1] = { { "  ✓ it runs now: nothing failed the last time", modal.hl.mark } }
  elseif total > 0 then
    lines[#lines + 1] = { { ("  %d of %d steps done%s"):format(done, total, s.rerun and " · r runs it again to check" or " · r reads the terminal again to check"), modal.hl.muted } }
  end
  return lines
end

--- Opens the screen for a session. `h` (handlers): ask(s), act(s, step, how), toggle(s, step), verify(s), followup(s), close(s)
---@param s DoctorSession
---@param h table
---@return Market
function M.open(s, h)
  local function step_of(row)
    return row and row.step
  end
  local def = {
    title = "Doctor",
    summary_rows = 6,
    rows = function()
      return M.rows(s)
    end,
    selectable = M.selectable,
    list_line = M.list_line,
    pane = function(_, row, width)
      return M.pane(s, row, width), {}
    end,
    result = function()
      return h.preview(s)
    end,
    summary = function()
      return M.summary(s)
    end,
    hints = function(mm, mode)
      if mode == "result" then
        return { { "Esc", "back" } }
      end
      local row = market.current(mm)
      if row and row.ask then
        return { { "⏎", "diagnose" }, { "p", "what is sent" }, { "?", "keys" }, { "q", "close" } }
      end
      return { { "⏎", "run" }, { "t", "terminal" }, { "Space", "mark done" }, { "r", "check again" }, { "a", "ask more" }, { "p", "what is sent" }, { "?", "keys" } }
    end,
    help = {
      { "⏎", "on a step: run it (it asks first); on “Ask the model”: diagnose" },
      { "t", "run the command in the integrated terminal instead (interactive things, servers)" },
      { "Space", "mark a step done by hand (manual steps, or something you did yourself)" },
      { "y", "copy the command" },
      { "r", "check again: run the failing command again (or read the terminal) and see if it still fails" },
      { "a", "ask the model a follow-up about this case" },
      { "p", "the exact text that is sent to the model" },
      { "q", "close: the case is kept, <leader>aXr reopens it" },
    },
    cancel = function(mm)
      market.close(mm)
    end,
    keys = {
      list = {
        {
          "<CR>",
          function(_, row)
            if row and row.ask then
              return h.ask(s)
            end
            local st = step_of(row)
            if st then
              h.act(s, st, "captured")
            end
          end,
          "Run",
        },
        {
          "t",
          function(_, row)
            local st = step_of(row)
            if st and st.kind == "command" then
              h.act(s, st, "terminal")
            end
          end,
          "Run in the terminal",
        },
        {
          "<Space>",
          function(mm, row)
            local st = step_of(row)
            if st then
              h.toggle(s, st)
              market.refresh(mm)
            end
          end,
          "Mark done",
        },
        {
          "y",
          function(_, row)
            local st = step_of(row)
            if st and st.run then
              vim.fn.setreg("+", st.run)
              vim.fn.setreg('"', st.run)
              require("utils.log").info("Doctor: copied `" .. st.run .. "`")
            end
          end,
          "Copy",
        },
        { "r", function() h.verify(s) end, "Check again" },
        { "a", function() h.followup(s) end, "Ask more" },
        { "A", function() h.ask(s) end, "Diagnose" },
      },
    },
  }
  return market.new(def, { doctor = s })
end

return M
