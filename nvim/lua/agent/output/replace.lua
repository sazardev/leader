-- ── "replace" presenter: inline proposal, accept/reject ──────────────────────
-- The result does NOT touch the buffer: it is painted as a diff over the code (ui/preview) and
-- you wait for your decision. Accept = a single set_lines (one `u` undoes it all). If
-- the code changed while the agent was working, it is discarded instead of overwritten.
local anchor = require "agent.anchor"
local events = require "agent.events"
local log = require "utils.log"
local preview = require "agent.ui.preview"
local protocol = require "agent.protocol"
local runs = require "agent.runs"
local settings = require("core.settings").agent
local stats = require "agent.stats"

local M = {}

---@class AgentProposal
---@field job AgentJob
---@field lines string[]     what accepting writes (after `merge`)
---@field raw string[]       what the model returned (before `merge`): what a refinement starts from
---@field ids integer[]

---@type table<integer, AgentProposal[]>
local proposals = {}

---@type table<string, string>
local KEY_LABEL = { ["<CR>"] = "Enter", ["<Esc>"] = "Esc", ["<Tab>"] = "Tab" }

---@param key string
---@return string
local function label(key)
  return KEY_LABEL[key] or key
end

---@param buf integer
local function bind(buf)
  local keys = settings.keys
  vim.keymap.set("n", keys.accept, M.accept, { buffer = buf, nowait = true, desc = "Agent accept proposal" })
  vim.keymap.set("n", keys.reject, M.reject, { buffer = buf, nowait = true, desc = "Agent reject proposal" })
  if keys.refine then
    vim.keymap.set("n", keys.refine, M.refine, { buffer = buf, nowait = true, desc = "Agent refine proposal" })
  end
end

---@param buf integer
local function unbind(buf)
  for _, key in pairs(settings.keys) do
    -- only the proposal's own mappings: the answer window may have bound the same key (refine) on this buffer
    local map = vim.api.nvim_buf_call(buf, function()
      return vim.fn.maparg(key, "n", false, true) -- it looks at the CURRENT buffer's mappings
    end)
    if map.buffer == 1 and (map.desc or ""):find("proposal", 1, true) then
      pcall(vim.keymap.del, "n", key, { buffer = buf })
    end
  end
end

--- Puts the keys back if proposals are still waiting in the buffer (something else borrowed one for a while)
---@param buf integer
function M.rebind(buf)
  if proposals[buf] and #proposals[buf] > 0 and vim.api.nvim_buf_is_valid(buf) then
    bind(buf)
  end
end

--- The proposal under the cursor; if none, the oldest one in the buffer
---@param buf integer
---@return AgentProposal?
local function current(buf)
  local list = proposals[buf]
  if not list or #list == 0 then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  for _, p in ipairs(list) do
    local first, last = anchor.range(buf, p.job.anchor)
    if first and row >= first and row <= last then
      return p
    end
  end
  return list[1]
end

---@param p AgentProposal
---@param how "rejected"|"refined"|"discarded"|"accepted"
local function drop(p, how)
  local buf = p.job.buf
  preview.clear(buf, p.ids)
  anchor.delete(buf, p.job.anchor)
  local list = proposals[buf] or {}
  for i, other in ipairs(list) do
    if other == p then
      table.remove(list, i)
      break
    end
  end
  if #list == 0 then
    proposals[buf] = nil
    if vim.api.nvim_buf_is_valid(buf) then
      unbind(buf)
    end
  end
  if how and how ~= "accepted" then
    events.emit("proposal.dropped", { job = p.job, how = how })
  end
end

--- Removes blank edges the model added and the target did not have
---@param code string[]
---@param target AgentTarget
---@return string[]
local function normalize(code, target)
  local function blank(l)
    return l == nil or not l:match "%S"
  end
  while #code > 0 and blank(code[#code]) and not blank(target.lines[#target.lines]) do
    table.remove(code)
  end
  while #code > 0 and blank(code[1]) and not blank(target.lines[1]) do
    table.remove(code, 1)
  end
  return code
end

---@param job AgentJob
---@param result table
---@return string? summary
function M.done(job, result)
  local code, needs, err, blocks, note = protocol.extract_code(result.text, job.target.lines)
  if not code then
    log.warn("Agent: " .. err .. " (showing the raw response)")
    return require("agent.output.text").done(job, result)
  end
  local raw = vim.deepcopy(code)
  -- `merge`: the model returned only what is NEW (adding tests at the end of a file): it is joined to what is already there
  if job.action.merge then
    code = job.action.merge(code, job.target)
  end
  code = normalize(code, job.target)

  if vim.deep_equal(code, job.target.lines) then
    anchor.delete(job.buf, job.anchor)
    runs.event(job, "unchanged")
    if note then
      log.info("Agent: left unchanged — " .. note)
      return "no changes · " .. note
    end
    return "no changes"
  end
  if not anchor.unchanged(job) then
    anchor.delete(job.buf, job.anchor)
    runs.event(job, "discarded", "code changed while running")
    log.warn "Agent: the code changed while the agent was working; proposal discarded"
    return nil
  end

  local first = anchor.range(job.buf, job.anchor)
  -- the destination can be another file (tests): it opens to the side, at the proposal, to decide there
  if job.action.reveal and vim.fn.bufwinid(job.buf) == -1 then
    vim.cmd "botright vsplit"
    vim.api.nvim_win_set_buf(0, job.buf)
    pcall(vim.api.nvim_win_set_cursor, 0, { math.min(first, vim.api.nvim_buf_line_count(job.buf)), 0 })
    vim.cmd "normal! zz"
  end
  local proposal = { job = job, lines = code, raw = raw, ids = {} }
  job.proposal = proposal
  proposal.ids = preview.render(job.buf, first, job.target.lines, code, function(hunks)
    local keys = settings.keys
    -- parts by priority (1 = essential): if the window is narrow the least
    -- important ones are dropped instead of cutting the line in half
    local parts = {
      {
        ("%s accept · %s reject%s"):format(
          label(keys.accept),
          label(keys.reject),
          keys.refine and (" · %s refine"):format(label(keys.refine)) or ""
        ),
        1,
      },
      { ("%d change%s"):format(hunks, hunks == 1 and "" or "s"), 2 },
    }
    if blocks and blocks > 1 then
      parts[#parts + 1] = { ("model sent %d blocks, check the diff"):format(blocks), 1 }
    end
    if note then
      parts[#parts + 1] = { "note: " .. note, 1 }
    end
    if needs then
      parts[#parts + 1] = { "import: " .. needs, 2 }
    end
    parts[#parts + 1] = { stats.line(job, result), 3 }
    -- whether anything will check this (or did): "unverified" is a label, not a warning (agent/trust.lua)
    local verify_cfg = settings.verify
    local facts = {
      output = "replace",
      verifies = verify_cfg.enabled and job.action.verify ~= false,
      comment_only = job.action.verify == false and job.action.merge ~= nil,
      lsp = #vim.lsp.get_clients { bufnr = job.buf } > 0,
      build = verify_cfg.command ~= false and verify_cfg.command ~= nil,
    }
    parts[#parts + 1] = { (require("agent.trust").verification(facts)), 2 }
    if job.meta and job.meta.hint then
      parts[#parts + 1] = { job.meta.hint, 2 } -- "2/4 · <leader>aA] next" when it comes from a batch
    end
    return require("utils.hints").fit(parts, vim.api.nvim_win_get_width(0) - 8)
  end)
  proposals[job.buf] = proposals[job.buf] or {}
  table.insert(proposals[job.buf], proposal)
  bind(job.buf)
end

---@class AgentAcceptOpts
---@field keep_cursor boolean? do not move the cursor to the new code (accepting a whole queue)

--- Writes a proposal into its buffer. One set_lines: a single `u` undoes it
---@param p AgentProposal
---@param opts AgentAcceptOpts?
---@return boolean accepted
function M.accept_proposal(p, opts)
  opts = opts or {}
  local buf = p.job.buf
  if not anchor.unchanged(p.job) then
    drop(p, "discarded")
    runs.event(p.job, "discarded", "code changed since the proposal")
    log.warn "Agent: the code changed since the proposal; discarded"
    return false
  end
  local first, last = anchor.range(buf, p.job.anchor)
  events.emit("proposal.accepting", { job = p.job, buf = buf, first = first, last = last, lines = p.lines })
  drop(p, "accepted")
  runs.event(p.job, "accepted")
  -- the code in that range is rewritten: what the review flagged there no longer applies (and if it was a fix, neither
  -- do its local DDD violations)
  pcall(function()
    require("agent.output.findings").resolve(buf, first, last)
    if p.job.action.fixes then
      require("agent.ddd.diagnose").resolve(buf, first, last)
    end
  end)
  vim.api.nvim_buf_set_lines(buf, first - 1, last, false, p.lines)
  pcall(function()
    require("ui.flat.fresh").lines(buf, first - 1, first - 1 + #p.lines) -- what you just accepted glows and fades (ui/flat)
  end)
  if not opts.keep_cursor and vim.api.nvim_win_get_buf(0) == buf then
    pcall(vim.api.nvim_win_set_cursor, 0, { first, 0 })
  end

  if settings.apply.format then
    local ok, conform = pcall(require, "conform")
    if ok then
      local end_row = first + #p.lines - 1
      conform.format {
        bufnr = buf,
        async = true,
        quiet = true,
        lsp_format = "fallback",
        range = { start = { first, 0 }, ["end"] = { end_row, #p.lines[#p.lines] } },
      }
    end
  end
  events.emit(
    "proposal.accepted",
    { job = p.job, buf = buf, first = first, last = first + #p.lines - 1, lines = p.lines }
  )
  return true
end

function M.accept()
  local p = current(vim.api.nvim_get_current_buf())
  if p then
    M.accept_proposal(p)
  end
end

function M.reject()
  local p = current(vim.api.nvim_get_current_buf())
  if p then
    drop(p, "rejected")
    runs.event(p.job, "rejected")
  end
end

--- Asks for a change to the proposal under the cursor (agent/refine.lua): it replaces this proposal with a new one
function M.refine()
  local p = current(vim.api.nvim_get_current_buf())
  if p then
    require("agent.refine").proposal(p)
  end
end

--- The proposal gives way to a refinement: its preview goes, its code stays untouched, the history says why
---@param p AgentProposal
function M.supersede(p)
  drop(p, "refined")
  runs.event(p.job, "refined")
end

--- Every proposal waiting for a decision, in the order the agent produced them (across buffers)
---@return AgentProposal[]
function M.pending()
  local all = {}
  for _, list in pairs(proposals) do
    vim.list_extend(all, list)
  end
  table.sort(all, function(a, b)
    return a.job.id < b.job.id
  end)
  return all
end

--- Discards all pending proposals (from one buffer, or all of them)
---@param buf integer?
function M.discard_all(buf)
  for b, list in pairs(proposals) do
    if not buf or b == buf then
      for _, p in ipairs(vim.list_slice(list)) do
        drop(p, "discarded")
        runs.event(p.job, "discarded", "cleared")
      end
    end
  end
end

---@param job AgentJob
function M.release(job)
  anchor.delete(job.buf, job.anchor)
end

return M
