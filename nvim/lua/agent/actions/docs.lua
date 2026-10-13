-- Documentar: añade o actualiza el comentario de documentación idiomático, sin tocar el código
local protocol = require "agent.protocol"

return {
  label = "docs",
  desc = "docs",
  key = "d",
  scope = "function",
  context = { "rules", "types" },
  output = "replace",
  tier = "light", -- poco razonamiento: lo hace bien el modelo pequeño
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
