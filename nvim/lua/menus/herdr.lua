-- ── Contexto Herdr (global): <leader>W ───────────────────────────────────────
-- The workspace Herdr runs: what every agent is doing, and how this nvim sits inside it.
return {
  name = "Herdr",
  prefix = "W",
  global = true,
  maps = {
    {
      "a",
      "agents (what the workspace is doing)",
      function()
        require("herdr.panel").open()
      end,
    },
    {
      "s",
      "setup (install and configure)",
      function()
        require("herdr.setup").open()
      end,
    },
  },
}
