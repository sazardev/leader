-- ── The Herdr panel ───────────────────────────────────────────────────────────
-- What the whole workspace is doing: every agent, the state Herdr sees (idle, working, blocked), where it is and, for
-- the one under the cursor, its transcript and WHY Herdr thinks it is in that state (the rule that matched).
--
-- It refreshes on its own (every settings.herdr.observe_ms), so what is on screen is the state now and not the state
-- when the panel was opened. Nothing is started, nothing is sent: it only looks.
local herdr = require "herdr"
local log = require "utils.log"
local market = require "utils.market"
local settings = require "core.settings"

local M = {}

local STATE_MARK = {
  working = "●",
  blocked = "!",
  idle = "○",
  done = "✓",
  unknown = "?",
}

local STATE_HL = {
  working = "DiagnosticWarn",
  blocked = "DiagnosticError",
  idle = "Comment",
  done = "DiagnosticOk",
  unknown = "Comment",
}

---@param path string?
---@return string
local function short(path)
  if not path or path == "" then
    return ""
  end
  return vim.fn.fnamemodify(path, ":~")
end

--- The rows: one title per workspace, one row per agent
---@param m table
---@return table[]
function M.rows(m)
  local out, order = {}, {}
  local by_ws = {}
  for _, a in ipairs(m.agents or {}) do
    local id = a.workspace_id or "?"
    by_ws[id] = by_ws[id] or {}
    table.insert(by_ws[id], a)
  end
  for _, ws in ipairs(m.workspaces or {}) do
    if by_ws[ws.workspace_id] then
      order[#order + 1] = { id = ws.workspace_id, label = ws.label or ws.workspace_id }
    end
  end
  local unknown = {}
  for id in pairs(by_ws) do -- a workspace the list did not name (a remote machine) still shows
    local known = false
    for _, ws in ipairs(order) do
      known = known or ws.id == id
    end
    if not known then
      unknown[#unknown + 1] = id
    end
  end
  table.sort(unknown) -- the ones without a label keep a stable order
  for _, id in ipairs(unknown) do
    order[#order + 1] = { id = id, label = id }
  end
  for _, ws in ipairs(order) do
    out[#out + 1] = { group = ws.label, title = true }
    for _, a in ipairs(by_ws[ws.id]) do
      out[#out + 1] = { agent = a }
    end
  end
  if #out == 0 then
    out[#out + 1] = { empty = true }
  end
  return out
end

---@param row table
---@return boolean
local function selectable(row)
  return row.agent ~= nil
end

--- The row of the list: its state, the agent and where it is
---@param row table
---@return table[]
function M.list_line(row)
  if row.title then
    return { { " " .. row.group, "NvModalBtn1" } }
  end
  if row.empty then
    return { { "   no agent in this workspace", "Comment" } }
  end
  local a = row.agent
  local state = a.agent_status or "unknown"
  return {
    { " " .. (STATE_MARK[state] or "?") .. " ", STATE_HL[state] or "Comment" },
    { (a.agent or "?"), "Identifier" },
    { "  " .. short(a.foreground_cwd or a.cwd), "Directory" },
  }
end

--- Reads the transcript (and the reason) of one agent, once
---@param m table
---@param pane_id string
local function read_transcript(m, pane_id)
  m.reading = m.reading or {}
  if m.reading[pane_id] then
    return
  end
  m.reading[pane_id] = true
  herdr.read(pane_id, function(text)
    m.reading[pane_id] = nil
    m.text = m.text or {}
    m.text[pane_id] = text or "" -- an empty string: it was read and there was nothing (or it failed)
    if not m.closed then
      market.refresh(m)
    end
  end)
end

--- The reading pane: who it is, where it is, why Herdr says so, and its own words
---@param m table
---@param row table?
---@param width integer
---@return table[]
local function pane(m, row, width)
  local out = {}
  local a = row and row.agent
  if not a then
    return { { { "   Nothing to read", "Comment" } } }
  end
  local state = a.agent_status or "unknown"
  out[#out + 1] = {
    { a.agent or "?", "Title" },
    { "  ·  ", "Comment" },
    { state, STATE_HL[state] or "Comment" },
  }
  out[#out + 1] = { { short(a.foreground_cwd or a.cwd) .. "  ·  " .. (a.pane_id or ""), "Directory" } }

  local why = m.explain and m.explain[a.pane_id]
  if why and why.matched_rule then
    out[#out + 1] = {
      { "why: ", "Comment" },
      { why.matched_rule.id or "?", "Comment" },
      { why.matched_rule.region and ("  (" .. why.matched_rule.region .. ")") or "", "Comment" },
    }
  elseif why and why.state then
    out[#out + 1] = { { "why: " .. why.state, "Comment" } }
  end
  out[#out + 1] = { { "" } }

  local text = m.text and m.text[a.pane_id]
  if text == nil then
    -- the cursor landed here: read it now (the pane says so until the answer comes)
    read_transcript(m, a.pane_id)
    out[#out + 1] = { { "   (reading…)", "Comment" } }
    return out
  end
  if text == "" then
    out[#out + 1] = { { "   (nothing to read)", "Comment" } }
    return out
  end
  for _, line in ipairs(vim.split(text, "\n")) do
    if line ~= "" then
      for _, wrapped in ipairs(market.wrap(line, math.max(width - 2, 20))) do
        out[#out + 1] = { { wrapped, "Comment" } }
      end
    end
  end
  return out
end

---@param m table
---@return table[]
local function summary(m)
  local working, total = 0, #(m.agents or {})
  for _, a in ipairs(m.agents or {}) do
    if a.agent_status == "working" then
      working = working + 1
    end
  end
  return {
    {
      { ("%d agent%s · %d working"):format(total, total == 1 and "" or "s", working), "Comment" },
      { "   herdr: ", "Comment" },
      { m.bin or "?", "Comment" },
    },
  }
end

--- The cursor rests on an agent: when the data arrives after the panel opened, it lands on the title
---@param m table
local function ensure_cursor(m)
  local row = market.current(m)
  if row and row.agent then
    return
  end
  for i, r in ipairs(m.rows or {}) do
    if r.agent then
      pcall(vim.api.nvim_win_set_cursor, m.wins.list, { i, 0 })
      return
    end
  end
end

--- Reads everything again: the agents, then the transcript of the one under the cursor
---@param m table
local function refresh(m)
  if m.busy or m.closed then
    return
  end
  m.busy = true
  local function done()
    m.busy = false
    if m.closed then
      return
    end
    market.refresh(m)
  end
  herdr.agents(function(agents)
    herdr.workspaces(function(workspaces)
      m.agents, m.workspaces = agents, workspaces
      market.refresh(m) -- the rows change: the cursor may be on a title now
      ensure_cursor(m)
      local row = market.current(m)
      local a = row and row.agent
      local pane_id = a and a.pane_id
      local changed = pane_id ~= m.pane
      m.pane = pane_id
      if not pane_id then
        m.text = {}
        return done()
      end
      -- the transcript changes while the agent works; when it is idle its last words do not move
      if not changed and a.agent_status ~= "working" and m.text[pane_id] then
        return done()
      end
      read_transcript(m, pane_id)
      if changed then
        herdr.explain(pane_id, function(explain)
          m.explain = m.explain or {}
          m.explain[pane_id] = explain
          done()
        end)
      else
        done()
      end
    end)
  end)
end

--- Opens the panel
function M.open()
  if not herdr.enabled() then
    return log.warn "Herdr: not installed — <leader>Ws → Setup installs it"
  end
  local m = { agents = {}, workspaces = {}, text = {}, explain = {} }
  m.bin = (require("herdr.cli").bin() or "herdr")
  local spec = {
    title = "Herdr",
    rows = M.rows,
    selectable = selectable,
    list_line = M.list_line,
    pane = pane,
    summary = summary,
    hints = function()
      return {
        { "j k", "move" },
        { "⏎", "read" },
        { "f", "focus it in Herdr" },
        { "s", "send it a prompt" },
        { "x", "why Herdr says so" },
        { "r", "refresh" },
        { "q", "close" },
      }
    end,
    help = {
      { "f", "bring the agent's pane to the front in Herdr" },
      { "s", "send a prompt to the agent under the cursor" },
      { "x", "explain how Herdr detected its state" },
    },
    keys = {
      list = {
        {
          "f",
          function(mm, row)
            local a = row and row.agent
            if not a then
              return
            end
            herdr.focus(a.pane_id, function(ok, err)
              log.info(ok and ("Herdr: %s brought to the front"):format(a.agent or a.pane_id) or ("Herdr: " .. (err or "?")))
            end)
          end,
          "Focus in Herdr",
        },
        {
          "s",
          function(mm, row)
            local a = row and row.agent
            if not a then
              return
            end
            require("utils.modal").input({ "What does it do next?" }, { title = "Prompt " .. (a.agent or a.pane_id) }, function(text)
              if not text or text == "" then
                return
              end
              herdr.prompt(a.pane_id, text, function(ok, err)
                log.info(ok and "Herdr: prompt sent" or ("Herdr: " .. (err or "the prompt was not sent")))
              end)
            end)
          end,
          "Send a prompt",
        },
        {
          "x",
          function(mm, row)
            local a = row and row.agent
            if not a then
              return
            end
            herdr.explain(a.pane_id, function(explain, err)
              if not explain then
                return log.warn("Herdr: " .. (err or "nothing to explain"))
              end
              local lines = { "# " .. (a.agent or a.pane_id), "" }
              lines[#lines + 1] = "- state: " .. tostring(explain.state)
              lines[#lines + 1] = "- rule: " .. tostring(explain.matched_rule and explain.matched_rule.id or "none")
              lines[#lines + 1] = "- region: " .. tostring(explain.matched_rule and explain.matched_rule.region or "-")
              lines[#lines + 1] = "- manifest: " .. tostring(explain.manifest_source or "-")
              require("agent.ui.panel").open(lines, "Herdr · why")
            end)
          end,
          "Why Herdr says so",
        },
        {
          "r",
          function()
            refresh(m)
          end,
          "Refresh",
        },
      },
    },
    on_close = function(mm)
      mm.closed = true
      if mm.timer then
        mm.timer:stop()
        mm.timer:close()
        mm.timer = nil
      end
    end,
  }

  local ok, handle = pcall(market.new, spec, m)
  if not ok or not handle then
    return
  end

  local every = settings.herdr.observe_ms
  if every and every > 0 then
    local timer = vim.uv.new_timer()
    timer:start(every, every, vim.schedule_wrap(function()
      refresh(m)
    end))
    m.timer = timer
  end
  refresh(m)
end

return M
