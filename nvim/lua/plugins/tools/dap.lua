-- Debugging: nvim-dap (the client) + nvim-dap-view (one panel: watches, scopes, breakpoints, threads, REPL).
-- Nothing loads until it is needed: flutter-tools requires `dap` when you debug (lazy loads the module on require),
-- the menu keys (Dart: <leader>d b/c/n/i/O/u) require it too. Colors of the signs come from the flat design (ui/flat/groups).
return {
  {
    "mfussenegger/nvim-dap",
    config = function()
      local signs = {
        DapBreakpoint = { text = "●", texthl = "DapBreakpoint" },
        DapBreakpointCondition = { text = "◆", texthl = "DapBreakpointCondition" },
        DapBreakpointRejected = { text = "○", texthl = "DapBreakpointRejected" },
        DapLogPoint = { text = "◇", texthl = "DapLogPoint" },
        DapStopped = { text = "▶", texthl = "DapStopped", linehl = "DapStoppedLine" },
      }
      for name, sign in pairs(signs) do
        vim.fn.sign_define(name, sign)
      end
      -- the panel opens with the session and closes with it
      local dap = require "dap"
      dap.listeners.before.attach["dap-view"] = function()
        require("dap-view").open()
      end
      dap.listeners.before.launch["dap-view"] = function()
        require("dap-view").open()
      end
      dap.listeners.before.event_terminated["dap-view"] = function()
        require("dap-view").close()
      end
      dap.listeners.before.event_exited["dap-view"] = function()
        require("dap-view").close()
      end
    end,
  },
  {
    "igorlfs/nvim-dap-view",
    cmd = { "DapViewOpen", "DapViewToggle", "DapViewWatch" },
    dependencies = { "mfussenegger/nvim-dap" },
    opts = {},
  },
}
