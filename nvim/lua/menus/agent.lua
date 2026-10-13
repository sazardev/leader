-- ── Contexto Agent (global): <leader>a ───────────────────────────────────────
-- Las acciones salen del registro (agent/actions): añadir una no obliga a tocar este
-- archivo. Funcionan en normal (función bajo el cursor) y en visual (la selección).
-- Aceptar/rechazar una propuesta NO tiene entrada aquí: son ⏎/⎋ sobre la propuesta.
local function agent()
  return require "agent"
end

local maps = {}
for _, action in ipairs(require("agent.actions").list()) do
  if not action.enabled or action.enabled() then
    maps[#maps + 1] = {
      action.key,
      action.desc,
      function()
        agent().run(action.name)
      end,
      action.modes or { "n", "x" },
    }
  end
end

vim.list_extend(maps, {
  {
    "m",
    "model",
    function()
      agent().settings()
    end,
  },
  {
    "h",
    "history",
    function()
      agent().history()
    end,
  },
  {
    "c",
    "clear",
    function()
      agent().clear()
    end,
  },
  {
    "x",
    "stop",
    function()
      agent().stop()
    end,
  },
  {
    "l",
    "last answer",
    function()
      agent().last()
    end,
  },
})

return {
  name = "Agent",
  prefix = "a",
  global = true,
  maps = maps,
}
