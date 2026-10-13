-- Treesitter textobjects (af/if/ac/ic, ]f/[f, PageUp/PageDown and Home/End by blocks).
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
  -- The "main" branch no longer reads keymaps from opts: they are defined by hand.
  keys = {
    { "af", select "@function.outer", mode = { "x", "o" }, desc = "Textobject outer function" },
    { "if", select "@function.inner", mode = { "x", "o" }, desc = "Textobject inner function" },
    { "ac", select "@class.outer", mode = { "x", "o" }, desc = "Textobject outer class" },
    { "ic", select "@class.inner", mode = { "x", "o" }, desc = "Textobject inner class" },
    { "]f", goto_function "next", mode = { "n", "x", "o" }, desc = "Textobject next function" },
    { "[f", goto_function "previous", mode = { "n", "x", "o" }, desc = "Textobject previous function" },
    -- PageDown/PageUp jump block by block (function, method, class, struct...)
    {
      "<PageDown>",
      function()
        require("utils.blocks").jump(true)
      end,
      mode = { "n", "x" },
      desc = "Textobject next block (PageDown)",
    },
    {
      "<PageUp>",
      function()
        require("utils.blocks").jump(false)
      end,
      mode = { "n", "x" },
      desc = "Textobject previous block (PageUp)",
    },
    -- Home/End: start/end of the current block (repeating goes up to the enclosing block)
    {
      "<Home>",
      function()
        require("utils.blocks").edge(true)
      end,
      mode = { "n", "x" },
      desc = "Textobject block start (Home)",
    },
    {
      "<End>",
      function()
        require("utils.blocks").edge(false)
      end,
      mode = { "n", "x" },
      desc = "Textobject block end (End)",
    },
  },
  opts = {
    select = { lookahead = true },
    move = { set_jumps = true },
  },
  config = function(_, opts)
    require("nvim-treesitter-textobjects").setup(opts)
  end,
}
