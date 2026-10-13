-- Compiles (and waits for) the treesitter parsers of the active languages. Used by install.sh and install.ps1:
--   nvim --headless -c "luafile scripts/install-treesitter.lua" +qa
require("lazy").load { plugins = { "nvim-treesitter" } }
local ts = require "nvim-treesitter"
ts.setup {}
ts.install(require("languages").treesitter()):wait(900000)
