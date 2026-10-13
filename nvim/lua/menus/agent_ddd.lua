-- ── Contexto Agent DDD (global): <leader>aD ──────────────────────────────────
-- Función aparte del agente normal: sigue las capas y la nomenclatura de TU proyecto (agent/ddd).
-- Las acciones salen de su registro; `d` es el diagnóstico estático de todo el proyecto (0 tokens).
local function ddd()
  return require "agent.ddd"
end

local maps = {}
for _, action in ipairs(require("agent.ddd.actions").list()) do
  maps[#maps + 1] = {
    action.key,
    action.desc,
    function()
      ddd().run(action.short)
    end,
    { "n", "x" },
  }
end

maps[#maps + 1] = {
  "d",
  "ddd diagnose",
  function()
    ddd().diagnose()
  end,
}
maps[#maps + 1] = {
  "c",
  "ddd clear",
  function()
    ddd().clear()
  end,
}

return {
  name = "Agent DDD",
  prefix = "aD",
  global = true,
  maps = maps,
}
