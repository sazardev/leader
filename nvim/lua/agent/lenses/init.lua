-- ── Lentes: revisiones con un solo foco (<leader>aL) ─────────────────────────
-- security | performance | concurrency | errors | api. Salen como diagnósticos (`[security]`) en la línea exacta, así
-- `af`/`aF` los arreglan. Cada una descarta antes de gastar nada lo que no le toca (`gate`), y las de patrón
-- (rendimiento, errores, api) usan el modelo ligero. Mismo pipeline y experiencia que `review`.
--   actions/    una lente por archivo (registro propio)
local M = {}

---@param name string
---@param opts { range: integer[]? }?
function M.run(name, opts)
  require("agent.pipeline").run(require("agent.lenses.actions").get(name), opts)
end

return M
