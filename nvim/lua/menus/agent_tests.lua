-- ── Contexto Agent Tests (global): <leader>aT ────────────────────────────────
-- Pruebas con el agente: las acciones salen del registro (agent/tests/actions); `g` es el análisis local (0 tokens).
local function tests()
  return require "agent.tests"
end

local maps = {}
for _, action in ipairs(require("agent.tests.actions").list()) do
  maps[#maps + 1] = {
    action.key,
    action.desc,
    function()
      tests().run(action.short)
    end,
    { "n", "x" },
  }
end

maps[#maps + 1] = {
  "g",
  "test gaps",
  function()
    tests().gaps()
  end,
}

return {
  name = "Agent Tests",
  prefix = "aT",
  global = true,
  maps = maps,
}
