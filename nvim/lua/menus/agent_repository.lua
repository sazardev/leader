-- ── Contexto Agent Repository (global): <leader>aP ───────────────────────────
-- Nivel de persistencia de la arquitectura hexagonal: adaptadores contra un puerto, una tabla y un ejemplo hermano.
local function repository()
  return require "agent.repository"
end

local maps = {}
for _, action in ipairs(require("agent.repository.actions").list()) do
  maps[#maps + 1] = {
    action.key,
    action.desc,
    function()
      repository().run(action.short)
    end,
    { "n", "x" },
  }
end

maps[#maps + 1] = {
  "c",
  "repo check",
  function()
    repository().check()
  end,
}

return {
  name = "Agent Repository",
  prefix = "aP",
  global = true,
  maps = maps,
}
