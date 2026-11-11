-- ── Terminal context (global): <leader>T ─────────────────────────────────────
-- The integrated terminal without surprises (lua/utils/terminal.lua, toggleterm): Esc closes the window and
-- the shell keeps running, so `t` shows the command terminal again, `l` lists every terminal to jump to,
-- `n` opens a new shell and `s` sends Ctrl-C. Reopening never re-sends anything.
return {
  name = "Terminal",
  prefix = "T",
  global = true,
  maps = {
    {
      "t",
      "Terminal show / hide",
      function()
        require("utils.terminal").focus()
      end,
    },
    {
      "l",
      "Terminal list",
      function()
        require("utils.terminal").pick()
      end,
    },
    {
      "n",
      "Terminal new shell",
      function()
        require("utils.terminal").new_shell()
      end,
    },
    {
      "v",
      "Terminal vertical split",
      function()
        require("utils.terminal").new_shell "vertical"
      end,
    },
    {
      "h",
      "Terminal horizontal split",
      function()
        require("utils.terminal").new_shell "horizontal"
      end,
    },
    {
      "s",
      "Terminal stop",
      function()
        require("utils.terminal").stop()
      end,
    },
  },
}
