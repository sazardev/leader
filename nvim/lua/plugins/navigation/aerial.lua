-- Symbol outline (treesitter + LSP), no icons
local KINDS = {
  "File",
  "Module",
  "Namespace",
  "Package",
  "Class",
  "Method",
  "Property",
  "Field",
  "Constructor",
  "Enum",
  "Interface",
  "Function",
  "Variable",
  "Constant",
  "String",
  "Number",
  "Boolean",
  "Array",
  "Object",
  "Key",
  "Null",
  "EnumMember",
  "Struct",
  "Event",
  "Operator",
  "TypeParameter",
}

local function empty_kinds()
  local kinds = {}
  for _, kind in ipairs(KINDS) do
    kinds[kind] = ""
  end
  return kinds
end

return {
  "stevearc/aerial.nvim",
  cmd = { "AerialToggle", "AerialOpen", "AerialNavToggle" },
  opts = {
    backends = { "treesitter", "lsp", "markdown" },
    layout = { min_width = 30, max_width = 50 },
    show_guides = false, -- no vertical lines
    guide_style = "stub",
    close_behavior = "auto",
    kinds = empty_kinds(),
    keymaps = {
      ["<CR>"] = "actions.jump",
      ["<C-s>"] = "actions.jump_vsplit",
      ["<C-v>"] = "actions.jump_split",
      ["q"] = "actions.close",
    },
  },
  config = function(_, opts)
    require("aerial").setup(opts)
  end,
}
