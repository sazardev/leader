-- YarnSpinner (dialogues). ftdetect/ and syntax/ define the filetype and the highlighting.
-- The `ysc` linter is optional: it is only enabled if installed
-- (dotnet tool install -g yarn-spinner; requires dotnet).
local has_ysc = vim.fn.executable "ysc" == 1

return {
  filetypes = { "yarnspinner" },
  linters = has_ysc and { yarnspinner = { "ysc" } } or nil,

  -- Error format: path(lnum,col): severity CODE: message
  setup_lint = function(lint)
    lint.linters.ysc = {
      name = "ysc",
      cmd = "ysc",
      stdin = false,
      args = { "compile", "--stdout" },
      stream = "stderr",
      ignore_exitcode = true,
      parser = require("lint.parser").from_pattern(
        "[^%(]+%((%d+),(%d+)%): (%a+) %w+: (.+)",
        { "lnum", "col", "severity", "message" },
        {
          ["error"] = vim.diagnostic.severity.ERROR,
          ["warning"] = vim.diagnostic.severity.WARN,
        }
      ),
    }
  end,
}
