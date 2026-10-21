-- ── Run history: facade ──────────────────────────────────────────────────────
-- `record` when a job finishes and `event` when the user decides (accept, reject...). It must never
-- break the action: any write failure is ignored.
local settings = require("core.settings").agent.history
local store = require "agent.runs.store"

local M = {}

local compacted = false

---@param job AgentJob
---@param status "done"|"error"|"cancelled"
---@param err string?
function M.record(job, status, err)
  if not settings.enabled then
    return
  end
  pcall(function()
    if not compacted then
      compacted = true
      store.compact()
    end
    local entry = require("agent.runs.record").build(job, status, err)
    job.record_id = entry.id
    store.append(entry)
    require("agent.spend").add(entry.usage.cost)
  end)
end

--- A call that is not an action over code (a commit draft, a staged-code review, a plan): same metrics, so the spend
--- report and the budget see it. `output = "oneshot"`.
---@param req { action: string, system: string, prompt: string }
---@param sel AgentSelection
---@param status "done"|"error"
---@param usage table?
---@param ms integer
---@param response string? text returned (or the error)
function M.call(req, sel, status, usage, ms, response)
  if not settings.enabled then
    return
  end
  pcall(function()
    usage = usage or {}
    local entry = {
      t = "run",
      id = ("%d-c%d"):format(vim.uv.hrtime() / 1e6 % 1e9, math.random(1000)),
      ts = os.time(),
      action = req.action,
      output = "oneshot",
      backend = sel.backend,
      model = sel.model,
      tier = sel.tier,
      status = status,
      error = status == "error" and response or nil,
      ms = ms,
      cwd = vim.fn.getcwd(),
      name = req.action,
      kind = "oneshot",
      usage = {
        tokens_in = usage.tokens_in,
        tokens_out = usage.tokens_out,
        cache_read = usage.cache_read,
        cache_write = usage.cache_write,
        cost = usage.cost,
      },
      chars = { system = #req.system, message = #req.prompt, target = 0, context = 0 },
    }
    if settings.store_text then
      entry.system, entry.prompt, entry.response = req.system, req.prompt, response
    end
    store.append(entry)
    require("agent.spend").add(entry.usage.cost)
  end)
end

---@param job AgentJob
---@param name string "accepted" | "rejected" | "discarded" | "unchanged" | "findings" | "shown"
---@param detail any?
function M.event(job, name, detail)
  if not (settings.enabled and job.record_id) then
    return
  end
  pcall(store.append, { t = "event", id = job.record_id, ts = os.time(), event = name, detail = detail })
end

return M
