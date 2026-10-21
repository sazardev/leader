-- ── Agent DDD context (global): <leader>aD ───────────────────────────────────
-- A feature separate from the normal agent: it follows the layers and naming of YOUR project (agent/ddd).
-- The actions come from its registry; `d` is the static diagnosis of the whole project (0 tokens).
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
  stability = "ddd",
  global = true,
  maps = maps,
}
