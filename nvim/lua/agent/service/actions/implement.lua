-- Service implement: a use case / service method that orchestrates the domain and calls its ports
local principles = require "agent.ddd.principles"
local protocol = require "agent.protocol"

return {
  label = "service implement",
  desc = "service implement",
  key = "i",
  scope = "function",
  examples = true,
  context = { "rules", "ddd", "ports", "types", "callees", "diagnostics" },
  output = "replace",
  input = "what should it do?",
  input_optional = true,
  system = function()
    return "TASK implement this application-service method (use case): orchestrate the domain and call ONLY the ports in <ports>, with their exact method names and signatures; never invent a port method (if one is missing, say so in `note:`). Business rules belong to the domain entities: call their methods, do not re-implement them here. Pass the context, translate port errors into domain/application errors, and keep one use case per method. Follow the sibling example for structure and error handling.\n"
      .. principles.RULES
      .. "\n"
      .. protocol.REPLACE_RULES
  end,
  task = function()
    return "Implement <target>."
  end,
}
