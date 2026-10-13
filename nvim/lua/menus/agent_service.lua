-- ── Contexto Agent Service (global): <leader>aS ──────────────────────────────
-- Nivel de aplicación de la arquitectura hexagonal: servicios / casos de uso que orquestan el dominio y llaman a puertos.
local function service()
  return require "agent.service"
end

local maps = {}
for _, action in ipairs(require("agent.service.actions").list()) do
  maps[#maps + 1] = {
    action.key,
    action.desc,
    function()
      service().run(action.short)
    end,
    { "n", "x" },
  }
end

maps[#maps + 1] = {
  "d",
  "service deps",
  function()
    service().deps()
  end,
}

return {
  name = "Agent Service",
  prefix = "aS",
  global = true,
  maps = maps,
}
