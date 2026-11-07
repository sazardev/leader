-- ── C# projects, solutions and the `dotnet` answers about them ────────────────
-- Finding the .sln/.slnx/.csproj around a file, listing what a solution contains, reading launch profiles,
-- NuGet search results (JSON) and the outdated/vulnerable reports: the pure parsers live here so the menu
-- (languages/actions/csharp.lua) only has to show them. No process runs from this module.
local M = {}

M.MAX_PROJECTS = 500
M.MAX_FILES = 2000

--- JSON `null` arrives as `vim.NIL`: the menu formats these values, so keep them as nil
---@param value any
---@return any
local function value(value)
  return value ~= vim.NIL and value or nil
end

---@param value any
---@return table
local function list(value)
  return type(value) == "table" and value or {}
end

local SKIP = {
  ["bin"] = true,
  ["obj"] = true,
  [".git"] = true,
  [".vs"] = true,
  [".idea"] = true,
  ["node_modules"] = true,
  ["TestResults"] = true,
  ["publish"] = true,
}

---@param path string
---@return string?
function M.read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return text
end

--- Walks `dir` skipping build output, VCS and editor folders; `accept(name)` decides the files.
---@param dir string
---@param accept fun(name: string): boolean
---@param out string[]
---@param depth integer
local function walk(dir, accept, out, depth)
  if #out >= M.MAX_PROJECTS or depth > 15 then
    return
  end
  local ok, iter = pcall(vim.fs.dir, dir)
  if not ok then
    return
  end
  for name, kind in iter do
    local path = dir .. "/" .. name
    if kind == "directory" then
      if not SKIP[name] and name:sub(1, 1) ~= "." then
        walk(path, accept, out, depth + 1)
      end
    elseif kind == "file" and accept(name) then
      out[#out + 1] = path
    end
  end
end

--- The folder of the solution/project around `dir`, or nil when there is none. A solution wins over the project
--- inside it: `dotnet test`, `dotnet sln` and the project index want the whole tree when there is one.
---@param dir string?
---@return string?
function M.find_root(dir)
  dir = dir or vim.fs.dirname(vim.api.nvim_buf_get_name(0))
  local function upward(match)
    return vim.fs.find(function(name)
      return match(name)
    end, { path = dir, upward = true, type = "file", limit = 1 })[1]
  end
  local solution = upward(function(name)
    return name:match "%.slnx?$" ~= nil
  end)
  if solution then
    return vim.fs.dirname(solution)
  end
  local project = upward(function(name)
    return name:match "%.csproj$" ~= nil
  end)
  if project then
    return vim.fs.dirname(project)
  end
  local global = upward(function(name)
    return name == "global.json"
  end)
  return global and vim.fs.dirname(global) or nil
end

--- The folder of the solution/project around `dir`, or `dir` itself
---@param dir string?
---@return string
function M.root(dir)
  dir = dir or vim.fs.dirname(vim.api.nvim_buf_get_name(0))
  return M.find_root(dir) or dir
end

---@param dir string
---@return string[]
function M.solutions(dir)
  local out = {}
  walk(dir, function(name)
    return name:match "%.slnx?$" ~= nil
  end, out, 0)
  table.sort(out)
  return out
end

---@param dir string
---@return string[]
function M.projects(dir)
  local out = {}
  walk(dir, function(name)
    return name:match "%.csproj$" ~= nil
  end, out, 0)
  table.sort(out)
  return out
end

---@param dir string
---@return string?
function M.solution(dir)
  return M.solutions(dir)[1]
end

---@param dir string
---@return string?
function M.project(dir)
  return M.projects(dir)[1]
end

--- A path as it is shown in menus (`src/Api/Api.csproj` from its folder)
---@param root string
---@param path string
---@return string
function M.relative(root, path)
  return path:sub(1, #root + 1) == root .. "/" and path:sub(#root + 2) or path
end

--- The project files `dotnet sln list` printed (pure)
---@param text string
---@return string[]
function M.parse_sln_list(text)
  local out = {}
  for line in text:gmatch "[^\r\n]+" do
    line = vim.trim(line)
    if line:match "%.%a+proj$" then
      out[#out + 1] = line
    end
  end
  return out
end

--- The profiles of a launchSettings.json (pure)
---@param text string?
---@return { name: string, command: string, url: string?, env: table<string, string> }[]
function M.parse_launch_settings(text)
  if not text or text == "" then
    return {}
  end
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" or type(data.profiles) ~= "table" then
    return {}
  end
  local out = {}
  for name, p in pairs(data.profiles) do
    if type(p) == "table" then
      out[#out + 1] = {
        name = name,
        command = p.commandName or "Project",
        url = type(p.applicationUrl) == "string" and p.applicationUrl:match "^[^;]+" or nil,
        env = type(p.environmentVariables) == "table" and p.environmentVariables or {},
      }
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

--- The launch profiles of a project (the test project included)
---@param root string
---@return { name: string, command: string, url: string?, env: table<string, string> }[]
function M.profiles(root)
  return M.parse_launch_settings(M.read(root .. "/Properties/launchSettings.json"))
end

--- The NuGet packages a `dotnet package search --format json` found (pure)
---@param text string
---@return { id: string, version: string?, downloads: integer, owners: string?, source: string? }[]
function M.parse_package_search(text)
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return {}
  end
  local out, seen = {}, {}
  for _, source in ipairs(list(data.searchResult)) do
    for _, p in ipairs(list(source.packages)) do
      if p.id and not seen[p.id] then
        seen[p.id] = true
        out[#out + 1] = {
          id = p.id,
          version = value(p.latestVersion),
          downloads = value(p.totalDownloads) or 0,
          owners = value(p.owners),
          source = value(source.sourceName),
        }
      end
    end
  end
  return out
end

--- The packages `dotnet list package --outdated --format json` says are old (pure)
---@param text string
---@return { project: string, framework: string, id: string, requested: string?, resolved: string?, latest: string, direct: boolean }[]
function M.parse_outdated(text)
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return {}
  end
  local out = {}
  for _, project in ipairs(list(data.projects)) do
    for _, fw in ipairs(list(project.frameworks)) do
      for _, set in ipairs { { "topLevelPackages", true }, { "transitivePackages", false } } do
        for _, p in ipairs(list(fw[set[1]])) do
          if value(p.latestVersion) then
            out[#out + 1] = {
              project = project.path,
              framework = fw.framework,
              id = p.id,
              requested = value(p.requestedVersion),
              resolved = value(p.resolvedVersion),
              latest = value(p.latestVersion),
              direct = set[2],
            }
          end
        end
      end
    end
  end
  return out
end

--- The vulnerable packages `dotnet list package --vulnerable --format json` found (pure)
---@param text string
---@return { project: string, framework: string, id: string, version: string?, severity: string?, advisory: string?, direct: boolean }[]
function M.parse_vulnerable(text)
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return {}
  end
  local out = {}
  for _, project in ipairs(list(data.projects)) do
    for _, fw in ipairs(list(project.frameworks)) do
      for _, set in ipairs { { "topLevelPackages", true }, { "transitivePackages", false } } do
        for _, p in ipairs(list(fw[set[1]])) do
          for _, v in ipairs(list(p.vulnerabilities)) do
            out[#out + 1] = {
              project = project.path,
              framework = fw.framework,
              id = p.id,
              version = value(p.resolvedVersion),
              severity = value(v.severity),
              advisory = value(v.advisoryurl),
              direct = set[2],
            }
          end
        end
      end
    end
  end
  return out
end

--- The target framework of a .csproj (pure)
---@param text string?
---@return string
function M.tfm(text)
  text = text or ""
  return text:match "<TargetFramework>%s*([^<%s]+)%s*</TargetFramework>"
    or text:match "<TargetFrameworks>%s*([^;<%s]+)"
    or "net10.0"
end

--- The assembly name of a .csproj (pure)
---@param text string?
---@param fallback string
---@return string
function M.assembly(text, fallback)
  text = text or ""
  return text:match "<AssemblyName>%s*([^<%s]+)%s*</AssemblyName>"
    or text:match "<RootNamespace>%s*([^<%s]+)%s*</RootNamespace>"
    or fallback
end

--- Does this .csproj run tests? (pure)
---@param text string?
---@return boolean
function M.is_test_project(text)
  text = text or ""
  return text:match "Microsoft%.NET%.Test%.Sdk" ~= nil
    or text:match "<IsTestProject>%s*true%s*</IsTestProject>" ~= nil
    or text:match "<IsTestProject>%s*True%s*</IsTestProject>" ~= nil
end

--- What `dotnet test` should be pointed at: the solution, else the test project, else the only project.
---@param root string
---@return string?
function M.test_target(root)
  local solution = M.solution(root)
  if solution then
    return solution
  end
  local projects = M.projects(root)
  local tests = vim.tbl_filter(function(path)
    return M.is_test_project(M.read(path))
  end, projects)
  if #tests == 1 then
    return tests[1]
  end
  return #projects == 1 and projects[1] or nil
end

return M
