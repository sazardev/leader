-- C# / .NET setup (<leader>cS): .editorconfig, Directory.Build.props, global.json, GitHub Actions, Dockerfile.
-- Filled from the first .csproj (assembly name, target framework) and the installed SDK.
local M = { name = "C# / .NET" }

local sdk_version

--- The installed SDK (once per session); a version that always exists as the fallback
---@return string
local function sdk()
  if sdk_version then
    return sdk_version
  end
  local ok, out = pcall(function()
    return vim.system({ "dotnet", "--version" }, { text = true }):wait(5000)
  end)
  sdk_version = ok and out.code == 0 and vim.trim(out.stdout or "") or ""
  if sdk_version == "" then
    sdk_version = "10.0.100"
  end
  return sdk_version
end

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, function(name)
    return name:match "%.slnx?$" ~= nil or name:match "%.csproj$" ~= nil or name == "global.json"
  end) or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local csproj = vim.fs.find(function(name)
    return name:match "%.csproj$" ~= nil
  end, { path = root, type = "file", limit = 1 })[1]
  local text = csproj and require("utils.project").read(csproj) or ""
  local name = text:match "<AssemblyName>([^<]+)</AssemblyName>"
    or text:match "<RootNamespace>([^<]+)</RootNamespace>"
    or (csproj and vim.fs.basename(csproj):gsub("%.csproj$", ""))
    or vim.fs.basename(root)
  local tfm = text:match "<TargetFramework>([^<]+)</TargetFramework>" or "net10.0"
  return {
    name = name,
    tfm = tfm,
    channel = tfm:match "net(%d+%.%d+)" or "10.0",
    sdk = sdk(),
  }
end

M.topics = {
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "dotnet", core = true },
  { id = "buildprops", key = "b", label = "Directory.Build.props", default = "standard", core = true },
  { id = "globaljson", key = "G", label = "global.json (SDK pin)", default = "latest", core = true },
  { id = "ci", key = "c", label = "GitHub Actions CI", default = "github", alts = { ".github/workflows/ci.yml" } },
  { id = "docker", key = "d", label = "Dockerfile (ASP.NET)", default = "aspnet" },
  { id = "dockerignore", key = "i", label = ".dockerignore", default = "dotnet", core = true },
}

function M.hint(topic)
  if topic.id == "docker" then
    return "docker build -t app . (the project is published inside the image)"
  end
end

return M
