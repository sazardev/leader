-- ── Nivel REPOSITORY: adaptadores de persistencia (<leader>aP) ───────────────
-- Se construyen contra un puerto, una tabla y un ejemplo hermano; el descubrimiento vive en contracts/.
--   run(name)   port | implement | review: acciones con el LLM (mismo pipeline y experiencia que el agente normal)
--   check()     ¿cumple el adaptador su puerto y su tabla? Análisis local, 0 tokens
--
--   contracts/   puerto, métodos que faltan, ejemplo hermano, esquema (SQL/Prisma) y dialecto
--   actions/     acciones del nivel (registro propio)         check.lua   el diagnóstico local
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
