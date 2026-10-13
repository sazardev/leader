-- ── Agent Repository context (global): <leader>aP ────────────────────────────
-- Persistence level of the hexagonal architecture: adapters against a port, a table and a sibling example.
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
