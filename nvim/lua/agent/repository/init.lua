-- ── REPOSITORY level: persistence adapters (<leader>aP) ──────────────────────
-- They are built against a port, a table and a sibling example; discovery lives in contracts/.
--   run(name)   port | implement | review: LLM actions (same pipeline and experience as the normal agent)
--   check()     does the adapter fulfil its port and its table? Local analysis, 0 tokens
--
--   contracts/   port, missing methods, sibling example, schema (SQL/Prisma) and dialect
--   actions/     level actions (own registry)                 check.lua   the local diagnosis
local M = {}

---@param name string "port" | "implement" | "review"
---@param opts { range: integer[]? }?
function M.run(name, opts)
  require("agent.pipeline").run(require("agent.repository.actions").get(name), opts)
end

function M.check()
  require("agent.repository.check").run()
end

return M
