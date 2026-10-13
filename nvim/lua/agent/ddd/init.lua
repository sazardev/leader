-- ── DDD: fachada ─────────────────────────────────────────────────────────────
-- Una función aparte del agente normal (<leader>aD):
--   run(name)    acciones con el LLM (implement, review, missing, ask): mismo pipeline y misma experiencia, pero
--                con la sección <ddd> (capas, nomenclatura, piezas relacionadas, violaciones) y reglas de DDD
--   diagnose()   análisis estático de TODO el proyecto, sin LLM (0 tokens): violaciones, huecos y conexiones
--
--   index.lua      recorrido del proyecto (capa, imports, tipos) con caché       imports.lua  imports por lenguaje
--   layers.lua     qué es cada directorio y quién puede depender de quién        naming.lua   nomenclatura deducida
--   rules.lua      reglas: dependencias, frameworks, nombres, agregados, cableado
--   profile.lua    la sección <ddd> compacta para el modelo                      idioms.lua   un modismo por lenguaje
--   actions/       acciones DDD (registro propio)                                diagnose.lua informe + diagnósticos
local M = {}

--- Ejecuta una acción DDD sobre la función bajo el cursor (o la selección visual)
---@param name string "implement" | "review" | "missing" | "ask"
---@param opts { range: integer[]? }?
function M.run(name, opts)
  require("agent.pipeline").run(require("agent.ddd.actions").get(name), opts)
end

--- Diagnóstico estático de todo el proyecto (gratis)
function M.diagnose()
  require("agent.ddd.diagnose").run()
end

--- Quita las violaciones del diagnóstico de DDD de todo el proyecto, también de lo guardado
function M.clear()
  require("agent.ddd.diagnose").clear()
  require("utils.log").info "Agent: DDD diagnosis cleared"
end

return M
