-- Compila (y espera) los parsers de treesitter de los lenguajes activos. Lo usan install.sh e install.ps1:
--   nvim --headless -c "luafile scripts/install-treesitter.lua" +qa
require("lazy").load { plugins = { "nvim-treesitter" } }
local ts = require "nvim-treesitter"
ts.setup {}
ts.install(require("languages").treesitter()):wait(900000)
