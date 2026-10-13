-- DDD review: violations of the DDD and SOLID rules, as diagnostics on their line
local principles = require "agent.ddd.principles"
local protocol = require "agent.protocol"

return {
  label = "ddd review",
  desc = "ddd review",
  key = "r",
  source = "ddd", -- the findings are told apart from those of `review` by the diagnostic source
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
