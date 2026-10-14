-- Explorer: hides git-ignored files (fast), no icons.
-- New / rename / delete use the flat modals of lua/files (the same ones as <leader>F), not nvim-tree's own prompts.

local function on_attach(bufnr)
  local api = require "nvim-tree.api"

  api.config.mappings.default_on_attach(bufnr)

  -- <CR> on a file → opens it and closes nvim-tree
  vim.keymap.set("n", "<CR>", function()
    local node = api.tree.get_node_under_cursor()
    api.node.open.edit()
    if not node.nodes then
      api.tree.close()
    end
  end, { buffer = bufnr, desc = "nvim-tree: Open file and close tree", nowait = true })

  -- a / r / d: new file or folder (end with "/" for a folder, ";" separates several), rename, delete (to a trash)
  vim.keymap.set("n", "a", function()
    require("files").new "file"
  end, { buffer = bufnr, nowait = true, desc = "nvim-tree: New file or folder" })
  vim.keymap.set("n", "r", function()
    require("files").rename()
  end, { buffer = bufnr, nowait = true, desc = "nvim-tree: Rename" })
  vim.keymap.set("n", "d", function()
    require("files").delete()
  end, { buffer = bufnr, nowait = true, desc = "nvim-tree: Delete" })
end

return {
  "nvim-tree/nvim-tree.lua",
  opts = {
    filters = {
      dotfiles = true,
      git_ignored = true,
    },
    renderer = {
      root_folder_label = false, -- no project row on top: <CR> on it only went up a folder (`-` does that)
      highlight_hidden = "name", -- dotfiles and dot-folders in their own color (NvimTreeHidden*HL, ui/flat/groups.lua)
      -- like the demo's tree: names only, indentation without guides, no special colors for README & co.
      indent_markers = { enable = false },
      special_files = {},
      highlight_opened_files = "none",
      highlight_git = "none",
      icons = {
        bookmarks_placement = "signcolumn",
        glyphs = { bookmark = "▎" }, -- a marked file gets a yellow bar at the very left
        show = {
          file = false,
          folder = false,
          folder_arrow = false,
          git = false,
        },
      },
    },
    on_attach = on_attach,
  },
  config = function(_, opts)
    require("nvim-tree").setup(opts)
  end,
}
