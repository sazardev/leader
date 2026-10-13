-- ── Pruebas con el agente (<leader>aT) ───────────────────────────────────────
--   run(name)   write | mock | fix: acciones con el LLM (mismo pipeline y experiencia)
--   gaps()      qué funciones de la carpeta no tiene ninguna prueba. Local, 0 tokens
--
--   convention.lua  dónde viven las pruebas, framework y cómo correrlas   target.lua  el final del archivo de pruebas
--   run.lua         correr una prueba y limpiar su salida                  gaps.lua    el análisis local
--   actions/        las acciones del nivel (registro propio)
local M = {}

---@param name string "write" | "mock" | "fix"
---@param opts { range: integer[]? }?
function M.run(name, opts)
  require("agent.pipeline").run(require("agent.tests.actions").get(name), opts)
end

function M.gaps()
  require("agent.tests.gaps").run()
end

return M
