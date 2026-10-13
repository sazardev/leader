-- Minimal entry point: the logic lives in lua/core/.
vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "
vim.g.maplocalleader = " " -- before lazy (otherwise lazy warns)
vim.o.cmdheight = 0

-- Lua module bytecode cache (faster startup)
vim.loader.enable()

require("core.lazy").setup()
require("core").setup()
