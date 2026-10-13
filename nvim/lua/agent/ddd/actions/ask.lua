-- DDD ask: una pregunta de arquitectura sobre lo que ves, con las capas y piezas reales del proyecto
local principles = require "agent.ddd.principles"

return {
  label = "ddd ask",
  desc = "ddd ask",
  key = "a",
  scope = "function",
  context = { "rules", "ddd", "types", "callees" },
  output = "text",
  input = "what do you want to know?",
  system = function(env)
    return ("TASK answer a DDD / architecture question about <target> in %s, Markdown: answer first, citing the layers, ports and files in <ddd>. If the message lacks the information, say exactly what is missing; do not guess.\n%s"):format(
      env.language,
      principles.RULES
    )
  end,
  task = function(env)
    return "Question about <target>: " .. env.input
  end,
}
