-- ── Nivel SERVICE: servicios de aplicación / casos de uso (<leader>aS) ───────
-- Orquestan el dominio y llaman a puertos; el contexto propio del nivel es `ports`.
--   run(name)   implement | review: acciones con el LLM (mismo pipeline y experiencia)
--   deps()      ¿existen, se llaman bien y están cableadas sus dependencias? Análisis local, 0 tokens
--
--   ports.lua   interfaces que recibe el servicio, con sus firmas       actions/   acciones del nivel (registro propio)
--   deps.lua    el diagnóstico local
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
