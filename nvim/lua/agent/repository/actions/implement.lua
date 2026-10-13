-- Repository implement: UN método de un adaptador de persistencia, con el puerto, el esquema y un ejemplo hermano
local protocol = require "agent.protocol"

return {
  label = "repository implement",
  desc = "repo implement",
  key = "i",
  scope = "function",
  examples = true,
  context = { "rules", "contracts", "schema", "types", "diagnostics" },
  output = "replace",
  input = "what should it do?",
  input_optional = true,
  system = function()
    return "TASK implement this repository method: it must match the signature the port declares in <contracts>. Follow the sibling example for structure, error handling and row mapping. Table and column names and the parameter style come only from <schema>; never invent columns (say so in `note:` if one is missing). Map rows to the entity exactly as <types> defines it. Pass the context and close what you open (rows, statements); wrap errors with the operation name; return the domain's not-found error for an empty result.\n"
      .. protocol.REPLACE_RULES
  end,
  task = function()
    return "Implement <target>."
  end,
}
