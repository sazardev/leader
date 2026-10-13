-- Instala (y espera) los LSP, formatters y linters que declaran los lenguajes activos. Lo usan install.sh e install.ps1:
--   nvim --headless -c "luafile scripts/install-mason.lua" +qa
-- `tree-sitter-cli` (binario precompilado de Mason) se añade solo si no hay uno en el PATH: los parsers lo necesitan y
-- así no hace falta cargo ni npm.
require("lazy").load { plugins = { "mason.nvim", "mason-tool-installer.nvim" } }
local list = require("languages").mason()
if vim.fn.executable "tree-sitter" == 0 then
  table.insert(list, "tree-sitter-cli")
end
require("mason-tool-installer").setup { ensure_installed = list, auto_update = false, run_on_start = false }
vim.cmd "MasonToolsInstallSync"
