-- Move lines/blocks with Alt+hjkl. <A-h> in normal mode is NvChad's horizontal terminal (the visual block
-- still moves left), so mini.move's `line_left` is off.
local DIRECTIONS = { h = "left", j = "down", k = "up", l = "right" }

local keys, mappings = {}, {}
for key, direction in pairs(DIRECTIONS) do
  local lhs = "<A-" .. key .. ">"
  table.insert(keys, { lhs, mode = key == "h" and { "v" } or { "n", "v" }, desc = "Edit move line/block " .. direction })
  mappings[direction] = lhs
end
mappings.line_left = ""

return {
  "echasnovski/mini.move",
  event = "VeryLazy",
  keys = keys,
  opts = { mappings = mappings },
  config = function(_, opts)
    require("mini.move").setup(opts)
  end,
}
