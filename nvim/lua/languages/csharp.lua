-- C# / .NET: the official Roslyn language server when it is installed and csharp-ls from Mason as the fallback
-- (servers/csharp.lua decides; the settings panel can force one). CSharpier formats on save, netcoredbg debugs the
-- built assembly, and the <leader>c menu runs dotnet, packages, EF Core migrations and the project setup.
return {
  filetypes = { "cs" },
  treesitter = { "c_sharp" },
  lsp = { "roslyn_ls" },
  mason = {
    always = { "csharpier" },
    full = { "csharp-language-server", "netcoredbg" },
  },
  formatters = { cs = { "csharpier" } },
  menu = {
    name = "C#",
    prefix = "c",
    maps = require "languages.actions.csharp",
    groups = { S = "setup", D = "debug", L = "project", G = "run" },
  },
}
