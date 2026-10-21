-- Settings panel: the inline agent (see prefs/init.lua for the item contract). The model and backend have their own
-- selector (<leader>am); the rest are the settings that change how it behaves.
local LANGUAGES = { "English", "Spanish", "Portuguese", "French", "German", "Italian" }

return {
  {
    group = "Agent",
    label = "Model",
    kind = "action",
    run = function()
      require("agent").settings()
    end,
  },
  {
    group = "Agent",
    label = "Answer language",
    kind = "choice",
    id = "agent.language",
    choices = vim.tbl_map(function(name)
      return { value = name, label = name }
    end, LANGUAGES),
  },
  { group = "Agent", label = "Verify after accepting", kind = "toggle", id = "agent.verify.enabled" },
  { group = "Agent", label = "Spend guard", kind = "toggle", id = "agent.budget.enabled" },
  { group = "Agent", label = "Smaller models get help", kind = "toggle", id = "agent.capability.enabled" },
  { group = "Agent", label = "Escalate to the main model", kind = "toggle", id = "agent.cascade.enabled" },
  { group = "Agent", label = "Preview prompt before sending", kind = "toggle", id = "agent.trust.preview" },
  { group = "Agent", label = "Experimental features", kind = "toggle", id = "agent.experimental", restart = true },
}
