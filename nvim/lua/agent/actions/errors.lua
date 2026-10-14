-- Fix from output: the errors a build left in the last terminal (or the quickfix list), grouped by function, asked once.
-- Runs nothing on a model until you confirm the estimate. `<leader>aAO` is the same but runs a command first.
return {
  label = "fix output",
  desc = "fix from output",
  key = "o",
  advanced = true,
  modes = { "n" },
  standalone = true,
  output = "replace",
  handler = function()
    require("agent.errors").run()
  end,
}
