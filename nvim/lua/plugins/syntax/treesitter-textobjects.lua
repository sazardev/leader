-- Textobjects por treesitter (af/if/ac/ic, ]f/[f).
local function select(query)
  return function()
    require("nvim-treesitter-textobjects.select").select_textobject(query, "textobjects")
  end
end

local function goto_function(direction)
  return function()
    require("nvim-treesitter-textobjects.move")["goto_" .. direction .. "_start"]("@function.outer", "textobjects")
  end
end

return {
  "nvim-treesitter/nvim-treesitter-textobjects",
  branch = "main",
  dependencies = { "nvim-treesitter/nvim-treesitter" },
  -- La rama "main" ya no lee keymaps desde opts: se definen a mano.
  keys = {
    { "af", select "@function.outer", mode = { "x", "o" }, desc = "Textobject outer function" },
    { "if", select "@function.inner", mode = { "x", "o" }, desc = "Textobject inner function" },
    { "ac", select "@class.outer", mode = { "x", "o" }, desc = "Textobject outer class" },
    { "ic", select "@class.inner", mode = { "x", "o" }, desc = "Textobject inner class" },
    { "]f", goto_function "next", mode = { "n", "x", "o" }, desc = "Textobject next function" },
    { "[f", goto_function "previous", mode = { "n", "x", "o" }, desc = "Textobject previous function" },
  },
  opts = {
    select = { lookahead = true },
    move = { set_jumps = true },
  },
  config = function(_, opts)
    require("nvim-treesitter-textobjects").setup(opts)
  end,
}
