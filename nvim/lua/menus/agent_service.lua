-- ── Agent Service context (global): <leader>aS ───────────────────────────────
-- Application level of the hexagonal architecture: services / use cases that orchestrate the domain and call ports.
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
