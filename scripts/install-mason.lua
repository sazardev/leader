-- Installs (and waits for) the LSPs, formatters and linters declared by the active languages. Used by install.sh and install.ps1:
--   nvim --headless -c "luafile scripts/install-mason.lua" +qa
-- `tree-sitter-cli` (Mason's prebuilt binary) is added only if there is none in PATH: the parsers need it and
-- this way neither cargo nor npm is required.
require("lazy").load { plugins = { "mason.nvim", "mason-tool-installer.nvim" } }
local list = require("languages").mason()
if vim.fn.executable "tree-sitter" == 0 then
  table.insert(list, "tree-sitter-cli")
end
require("mason-tool-installer").setup { ensure_installed = list, auto_update = false, run_on_start = false }
vim.cmd "MasonToolsInstallSync"
