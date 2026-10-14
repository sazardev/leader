-- Fix from a command: asks which command to run (the project's build by default), runs it, and fixes what it prints.
return {
  label = "fix command",
  desc = "fix from a command",
  key = "O",
  advanced = true,
  modes = { "n" },
  standalone = true,
  output = "replace",
  handler = function()
    require("agent.errors").run_command()
  end,
}
