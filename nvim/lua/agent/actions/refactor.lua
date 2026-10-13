-- Refactorizar: aplica EXACTAMENTE la instrucción que escribes, sin cambiar el comportamiento
local protocol = require "agent.protocol"

return {
  label = "refactor",
  desc = "refactor",
  key = "R",
  scope = "function",
  context = { "rules", "types", "callees", "outline" },
  output = "replace",
  input = "what should change?",
  system = function()
    return "TASK refactor: apply the user's instruction to <target>; keep its behaviour and public signature unless told otherwise.\n"
      .. protocol.REPLACE_RULES
  end,
  task = function(env)
    return "Instruction: " .. env.input
  end,
}
