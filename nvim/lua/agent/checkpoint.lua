-- ── One key to take a whole run back ─────────────────────────────────────────
-- `u` already undoes ONE accepted proposal in ONE buffer. A batch (fix all, the queue's accept-all, a plan) writes into
-- several buffers, and nobody wants to hunt them down. Every accepted proposal is remembered here (the lines before, the
-- lines it wrote, and where they are now, tracked by an extmark); proposals of one batch form one group, and `undo` takes
-- the LAST group back.
-- It never overwrites what you did afterwards: a range whose text is no longer what the agent wrote is skipped and said so.
-- The restore is an ordinary edit, so `u` undoes the undo.
local events = require "agent.events"

local M = {}

local NS = vim.api.nvim_create_namespace "agent.checkpoint"
local MAX_GROUPS = 20

---@class AgentCheckpointItem
---@field buf integer
---@field mark integer?
---@field before string[]
---@field after string[]

---@class AgentCheckpointGroup
---@field id any            the batch id (or the job's own id)
---@field label string
---@field items AgentCheckpointItem[]

---@type AgentCheckpointGroup[]
local groups = {}

---@type table<any, AgentCheckpointItem>
local pending = {} -- by job id, between `accepting` and `accepted`

---@param job AgentJob
---@return any
local function group_id(job)
  return (job.meta and job.meta.batch) or ("job" .. job.id)
end

local function on_accepting(ev)
  pending[ev.job.id] = {
    buf = ev.buf,
    before = vim.api.nvim_buf_get_lines(ev.buf, ev.first - 1, ev.last, false),
    after = vim.deepcopy(ev.lines),
  }
end

local function on_accepted(ev)
  local item = pending[ev.job.id]
  pending[ev.job.id] = nil
  if not item or not vim.api.nvim_buf_is_valid(ev.buf) then
    return
  end
  local last_line = vim.api.nvim_buf_get_lines(ev.buf, ev.last - 1, ev.last, false)[1] or ""
  item.mark = vim.api.nvim_buf_set_extmark(ev.buf, NS, ev.first - 1, 0, {
    end_row = ev.last - 1,
    end_col = #last_line,
    right_gravity = false,
    end_right_gravity = true,
    strict = false,
  })
  local id = group_id(ev.job)
  local top = groups[#groups]
  if not (top and top.id == id) then
    top = { id = id, label = ev.job.action.label, items = {} }
    groups[#groups + 1] = top
    if #groups > MAX_GROUPS then
      table.remove(groups, 1)
    end
  end
  top.items[#top.items + 1] = item
end

--- What there is to take back: { label, changes, files }, nil when nothing
---@return { label: string, changes: integer, files: integer }?
function M.last()
  local g = groups[#groups]
  if not g then
    return nil
  end
  local files = {}
  for _, item in ipairs(g.items) do
    files[item.buf] = true
  end
  return { label = g.label, changes = #g.items, files = vim.tbl_count(files) }
end

---@param item AgentCheckpointItem
---@return "restored"|"edited"|"gone"
local function restore(item)
  if not vim.api.nvim_buf_is_valid(item.buf) or not item.mark then
    return "gone"
  end
  local m = vim.api.nvim_buf_get_extmark_by_id(item.buf, NS, item.mark, { details = true })
  if not m or #m == 0 then
    return "gone"
  end
  local first, last = m[1], m[3].end_row
  if not last then
    return "gone"
  end
  local now = vim.api.nvim_buf_get_lines(item.buf, first, last + 1, false)
  if not vim.deep_equal(now, item.after) then
    return "edited"
  end
  vim.api.nvim_buf_set_lines(item.buf, first, last + 1, false, item.before)
  pcall(vim.api.nvim_buf_del_extmark, item.buf, NS, item.mark)
  return "restored"
end

--- Takes the last group back. Returns a summary: { restored, skipped, label }
---@return { restored: integer, skipped: integer, label: string }?
function M.undo()
  local g = table.remove(groups)
  if not g then
    return nil
  end
  local restored, skipped = 0, 0
  for i = #g.items, 1, -1 do
    if restore(g.items[i]) == "restored" then
      restored = restored + 1
    else
      skipped = skipped + 1
    end
  end
  return { restored = restored, skipped = skipped, label = g.label }
end

--- The key's whole flow: undo, say what happened
function M.run()
  local log = require "utils.log"
  local r = M.undo()
  if not r then
    return log.info "Agent: nothing to undo"
  end
  local what = ("%d change%s"):format(r.restored, r.restored == 1 and "" or "s")
  if r.skipped > 0 then
    return log.warn(("Agent: undid %s of %s · %d left alone (you edited them since)"):format(what, r.label, r.skipped))
  end
  log.info(("Agent: undid %s of %s"):format(what, r.label))
end

local subscribed = false

function M.setup()
  if subscribed then
    return
  end
  subscribed = true
  events.on("proposal.accepting", on_accepting)
  events.on("proposal.accepted", on_accepted)
end

--- Forgets everything (tests)
function M.reset()
  for _, g in ipairs(groups) do
    for _, item in ipairs(g.items) do
      if item.mark and vim.api.nvim_buf_is_valid(item.buf) then
        pcall(vim.api.nvim_buf_del_extmark, item.buf, NS, item.mark)
      end
    end
  end
  groups, pending, subscribed = {}, {}, false
end

return M
