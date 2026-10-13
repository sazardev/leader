-- Preguntar: una pregunta concreta sobre lo que estás viendo (un solo disparo, sin chat)
return {
  label = "ask",
  desc = "ask",
  key = "a",
  scope = "function",
  context = { "rules", "types", "callees", "outline", "diagnostics" },
  output = "text",
  input = "what do you want to know?",
  system = function(env)
    return ("TASK answer in %s, Markdown: answer first, reasoning only if needed. If the message lacks the information, say exactly what is missing; do not guess."):format(
      env.language
    )
  end,
  task = function(env)
    return "Question about <target>: " .. env.input
  end,
}
