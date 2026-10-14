-- ── Files context (global): <leader>F ────────────────────────────────────────
-- Everything you do to a file, in one place and with the same modals as the tree. They act on the current file, or on the
-- row under the cursor when you are in the tree (lua/files). Deleting goes to a trash: `u` brings the last one back.
local function files()
  return require "files"
end

return {
  name = "File",
  prefix = "F",
  global = true,
  maps = {
    {
      "n",
      "new file",
      function()
        files().new "file"
      end,
    },
    {
      "N",
      "new folder",
      function()
        files().new "folder"
      end,
    },
    {
      "r",
      "rename",
      function()
        files().rename()
      end,
    },
    {
      "m",
      "move",
      function()
        files().move()
      end,
    },
    {
      "c",
      "duplicate",
      function()
        files().copy()
      end,
    },
    {
      "x",
      "delete",
      function()
        files().delete()
      end,
    },
    {
      "u",
      "undo delete",
      function()
        files().undo()
      end,
    },
    {
      "y",
      "copy path",
      function()
        files().copy_path(false)
      end,
    },
    {
      "Y",
      "copy full path",
      function()
        files().copy_path(true)
      end,
    },
    {
      "t",
      "show in tree",
      function()
        files().reveal()
      end,
    },
    {
      "o",
      "open file",
      function()
        files().open_file()
      end,
    },
  },
}
