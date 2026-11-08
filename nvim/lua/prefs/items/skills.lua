-- Settings panel: agent skills (see prefs/init.lua for the item contract).
return {
  { group = "Skills", label = "Enabled", kind = "toggle", id = "skills.enabled" },
  { group = "Skills", label = "Auto-suggest (0-config)", kind = "toggle", id = "skills.auto" },
  {
    group = "Skills",
    label = "Scope",
    kind = "choice",
    id = "skills.scope",
    choices = {
      { value = "project", label = ".agents/skills in this project" },
      { value = "global", label = "~/.config/opencode/skills (every project)" },
    },
  },
  {
    group = "Skills",
    label = "Marketplace",
    kind = "action",
    run = function()
      require("skills").open()
    end,
  },
  {
    group = "Skills",
    label = "Apply suggestions",
    kind = "action",
    run = function()
      require("skills").apply_suggestions()
    end,
  },
  {
    group = "Skills",
    label = "Check updates",
    kind = "action",
    run = function()
      require("skills.catalog").check_updates(function(ok, text)
        require("utils.log").info(ok and (text ~= "" and text or "Skills: up to date")
          or ("Skills: " .. (text or "check failed")))
      end)
    end,
  },
}
