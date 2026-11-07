-- ── Which C# language server ─────────────────────────────────────────────────
-- Roslyn (Microsoft's official server, installed with `dotnet tool install --global roslyn-language-server
-- --prerelease`) understands modern .NET and ASP.NET best. csharp-ls (Mason) is the fallback, so C# never ends up
-- without a server when the SDK is there but the global tool is not. `settings.lsp.csharp_server` = "auto" prefers
-- Roslyn and only names the other when forced.
local M = {}

M.ROSLYN = "roslyn-language-server"
M.CSHARP_LS = "csharp-ls"

--- An executable by name, or in the folders `dotnet tool` and Mason install into (they may not be on PATH yet)
---@param name string
---@return string?
local function find(name)
  local path = vim.fn.exepath(name)
  if path ~= "" then
    return path
  end
  for _, dir in ipairs { vim.fn.expand "~/.dotnet/tools", vim.fn.stdpath "data" .. "/mason/bin" } do
    local candidate = dir .. "/" .. name
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
end

--- What is on this machine
---@return { roslyn: string?, csharp_ls: string? }
function M.installed()
  return { roslyn = find(M.ROSLYN), csharp_ls = find(M.CSHARP_LS) }
end

--- Pure: the server to use, or nil when neither is installed
---@param pref string? "auto" | "roslyn" | "csharp_ls"
---@param installed { roslyn: string?, csharp_ls: string? }
---@return { name: "roslyn"|"csharp_ls", path: string }?
function M.choose(pref, installed)
  if pref == "roslyn" then
    return installed.roslyn and { name = "roslyn", path = installed.roslyn } or nil
  end
  if pref == "csharp_ls" then
    return installed.csharp_ls and { name = "csharp_ls", path = installed.csharp_ls } or nil
  end
  if installed.roslyn then
    return { name = "roslyn", path = installed.roslyn }
  end
  if installed.csharp_ls then
    return { name = "csharp_ls", path = installed.csharp_ls }
  end
end

---@return { name: "roslyn"|"csharp_ls", path: string }?
function M.pick()
  local pref = (require("core.settings").lsp or {}).csharp_server or "auto"
  return M.choose(pref, M.installed())
end

return M
