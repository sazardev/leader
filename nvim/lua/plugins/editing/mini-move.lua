-- Mover líneas/bloques con Alt+hjkl
local DIRECTIONS = { h = "left", j = "down", k = "up", l = "right" }

local keys, mappings = {}, {}
for key, direction in pairs(DIRECTIONS) do
  local lhs = "<A-" .. key .. ">"
  table.insert(keys, { lhs, mode = { "n", "v" }, desc = "Edit move line/block " .. direction })
  mappings[direction] = lhs
end

return {
  "echasnovski/mini.move",
  -- VeryLazy además de keys: <A-h> en normal lo libera core/keymaps/cleanup.lua después de
  -- crearse el stub de lazy, así que hay que cargar el plugin para que lo mapee
  event = "VeryLazy",
  keys = keys,
  opts = { mappings = mappings },
  config = function(_, opts)
    require("mini.move").setup(opts)
  end,
}
