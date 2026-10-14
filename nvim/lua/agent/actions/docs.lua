-- Document: add or update the idiomatic doc comment, without touching the code
local protocol = require "agent.protocol"

return {
  label = "docs",
  verify = false, -- only comments change: nothing to verify
  desc = "docs",
  key = "d",
  scope = "function",
  context = { "rules", "types" },
  output = "replace",
  tier = "light", -- little reasoning needed: the small model does it fine
  input = "what should the docs focus on?",
  input_optional = true,
  system = function(env)
    return ("TASK document in %s: add or update the idiomatic doc comment of <target> (godoc, TSDoc, docstring, rustdoc...), starting with the name where idiomatic. Cover behaviour, parameters, returns and errors, using the real types in <types>. The code stays byte-identical.\n%s"):format(
      env.language,
      protocol.REPLACE_RULES
    )
  end,
  task = function()
    return "Document <target>."
  end,
}
