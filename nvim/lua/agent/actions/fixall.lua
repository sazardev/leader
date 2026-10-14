-- Fix ALL the findings and diagnostics of the file: one proposal per function that holds any, asked once with the total
-- estimate, reviewed through the queue. The model work is the `fix block` action's; this one only decides what to ask.
return {
  label = "fix all",
  desc = "fix all",
  key = "a",
  advanced = true,
  modes = { "n" },
  standalone = true,
  output = "replace",
  handler = function()
    require("agent.fixall").run()
  end,
}
