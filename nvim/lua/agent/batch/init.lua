-- ── Batch: several proposals in a row ────────────────────────────────────────
-- Fix all, fix from output and multi-file plans all end up as "N pieces of code, each one request". This module is what
-- they share: ONE confirmation with the total estimate (the budget guard is not asked again per piece, but a cap still
-- stops it), the pieces run one by one (a model is never hit with 12 requests at once), a progress label in the statusline
-- ("fix all 2/4"), and when they are all done the proposals wait in a queue to review (batch/queue.lua).
--
-- It knows nothing about WHY the pieces exist: the caller hands over items and the action to run them with.
local anchor = require "agent.anchor"
local budget = require "agent.budget"
local events = require "agent.events"
local log = require "utils.log"
local queue = require "agent.batch.queue"
local selection = require "agent.selection"
local settings = require("core.settings").agent

local M = {}

---@class AgentBatchItem
---@field label string
---@field target AgentTarget
---@field extra (table[] | fun(done: AgentBatchItem[]): table[])?   sections for this piece; a function sees the pieces done before it
---@field input string?
---@field count integer?                                              how many problems this piece solves (shown in the summary)
---@field diags table[]?                                              the problems themselves (diagnostic-like)
---@field anchor integer?                                             (set by the batch)
---@field job AgentJob?                                               (set by the batch)
---@field outcome string?                                             "done" | "error" | "cancelled" | "denied" | "skipped"

---@class AgentBatch
---@field id integer
---@field title string
---@field items AgentBatchItem[]
---@field index integer
---@field aborted boolean?

---@class AgentBatchSpec
---@field title string
---@field action table                    the action every piece runs (its label gets the progress appended)
---@field items AgentBatchItem[]
---@field selection AgentSelection?       default: the one the action's tier picks
---@field confirm boolean?                ask once with the total (default true)
---@field header table?                   lines shown above the summary in the confirmation (why this is being asked)
---@field meta table?                     copied into every job's meta
---@field on_done fun(batch: AgentBatch)?

--- Fixed part of a request that is not the target: the system prompt and the typical context
local OVERHEAD_CHARS = 1100 + 1500

---@type table<integer, AgentBatch>
local active = {}
local seq = 0
local listening = false

---@param items AgentBatchItem[]
---@return integer
local function chars_of(items)
  local n = 0
  for _, item in ipairs(items) do
    n = n + OVERHEAD_CHARS + #table.concat(item.target.lines, "\n")
    if type(item.extra) == "table" then
      for _, s in ipairs(item.extra) do
        n = n + #s.text
      end
    end
  end
  return n
end

---@param batch AgentBatch
---@return AgentBatchItem[]
local function done_items(batch)
  return vim.tbl_filter(function(i)
    return i.outcome == "done"
  end, batch.items)
end

local run_next

---@param batch AgentBatch
local function finish(batch)
  active[batch.id] = nil
  for _, item in ipairs(batch.items) do
    if item.anchor then
      anchor.delete(item.target.buf, item.anchor)
    end
  end
  local proposals = {}
  for _, item in ipairs(batch.items) do
    if item.job and item.job.proposal then
      proposals[#proposals + 1] = item.job.proposal
    end
  end
  if batch.spec.on_done then
    pcall(batch.spec.on_done, batch, proposals)
  end
  if batch.aborted then
    return log.info(("Agent %s: stopped (%d of %d done)"):format(batch.title, #done_items(batch), #batch.items))
  end
  if #proposals == 0 then
    return log.info(("Agent %s: nothing to change (0 proposals)"):format(batch.title))
  end
  -- one proposal speaks for itself (its hint says Enter / Esc / Tab); several need a word about how to move through them
  if #proposals > 1 then
    log.info(
      ("Agent %s: %d proposals ready · %s next · %s accept all"):format(
        batch.title,
        #proposals,
        queue.label "next",
        queue.label "accept_all"
      )
    )
  end
  queue.open()
end

---@param batch AgentBatch
local function on_settled(batch, item, outcome)
  item.outcome = outcome
  if outcome == "cancelled" or outcome == "denied" then
    batch.aborted = true -- you stopped it, or the budget did: the rest does not go on
  end
  vim.schedule(function()
    run_next(batch)
  end)
end

---@param batch AgentBatch
run_next = function(batch)
  if batch.aborted or batch.index >= #batch.items then
    return finish(batch)
  end
  batch.index = batch.index + 1
  local item = batch.items[batch.index]
  local first, last = anchor.range(item.target.buf, item.anchor)
  if not first or not vim.api.nvim_buf_is_valid(item.target.buf) then
    item.outcome = "skipped" -- the code was deleted meanwhile
    return run_next(batch)
  end
  -- the range may have moved (you accepted something above it): ask for what is THERE now
  local target =
    require("agent.context.target").of_range(item.target.buf, item.target.kind, first, last, item.target.name)
  if not target then
    item.outcome = "skipped"
    return run_next(batch)
  end
  item.target = target
  local extra = type(item.extra) == "function" and item.extra(done_items(batch)) or item.extra
  local several = #batch.items > 1
  local progress = ("%d/%d"):format(batch.index, #batch.items)
  local derived = vim.tbl_extend("force", batch.spec.action, {
    label = several and ("%s %s"):format(batch.title, progress) or batch.title,
  })
  item.job = require("agent.pipeline").launch {
    action = derived,
    target = target,
    selection = batch.selection,
    input = item.input,
    extra = extra,
    preapproved = true,
    meta = vim.tbl_extend("force", batch.spec.meta or {}, {
      batch = batch.id,
      index = batch.index,
      hint = several and ("%s · %s next"):format(progress, queue.label "next") or nil,
    }),
  }
end

local function listen()
  if listening then
    return
  end
  listening = true
  events.on("job.settled", function(ev)
    local id = ev.job.meta and ev.job.meta.batch
    local batch = id and active[id]
    if not batch then
      return
    end
    for _, item in ipairs(batch.items) do
      if item.job == ev.job then
        return on_settled(batch, item, ev.outcome)
      end
    end
  end)
end

---@param batch AgentBatch
local function start(batch)
  active[batch.id] = batch
  for _, item in ipairs(batch.items) do
    item.anchor = anchor.create(item.target.buf, item.target.first, item.target.last)
  end
  run_next(batch)
end

--- What the confirmation shows
---@param spec AgentBatchSpec
---@param verdict AgentBudgetVerdict
---@param sel AgentSelection
---@return table lines
local function summary_lines(spec, verdict, sel)
  local hl = require("utils.modal").hl
  local lines = vim.list_slice(spec.header or {})
  if #lines > 0 then
    lines[#lines + 1] = ""
  end
  vim.list_extend(lines, {
    { { ("%d proposal%s · %s"):format(#spec.items, #spec.items == 1 and "" or "s", selection.label(sel)) } },
    { { budget.describe(verdict), hl.muted } },
    "",
  })
  for i, item in ipairs(spec.items) do
    if i > 6 then
      lines[#lines + 1] = { { ("  … and %d more"):format(#spec.items - 6), hl.muted } }
      break
    end
    local file = vim.fn.fnamemodify(item.target.path, ":t")
    lines[#lines + 1] = {
      { "  " },
      { file, hl.folder },
      { "  " .. item.label .. (item.count and item.count > 1 and (" · %d problems"):format(item.count) or "") },
    }
  end
  for _, reason in ipairs(verdict.reasons) do
    lines[#lines + 1] = { { reason, hl.warn } }
  end
  return lines
end

--- What running `items` would cost, as the budget sees it (no confirmation, nothing started)
---@param items AgentBatchItem[]
---@param sel AgentSelection
---@param title string?
---@return AgentBudgetVerdict
function M.estimate(items, sel, title)
  return budget.check({
    action = title or "batch",
    backend = sel.backend,
    model = sel.model,
    chars = chars_of(items),
  }, settings.budget, require("agent.guards.budget").context())
end

---@param spec AgentBatchSpec
function M.run(spec)
  listen()
  local sel = spec.selection or selection.current(spec.action)
  if not sel then
    return log.error "Agent: no backend available: run <leader>am → Setup"
  end
  local items = spec.items
  if #items > settings.batch.max_items then
    log.warn(
      ("Agent: %d pieces; doing the first %d (settings.agent.batch.max_items)"):format(#items, settings.batch.max_items)
    )
    items = vim.list_slice(items, 1, settings.batch.max_items)
    spec = vim.tbl_extend("force", spec, { items = items })
  end

  seq = seq + 1
  local batch = { id = seq, title = spec.title, items = items, index = 0, spec = spec, selection = sel }

  -- the total goes through the budget (a cap blocks it; a big total asks), and then through the user ONCE
  local verdict = M.estimate(items, sel, spec.title)
  if verdict.level == "block" and settings.budget.enabled then
    return log.warn("Agent: " .. verdict.reasons[1])
  end
  if spec.confirm == false then
    return start(batch)
  end
  require("utils.modal").confirm(summary_lines(spec, verdict, sel), { title = spec.title }, function()
    start(batch)
  end)
end

---@return AgentBatch[]
function M.active()
  return vim.tbl_values(active)
end

return M
