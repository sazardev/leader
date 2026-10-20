-- ── Settings context (global): <leader>S ─────────────────────────────────────
-- `p` opens the panel with everything that can be changed (lua/prefs); the rest are the few that earn a key of their own.
local function prefs()
  return require "prefs"
end

return {
  name = "Settings",
  prefix = "S",
  global = true,
  maps = {
    {
      "p",
      "panel",
      function()
        prefs().open()
      end,
    },
    {
      "t",
      "toggle theme",
      function()
        require("appearance").toggle()
      end,
    },
    {
      "f",
      "format on save",
      function()
        prefs().cycle(prefs().find "format_on_save.enabled")
      end,
    },
    {
      "l",
      "plugins",
      function()
        vim.cmd "Lazy"
      end,
    },
    {
      "M",
      "tools",
      function()
        vim.cmd "Mason"
      end,
    },
    {
      "i",
      "info",
      function()
        require("prefs.info").open()
      end,
    },
    {
      "u",
      "updates",
      function()
        require("update.panel").open()
      end,
    },
  },
}
