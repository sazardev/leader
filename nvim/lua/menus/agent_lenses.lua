-- ── Agent Lenses context (global): <leader>aL ────────────────────────────────
-- Reviews with a single focus; the lenses come from the registry (agent/lenses/actions).
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
  stability = "lenses",
  global = true,
  maps = maps,
}
