-- ── Autocmds: un módulo por responsabilidad ──────────────────────────────────
local M = {}

local MODULES = { "reload", "treesitter", "ui", "appearance", "navigation", "last-position", "autoread", "session", "gitcommit", "agent", "diagnostics" }

function M.setup()
  require "nvchad.autocmds"
  for _, name in ipairs(MODULES) do
    require("core.autocmds." .. name).setup()
  end
end

return M
