-- Multi-file plan: on a type or function, say what should change and it finds where that reaches, proposes ordered steps for
-- you to edit, and runs them as proposals. See agent/plan.
return {
  label = "plan",
  desc = "plan across files",
  key = "p",
  advanced = true,
  stability = "plan",
  modes = { "n" },
  standalone = true,
  output = "replace",
  handler = function(session)
    require("agent.plan").start(session)
  end,
}
