-- File "favorites" for the current work cycle
local function list()
  return require("harpoon"):list()
end

local keys = {
  {
    "<leader>ha",
    function()
      list():add()
    end,
    desc = "Harpoon add file",
  },
  {
    "<leader>hm",
    function()
      require("harpoon").ui:toggle_quick_menu(
        list(),
        { border = require("ui.flat").border(), title = { { "HARPOON ", "FlatModalTitle" } }, title_pos = "left" }
      )
    end,
    desc = "Harpoon menu",
  },
}
for i = 1, 4 do
  table.insert(keys, {
    "<leader>h" .. i,
    function()
      list():select(i)
    end,
    desc = "Harpoon jump to file " .. i,
  })
end

return {
  "ThePrimeagen/harpoon",
  branch = "harpoon2",
  keys = keys,
  config = function()
    local harpoon = require "harpoon"
    harpoon:setup {}
    if require("ui.flat").enabled() then
      -- the demo's modal: no line numbers, the chosen file a blue chip as wide as its name
      harpoon:extend {
        UI_CREATE = function(cx)
          vim.wo[cx.win_id].number = false
          vim.wo[cx.win_id].statuscolumn = ""
          require("ui.flat.chips").follow(cx.bufnr, cx.win_id)
          require("ui.flat.motion").enter { cx.win_id }
        end,
      }
    end
  end,
}
