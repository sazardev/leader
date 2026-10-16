-- ── History context (global): <leader>u ──────────────────────────────────────
-- The undo tree, the file at the previous / next save and the yank list (lua/history). u / U / Ctrl+Y and [y / ]y
-- are plain keys, see history/init.lua.
local function undo()
  return require "history.undo"
end

return {
  name = "History",
  prefix = "u",
  global = true,
  maps = {
    {
      "u",
      "undo tree",
      function()
        undo().tree()
      end,
    },
    {
      "y",
      "yank list",
      function()
        require("history.picker").open()
      end,
    },
    {
      "[",
      "previous save",
      function()
        undo().save_step(-1)
      end,
    },
    {
      "]",
      "next save",
      function()
        undo().save_step(1)
      end,
    },
    {
      "x",
      "forget yanks",
      function()
        require("history.yanks").clear()
        vim.notify("Yank history cleared", vim.log.levels.INFO)
      end,
    },
  },
}
