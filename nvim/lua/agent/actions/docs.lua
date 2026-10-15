-- Document: add or update the idiomatic doc comment, without touching the code
local docplace = require "agent.docplace"
local protocol = require "agent.protocol"

return {
  label = "docs",
  verify = false, -- only comments change: nothing to verify
  desc = "docs",
  key = "d",
  scope = "function",
  context = { "rules", "types" },
  output = "replace",
  merge = docplace.merge, -- the model returns ONLY the comment; the code is never retyped (so it cannot change)
  tier = "light", -- little reasoning needed: the small model does it fine
  input = "what should the docs focus on?",
  input_optional = true,
  system = function(env)
    return ("TASK document in %s: add or update the idiomatic doc comment of <target> (godoc, TSDoc, docstring, rustdoc...), starting with the name where idiomatic. Cover behaviour, parameters, returns and errors, using the real types in <types>. The code is not part of your answer.\n%s"):format(
      env.language,
      protocol.DOC_RULES
    )
  end,
  task = function()
    return "Document <target>."
  end,
}
