-- Review: real findings as diagnostics on the exact line
local protocol = require "agent.protocol"

return {
  label = "review",
  desc = "review",
  key = "r",
  scope = "function",
  context = { "rules", "diagnostics", "contracts", "schema", "types", "callees" },
  output = "findings",
  numbered = true,
  system = function(env)
    return ("TASK review (messages in %s): find real defects in <target>.\n%s"):format(
      env.language,
      protocol.FINDINGS_RULES
    )
  end,
  task = function()
    return "Review <target>. Check field use against <types> and calls against <callees>."
  end,
}
