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
      -- the panel opens with the session and closes with it. A Dart run (<leader>dr) is a debug session too, but its
      -- panel is not wanted until the app stops at a breakpoint (<leader>dd opens it at once)
      local dap = require "dap"
      local function opens_with_session(session)
        if session and session.config and session.config.type == "dart" then
          return require("dartrun").wants_panel()
        end
        return true
      end
      local function panel_open()
        local state = package.loaded["dap-view.state"]
        return state ~= nil and state.winnr ~= nil and vim.api.nvim_win_is_valid(state.winnr)
      end
      dap.listeners.before.attach["dap-view"] = function(session)
        if opens_with_session(session) then
          require("dap-view").open()
        end
      end
      dap.listeners.before.launch["dap-view"] = function(session)
        if opens_with_session(session) then
          require("dap-view").open()
        end
      end
      -- (the adapter stops once at the start, reason "entry": that is not a breakpoint)
      dap.listeners.after.event_stopped["dap-view"] = function(_, body)
        if body and body.reason ~= "entry" and not panel_open() then
          require("dap-view").open()
        end
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
