-- "Favoritos" de archivos del ciclo de trabajo
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
      require("harpoon").ui:toggle_quick_menu(list())
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
    require("harpoon").setup {}
  end,
}
