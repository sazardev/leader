-- Run by scripts/gen-cheatsheet.sh inside nvim --headless (real config).
-- Environment: CHEATSHEET_OUT = markdown path, CHEATSHEET_CHECK=1 = compare only.
local cheat = require "utils.cheatsheet"
local out = vim.env.CHEATSHEET_OUT
local check = vim.env.CHEATSHEET_CHECK == "1"

if not cheat.wait_ready() then
  io.stderr:write "gen-cheatsheet: the config did not load the keymaps\n"
  vim.cmd "cquit 2"
end

local fresh = cheat.write(out, check)
for _, w in ipairs(cheat.warnings) do
  io.stderr:write("warning: " .. w .. "\n")
end
if check and not fresh then
  io.stderr:write "gen-cheatsheet: CHEATSHEET.md is out of date (run scripts/gen-cheatsheet.sh)\n"
end
vim.cmd(fresh and "qa!" or "cquit 1")
