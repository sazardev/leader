-- Roslyn when it is installed, csharp-ls otherwise (servers/csharp.lua). The server keeps the name roslyn_ls so the
-- config nvim-lspconfig ships (root, handlers, fix-all, inlay hints) applies to either one; what changes is the
-- command. `init_options` is for csharp-ls (it loads the workspace on its own), Roslyn ignores it.
local csharp = require "servers.csharp"

local warned = false

return {
  -- nvim-lspconfig's before_init reads config.cmd[1]; ours is a function
  before_init = function() end,
  init_options = { AutomaticWorkspaceInit = true },
  cmd = function(dispatchers, config)
    local server = csharp.pick()
    if not server then
      if not warned then
        warned = true
        vim.notify(
          "C#: no language server. Install Roslyn with <leader>cSr, or csharp-ls with :MasonInstall csharp-language-server",
          vim.log.levels.WARN,
          { title = "C#" }
        )
      end
      return nil
    end
    local cmd = server.name == "roslyn" and { server.path, "--stdio", "--autoLoadProjects" } or { server.path }
    return vim.lsp.rpc.start(cmd, dispatchers, {
      cwd = config.cmd_cwd or config.root_dir,
      env = config.cmd_env,
      detached = config.detached,
    })
  end,
}
