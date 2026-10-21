-- Refactor: applies EXACTLY the instruction you type, without changing behaviour
local protocol = require "agent.protocol"

return {
  label = "refactor",
  desc = "refactor",
  key = "R",
  scope = "function",
  context = { "rules", "types", "callees", "callers", "outline", "gitlog" },
  output = "replace",
  decomposable = true,
  input = "what should change?",
  system = function()
    return "TASK refactor: apply the user's instruction to <target>; keep its behaviour and public signature unless told otherwise.\n"
      .. protocol.REPLACE_RULES
  end,
  task = function(env)
    return "Instruction: " .. env.input
  end,
}
