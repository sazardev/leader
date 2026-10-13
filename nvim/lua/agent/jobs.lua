-- ── Job registry ─────────────────────────────────────────────────────────────
-- Pure job state (no UI or processes): what is running, where, and the last
-- result. Several can run at once, even in the same buffer if they do not overlap.
local M = {}

---@class AgentJob
---@field id integer
---@field action table
---@field target AgentTarget
---@field buf integer
---@field anchor integer
---@field selection AgentSelection
---@field system string
---@field prompt string
---@field presenter table
---@field state "running"|"done"|"error"|"cancelled"
---@field t0 integer
---@field handle vim.SystemObj?
---@field partial string
---@field result table?

---@type table<integer, AgentJob>
local running = {}
local seq = 0

---@type AgentJob?
local last

---@param fields table
---@return AgentJob
function M.create(fields)
  seq = seq + 1
  local job = vim.tbl_extend("force", { id = seq, state = "running", t0 = vim.uv.hrtime(), partial = "" }, fields)
  running[job.id] = job
  return job
end

---@param job AgentJob
function M.finish(job)
  running[job.id] = nil
  if job.state == "done" then
    last = job
  end
end

---@return AgentJob[]
function M.running()
  local list = vim.tbl_values(running)
  table.sort(list, function(a, b)
    return a.id < b.id
  end)
  return list
end

---@return AgentJob?
function M.last()
  return last
end

--- Is there a job modifying code that overlaps this range?
---@param buf integer
---@param first integer
---@param last_line integer
---@return boolean
function M.overlaps(buf, first, last_line)
  for _, job in pairs(running) do
    if job.buf == buf and job.action.output == "replace" then
      local f, l = require("agent.anchor").range(buf, job.anchor)
      if f and f <= last_line and first <= l then
        return true
      end
    end
  end
  return false
end

---@param job AgentJob
---@return number seconds
function M.elapsed(job)
  return (vim.uv.hrtime() - job.t0) / 1e9
end

--- Text for the statusline ("" if nothing is running)
---@return string
function M.statusline()
  local list = M.running()
  if #list == 0 then
    return ""
  end
  local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = frames[math.floor(vim.uv.hrtime() / 1e8) % #frames + 1]
  local label = #list == 1 and list[1].action.label or (#list .. " tasks")
  return (" %s agent %s "):format(frame, label)
end

return M
