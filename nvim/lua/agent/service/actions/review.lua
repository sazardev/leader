-- Service review: what is specific to an application service, checked against the ports it really has
local principles = require "agent.ddd.principles"
local protocol = require "agent.protocol"

return {
  label = "service review",
  desc = "service review",
  key = "r",
  source = "service",
  scope = "function",
  context = { "rules", "ddd", "diagnostics", "ports", "types", "callees" },
  output = "findings",
  numbered = true,
  system = function(env)
    return ("TASK review this application service (messages in %s): defects specific to a use case, checked against the ports in <ports>: calls to port methods that do not exist or with the wrong arguments, business rules implemented here instead of in the domain, port or infrastructure details leaking in, missing context propagation, errors swallowed or returned untranslated, steps that are not atomic or are in a risky order (side effects before the state is saved), repeated port calls inside loops (N+1), more than one use case in one method.\n%s\n%s"):format(
      env.language,
      principles.RULES,
      protocol.FINDINGS_RULES
    )
  end,
  task = function()
    return "Review <target> as an application service."
  end,
}
