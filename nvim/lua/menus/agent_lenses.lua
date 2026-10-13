-- ── Contexto Agent Lenses (global): <leader>aL ───────────────────────────────
-- Revisiones con un solo foco; las lentes salen del registro (agent/lenses/actions).
local maps = {}
for _, action in ipairs(require("agent.lenses.actions").list()) do
  maps[#maps + 1] = {
    action.key,
    "lens " .. action.desc,
    function()
      require("agent.lenses").run(action.short)
    end,
    { "n", "x" },
  }
end

return {
  name = "Agent Lenses",
  prefix = "aL",
  global = true,
  maps = maps,
}
