-- DDD missing: what is missing around the target for a complete DDD slice, including the connections
local principles = require "agent.ddd.principles"

return {
  label = "ddd missing",
  desc = "ddd missing",
  key = "m",
  scope = "function",
  context = { "rules", "ddd", "types", "outline" },
  output = "text",
  system = function(env)
    return ("TASK list what is missing around <target> for a complete DDD slice, using <ddd> (it holds facts from static analysis: related pieces, violations, naming). Markdown in %s, max 8 lines, most important first, only things that do NOT exist yet. One line each: `- [ ] <piece> — <file path following the naming in <ddd>> — <why, max 10 words>`. Cover ports, implementations, use cases, mappers/DTOs, wiring in the composition root (connections), domain errors/events and tests. No intro, no summary.\n%s"):format(
      env.language,
      principles.RULES
    )
  end,
  task = function()
    return "What is missing around <target>?"
  end,
}
