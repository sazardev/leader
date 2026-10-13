-- Repository port: implements a whole adapter (e.g. a SQL repository) against the port it must fulfil
local protocol = require "agent.protocol"

return {
  label = "repository port",
  desc = "repo port",
  key = "p",
  scope = "type", -- the type under the cursor, or its receiver's if you are inside one of its methods
  examples = true, -- the `contracts` provider adds another implementation from the project as a style example
  context = { "rules", "contracts", "schema", "types", "diagnostics" },
  output = "replace",
  input = "anything special? (empty = all missing methods)",
  input_optional = true,
  system = function()
    return "TASK implement the port: <contracts> shows the interface <target> must satisfy and which of its methods are missing. Write <target> in full (keep what exists; add the dependencies it needs as constructor-injected fields), then the constructor if it is missing, then EVERY missing method in the port's order. Follow the sibling example for structure, error handling and mapping. Take table and column names and the parameter style only from <schema>; never invent columns (if one is not in the schema or the entity, say so in `note:`). Do not repeat methods that already exist. Map rows to the entity exactly as <types> defines it.\n"
      .. protocol.REPLACE_RULES
  end,
  task = function()
    return "Implement the missing methods of the port in <target>."
  end,
}
