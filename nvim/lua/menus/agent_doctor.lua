-- ── Agent Doctor context (global): <leader>aX ───────────────────────────────
-- A troubleshooting agent: the app does not build, does not start, dies at runtime, or something is off before you compile.
-- Hand it the failure the easy way (the terminal, the clipboard, a command it runs, a log, your words, a selection, or just a
-- check of the project): free evidence and known causes first, the model once after you see what is sent.
local function doctor()
  return require "agent.doctor"
end

return {
  name = "Agent Doctor",
  prefix = "aX",
  global = true,
  maps = {
    {
      "x",
      "doctor diagnose",
      function()
        doctor().auto()
      end,
    },
    {
      "p",
      "doctor paste",
      function()
        doctor().paste()
      end,
    },
    {
      "c",
      "doctor command",
      function()
        doctor().command()
      end,
    },
    {
      "d",
      "doctor describe",
      function()
        doctor().describe()
      end,
    },
    {
      "l",
      "doctor log",
      function()
        doctor().log()
      end,
    },
    {
      "h",
      "doctor health",
      function()
        doctor().health()
      end,
    },
    {
      "s",
      "doctor selection",
      function()
        doctor().selection()
      end,
      { "x" },
    },
    {
      "r",
      "doctor reopen",
      function()
        doctor().reopen()
      end,
    },
  },
}
