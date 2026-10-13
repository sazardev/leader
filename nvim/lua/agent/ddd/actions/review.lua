-- DDD review: violaciones de las reglas de DDD y de SOLID, como diagnósticos en su línea
local principles = require "agent.ddd.principles"
local protocol = require "agent.protocol"

return {
  label = "ddd review",
  desc = "ddd review",
  key = "r",
  source = "ddd", -- los hallazgos se distinguen de los de `review` en el origen del diagnóstico
  scope = "function",
  context = { "rules", "ddd", "diagnostics", "contracts", "schema", "types" },
  output = "findings",
  numbered = true,
  system = function(env)
    return ("TASK DDD review (messages in %s): find violations of the DDD rules and of SOLID in <target>: layer leakage, business rules outside the domain, anemic model, primitive obsession, invariants not enforced, a concrete dependency where an injected interface belongs, mixed responsibilities, names that break <ddd>. The violations listed in <ddd> are already known: do not repeat them.\n%s\n%s"):format(
      env.language,
      principles.RULES,
      protocol.FINDINGS_RULES
    )
  end,
  task = function()
    return "Review <target> against the DDD rules and <ddd>."
  end,
}
