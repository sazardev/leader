-- ── XAML actions (.xaml, WPF/UWP/MAUI) ────────────────────────────────────────
-- XAML is XML: format with prettier, build/restore/format with dotnet at the .sln/.csproj root
-- (utils/csharpproj.lua). No XAML preview exists in Neovim (Rider has one); `dotnet build` + the app's
-- own runtime are how you verify a layout change.
local log = require "utils.log"
local proj = require "utils.csharpproj"
local terminal = require "utils.terminal"

local function run(command, dir)
  terminal.run(command, dir)
end

local function dotnet(sub, extra)
  return function()
    local dir = proj.root()
    local target = proj.test_target(dir) or proj.solution(dir) or proj.project(dir)
    if not target then
      return log.warn "XAML: no solution or project around this file"
    end
    run(("dotnet %s %s%s"):format(sub, vim.fn.shellescape(target), extra and (" " .. extra) or ""), dir)
  end
end

return {
  {
    "f",
    "format (prettier)",
    function()
      require("conform").format { lsp_format = "fallback" }
    end,
  },
  { "b", "dotnet build", dotnet "build" },
  { "F", "dotnet format", dotnet "format" },
  { "u", "dotnet restore", dotnet "restore" },
  {
    "I",
    "SDK info",
    function()
      run("dotnet --info", proj.root())
    end,
  },
}
