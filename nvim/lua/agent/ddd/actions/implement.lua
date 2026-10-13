-- DDD implement: completa el código en la capa que le toca, con los nombres y modismos del proyecto
local principles = require "agent.ddd.principles"
local protocol = require "agent.protocol"

return {
  label = "ddd implement",
  desc = "ddd implement",
  key = "i",
  scope = "function",
  context = { "rules", "ddd", "contracts", "schema", "types", "callees", "diagnostics" },
  examples = true,
  output = "replace",
  input = "what should it do?",
  input_optional = true,
  system = function()
    return "TASK implement with DDD: write <target> in full, in the layer it belongs to. Spec = its name, signature, doc, TODO/stub and the task text (it wins). Business rules go in the domain, never in handlers or repositories. Follow <ddd>. If it belongs in another layer or needs a port or type that does not exist, implement anyway and say so in `note:`.\n"
      .. principles.RULES
      .. "\n"
      .. protocol.REPLACE_RULES
  end,
  task = function()
    return "Implement <target>."
  end,
}
