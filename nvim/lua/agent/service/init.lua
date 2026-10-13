-- ── SERVICE level: application services / use cases (<leader>aS) ─────────────
-- They orchestrate the domain and call ports; the level's own context is `ports`.
--   run(name)   implement | review: LLM actions (same pipeline and experience)
--   deps()      do its dependencies exist, are they called correctly and are they wired? Local analysis, 0 tokens
--
--   ports.lua   interfaces the service receives, with their signatures   actions/   the level's actions (own registry)
--   deps.lua    the local diagnosis
local M = {}

---@param name string "implement" | "review"
---@param opts { range: integer[]? }?
function M.run(name, opts)
  require("agent.pipeline").run(require("agent.service.actions").get(name), opts)
end

function M.deps()
  require("agent.service.deps").run()
end

return M
