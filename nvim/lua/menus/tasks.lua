-- ── Run context (global): <leader>R ──────────────────────────────────────────
-- The targets of the project's Makefile in one picker, run in the integrated terminal (lua/tasks). It works only with a
-- Makefile; `c` creates one from a preset when there is none. No model: it only asks make what it has.
local function tasks()
  return require "tasks"
end

return {
  name = "Run",
  prefix = "R",
  global = true,
  maps = {
    {
      "r",
      "pick task",
      function()
        tasks().pick()
      end,
    },
    {
      "l",
      "last task",
      function()
        tasks().last()
      end,
    },
    {
      "d",
      "default task",
      function()
        tasks().default()
      end,
    },
    {
      "a",
      "last with args",
      function()
        tasks().last { ask = true }
      end,
    },
    {
      "p",
      "dry run",
      function()
        tasks().pick { dry = true }
      end,
    },
    {
      "o",
      "output terminal",
      function()
        tasks().output()
      end,
    },
    {
      "q",
      "output to quickfix",
      function()
        tasks().quickfix()
      end,
    },
    {
      "s",
      "stop task",
      function()
        tasks().stop()
      end,
    },
    {
      "c",
      "create Makefile",
      function()
        tasks().create()
      end,
    },
  },
}
