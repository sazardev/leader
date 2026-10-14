-- ── Agent events ─────────────────────────────────────────────────────────────
-- A tiny publish/subscribe bus. The pieces that PRODUCE something (the replace presenter accepting a proposal, the
-- runner finishing a job) announce it here and know nothing about who listens (verification, batches, the proposal
-- queue); the pieces that REACT subscribe. That is what lets a feature be added without editing the flow it hangs from.
--
--   proposal.accepting   { job, buf, first, last, lines }   just BEFORE the proposal is written into the buffer
--   proposal.accepted    { job, buf, first, last, lines }   right AFTER (first/last = where the new code now is)
--   proposal.dropped     { job, how = "rejected"|"refined"|"discarded" }
--   job.settled          { job, outcome = "done"|"error"|"cancelled"|"denied" }
--
-- A handler that fails never takes the emitter down (pcall), and handlers run in the order they were registered.
local M = {}

---@type table<string, fun(payload: table)[]>
local handlers = {}

---@param event string
---@param fn fun(payload: table)
---@return fun() off unsubscribes
function M.on(event, fn)
  handlers[event] = handlers[event] or {}
  table.insert(handlers[event], fn)
  return function()
    for i, h in ipairs(handlers[event] or {}) do
      if h == fn then
        table.remove(handlers[event], i)
        return
      end
    end
  end
end

---@param event string
---@param payload table
function M.emit(event, payload)
  for _, fn in ipairs(vim.list_slice(handlers[event] or {})) do
    pcall(fn, payload)
  end
end

--- Forgets every handler (tests)
function M.reset()
  handlers = {}
end

return M
