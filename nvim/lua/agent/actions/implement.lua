-- Implementar: completa la función bajo el cursor a partir de su firma, su doc o su nombre
local protocol = require "agent.protocol"

return {
  label = "implement",
  desc = "implement",
  key = "i",
  scope = "function",
  context = { "rules", "contracts", "schema", "types", "callees", "outline", "diagnostics" },
  examples = true,
  output = "replace",
  input = "what should it do?",
  input_optional = true,
  system = function()
    return "TASK implement: write <target> in full. Its name, signature, doc, TODO/stub and the task text are the spec (the task text wins). Complete partial signatures; keep code that is already correct.\n"
      .. protocol.REPLACE_RULES
  end,
  task = function()
    return "Implement <target>."
  end,
}
