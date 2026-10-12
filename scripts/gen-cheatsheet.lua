-- Lo ejecuta scripts/gen-cheatsheet.sh dentro de nvim --headless (config real).
-- Entorno: CHEATSHEET_OUT = ruta del markdown, CHEATSHEET_CHECK=1 = solo comparar.
local cheat = require "utils.cheatsheet"
local out = vim.env.CHEATSHEET_OUT
local check = vim.env.CHEATSHEET_CHECK == "1"

if not cheat.wait_ready() then
  io.stderr:write "gen-cheatsheet: la config no cargó los keymaps\n"
  vim.cmd "cquit 2"
end

local fresh = cheat.write(out, check)
for _, w in ipairs(cheat.warnings) do
  io.stderr:write("aviso: " .. w .. "\n")
end
if check and not fresh then
  io.stderr:write "gen-cheatsheet: CHEATSHEET.md está desactualizado (ejecuta scripts/gen-cheatsheet.sh)\n"
end
vim.cmd(fresh and "qa!" or "cquit 1")
