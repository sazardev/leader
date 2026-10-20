-- ── Context LSP (global): <leader>L ──────────────────────────────────────────
local function ctl()
  return require "utils.lspctl"
end

return {
  name = "LSP",
  prefix = "L",
  global = true,
  maps = {
    {
      "s",
      "stop (this buffer)",
      function()
        ctl().stop()
      end,
    },
    {
      "S",
      "stop all (every project)",
      function()
        ctl().stop_all()
      end,
    },
    {
      "r",
      "restart (this buffer)",
      function()
        ctl().restart()
      end,
    },
    {
      "p",
      "pause or resume everything",
      function()
        ctl().toggle_pause()
      end,
    },
    {
      "i",
      "info (what is loading)",
      function()
        require("utils.log").info("LSP: " .. ctl().status())
      end,
    },
  },
}
