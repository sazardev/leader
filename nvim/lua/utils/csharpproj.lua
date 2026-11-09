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
  -- Unity generated folders (never read for projects/solutions)
  ["Library"] = true,
  ["Temp"] = true,
  ["Logs"] = true,
  ["UserSettings"] = true,
  ["Build"] = true,
  ["Builds"] = true,
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
  if global then
    return vim.fs.dirname(global)
  end
  -- Unity: Assets/ + ProjectSettings/ (a generated .sln/.csproj usually exists too, but not before Unity runs)
  -- ProjectSettings/ is a directory, so the file search above cannot see it; use unity_root() (directory search).
  if M.unity_root and M.unity_root(dir) then
    return M.unity_root(dir)
  end
  return nil
end

--- The folder of the solution/project around `dir`, or `dir` itself
---@param dir string?
---@return string
function M.root(dir)
  dir = dir or vim.fs.dirname(vim.api.nvim_buf_get_name(0))
  return M.find_root(dir) or dir
end

--- Is `dir` a Unity project root? (pure over a single stat, no walk)
---@param dir string
---@return boolean
function M.is_unity(dir)
  if type(dir) ~= "string" or dir == "" then
    return false
  end
  local has_assets = vim.uv.fs_stat(dir .. "/Assets") ~= nil
  local has_settings = vim.uv.fs_stat(dir .. "/ProjectSettings") ~= nil
  return has_assets and has_settings
end

--- The Unity project root around `dir` (Assets/ + ProjectSettings/), or nil (pure: upward search only)
---@param dir string?
---@return string?
function M.unity_root(dir)
  dir = dir or vim.fs.dirname(vim.api.nvim_buf_get_name(0))
  if dir == "" or dir == "." then
    return nil
  end
  local folder = vim.fs.find(function(name)
    return name == "ProjectSettings"
  end, { path = dir, upward = true, type = "directory", limit = 1 })[1]
  if not folder then
    return nil
  end
  local root = vim.fs.dirname(folder)
  return M.is_unity(root) and root or nil
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

--- ALL target frameworks of a .csproj (pure): `<TargetFrameworks>net10.0;net8.0</TargetFrameworks>`
---@param text string?
---@return string[]
function M.tfms(text)
  text = text or ""
  local many = text:match "<TargetFrameworks>%s*([^<]+)%s*</TargetFrameworks>"
  if many then
    local out = {}
    for tfm in many:gmatch "[^;]+" do
      tfm = vim.trim(tfm)
      if tfm ~= "" then
        out[#out + 1] = tfm
      end
    end
    if #out > 0 then
      return out
    end
  end
  return { M.tfm(text) }
end

--- The SDK of a .csproj (pure): `<Project Sdk="Microsoft.NET.Sdk.Web">`
---@param text string?
---@return string?
function M.sdk(text)
  text = text or ""
  return text:match '<Project[^>]+Sdk="([^"]+)"' or text:match "<Project[^>]+Sdk=([%w%._%-]+)"
end

--- The output kind of a .csproj (pure): `Exe` (apps) vs anything else (libraries)
---@param text string?
---@return "Exe"|"Library"
function M.output_type(text)
  text = text or ""
  local v = text:match "<%s*OutputType>%s*([^<%s]+)%s*</%s*OutputType>"
  if v == "Exe" then
    return "Exe"
  end
  -- test/console/Web SDKs are Exe even when OutputType is absent
  local sdk = M.sdk(text) or ""
  if sdk:find "Web" or sdk:find "Razor" or sdk:find "Worker" or sdk:find "Test" then
    return "Exe"
  end
  return "Library"
end

--- ProjectReferences of a .csproj (pure): the `Include` of every `<ProjectReference>`
---@param text string?
---@return string[]
function M.project_refs(text)
  text = text or ""
  local out, seen = {}, {}
  for inc in text:gmatch '<%s*ProjectReference[^>]+Include="([^"]+)"' do
    if not seen[inc] then
      seen[inc] = true
      out[#out + 1] = inc
    end
  end
  table.sort(out)
  return out
end

--- PackageReferences of a .csproj (pure): id + version (`Version`, or `VersionOverride` for central packages)
---@param text string?
---@return { id: string, version: string? }[]
function M.package_refs(text)
  text = text or ""
  local out = {}
  for block in text:gmatch "<%s*PackageReference[^>]*>" do
    local id = block:match 'Include="([^"]+)"'
    local ver = block:match 'Version="([^"]+)"' or block:match 'VersionOverride="([^"]+)"'
    if id then
      out[#out + 1] = { id = id, version = ver }
    end
  end
  -- child-form `<PackageReference Include="X"><Version>1.0</Version>` (Version not on the tag)
  for id, ver in
    text:gmatch '<%s*PackageReference[^>]+Include="([^"]+)"[^>]*>%s*<%s*Version%s*>([^<]+)<%s*/%s*Version%s*>'
  do
    local found = false
    for _, p in ipairs(out) do
      if p.id == id then
        found = true
        break
      end
    end
    if not found then
      out[#out + 1] = { id = id, version = vim.trim(ver) }
    end
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

--- The projects of a classic .sln (pure). Solution folders (type 2150...) and shared projects are kept as
--- folders, not projects: `folders` maps a project name to the folder that contains it (one level).
---@param text string?
---@return { name: string, path: string, guid: string?, kind: "project"|"folder" }[]
function M.parse_sln(text)
  text = text or ""
  local out = {}
  for line in text:gmatch "[^\r\n]+" do
    -- Project("{GUID}") = "Name", "path", "{GUID}"
    local kind, name, path, guid = line:match '^%s*Project%("([^"]+)"%)%s*=%s*"([^"]+)",%s*"([^"]+)",%s*"([^"]+)"'
    if name then
      local is_folder = kind and kind:find("2150", 1, true) ~= nil
      out[#out + 1] = { name = name, path = path, guid = guid, kind = is_folder and "folder" or "project" }
    end
  end
  return out
end

--- The projects of a .slnx (pure): XML `<Project Path="src/Api/Api.csproj">` (solution folders are
--- `<Folder Name="...">` — returned as folders for grouping).
---@param text string?
---@return { name: string, path: string, kind: "project"|"folder" }[]
function M.parse_slnx(text)
  text = text or ""
  local out = {}
  for path in text:gmatch '<%s*Project%s+Path="([^"]+)"' do
    out[#out + 1] = { name = vim.fs.basename(path):gsub("%.%a+proj$", ""), path = path, kind = "project" }
  end
  for name in text:gmatch '<%s*Folder%s+Name="([^"]+)"' do
    out[#out + 1] = { name = name, path = name, kind = "folder" }
  end
  return out
end

--- The projects a solution file lists, whichever format it is (pure)
---@param path string
---@param text string?
---@return { name: string, path: string, kind: string }[]
function M.solution_projects(path, text)
  text = text or M.read(path) or ""
  if path:match "%.slnx$" then
    return M.parse_slnx(text)
  end
  return M.parse_sln(text)
end

--- Every package `dotnet list package --format json` printed (pure): direct and transitive, per framework
---@param text string
---@return { project: string, framework: string, id: string, requested: string?, resolved: string?, direct: boolean }[]
function M.parse_list_all(text)
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return {}
  end
  local out = {}
  for _, project in ipairs(list(data.projects)) do
    for _, fw in ipairs(list(project.frameworks)) do
      for _, set in ipairs { { "topLevelPackages", true }, { "transitivePackages", false } } do
        for _, p in ipairs(list(fw[set[1]])) do
          if p.id then
            out[#out + 1] = {
              project = project.path,
              framework = fw.framework,
              id = p.id,
              requested = value(p.requestedVersion),
              resolved = value(p.resolvedVersion),
              direct = set[2],
            }
          end
        end
      end
    end
  end
  return out
end

--- The dependency graph of `obj/project.assets.json` (pure): package id → its direct dependencies
---@param text string?
---@return table<string, string[]> id → child ids (sorted, deduped)
function M.parse_assets(text)
  if not text or text == "" then
    return {}
  end
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" then
    return {}
  end
  local edges = {}
  local function add(from, to)
    if from == "" or to == "" or from == to then
      return
    end
    edges[from] = edges[from] or {}
    for _, t in ipairs(edges[from]) do
      if t == to then
        return
      end
    end
    edges[from][#edges[from] + 1] = to
  end
  local function id_only(name)
    return (name or ""):gsub("/.*$", "")
  end
  for _, target in pairs(data.targets or {}) do
    if type(target) == "table" then
      for lib_name, lib in pairs(target) do
        if type(lib) == "table" and type(lib.dependencies) == "table" then
          local from = id_only(lib_name)
          for dep in pairs(lib.dependencies) do
            add(from, id_only(dep))
          end
          -- `dependencies` is a map; also check `dependencyGroups`? assets.json uses `dependencies`
          if type(lib.dependencyGroups) == "table" then
            for _, group in ipairs(list(lib.dependencyGroups)) do
              for dep in pairs(type(group) == "table" and group.dependencies or {}) do
                add(from, id_only(dep))
              end
            end
          end
        end
      end
    end
  end
  -- also the project entry (`project` → direct libs) for root edges
  if type(data.project) == "table" and type(data.project.dependencies) == "table" then
    for _, fw in pairs(data.project.dependencies) do
      if type(fw) == "table" then
        for dep in pairs(fw) do
          add("<root>", id_only(dep))
        end
      end
    end
  end
  for _, kids in pairs(edges) do
    table.sort(kids)
  end
  return edges
end

return M
