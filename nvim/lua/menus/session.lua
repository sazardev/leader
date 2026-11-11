-- ── Contexto Session (global): <leader>P ─────────────────────────────────────
local function session()
  return require "utils.session"
end

return {
  name = "Session",
  prefix = "P",
  global = true,
  maps = {
    {
      "r",
      "restore session (this folder)",
      function()
        session().restore()
      end,
    },
    {
      "s",
      "select session (any project)",
      function()
        session().pick()
      end,
    },
    {
      "l",
      "restore last session",
      function()
        session().last()
      end,
    },
    {
      "w",
      "save session now",
      function()
        session().save()
      end,
    },
    {
      "x",
      "don't save on exit",
      function()
        session().stop()
      end,
    },
    {
      "q",
      "quit all (save session)",
      function()
        session().quit()
      end,
    },
  },
}
