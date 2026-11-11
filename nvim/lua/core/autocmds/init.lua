-- ── Autocmds: one module per responsibility ──────────────────────────────────
local M = {}

local MODULES = {
  "reload",
  "treesitter",
  "session",
  "ui",
  "appearance",
  "navigation",
  "last-position",
  "autoread",
  "gitcommit",
  "agent",
  "diagnostics",
  "herdr",
}

function M.setup()
  require "nvchad.autocmds"
  for _, name in ipairs(MODULES) do
    require("core.autocmds." .. name).setup()
  end
end

return M
