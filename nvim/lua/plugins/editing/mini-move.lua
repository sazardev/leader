-- Move lines/blocks with Alt+hjkl
local DIRECTIONS = { h = "left", j = "down", k = "up", l = "right" }

local keys, mappings = {}, {}
for key, direction in pairs(DIRECTIONS) do
  local lhs = "<A-" .. key .. ">"
  table.insert(keys, { lhs, mode = { "n", "v" }, desc = "Edit move line/block " .. direction })
  mappings[direction] = lhs
end

return {
  "echasnovski/mini.move",
  -- VeryLazy in addition to keys: <A-h> in normal mode is freed by core/keymaps/cleanup.lua after
  -- lazy's stub is created, so the plugin must be loaded for it to map it
  event = "VeryLazy",
  keys = keys,
  opts = { mappings = mappings },
  config = function(_, opts)
    require("mini.move").setup(opts)
  end,
}
