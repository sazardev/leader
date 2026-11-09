-- ── Solution Explorer: the model (pure) ──────────────────────────────────────
-- What the explorer needs: the solution's projects with their TFM(s), output kind, assembly, project
-- references (dependencies) and package counts, grouped by folder. Everything is parsed from the .sln/.slnx
-- and the .csproj text (utils/csharpproj.lua); no process runs here. The view is csharp/explorer.lua.
local proj = require "utils.csharpproj"

local M = {}

--- The folder a project lives in, relative to the solution root (`src`, `tests`, …); "" for the root itself
---@param root string
---@param path string
---@return string
function M.folder_of(root, path)
  local rel = proj.relative(root, path)
  local dir = vim.fn.fnamemodify(rel, ":h")
  return dir == "." and "" or dir
end

--- The first path segment of a folder (`src/Api` → `src`), for grouping
---@param folder string
---@return string
function M.group_of(folder)
  if folder == "" then
    return "(root)"
  end
  return folder:match "^([^/]+)" or folder
end

--- The full info of one project file (pure over its text)
---@param path string
---@param text string?
---@return { path: string, name: string, assembly: string, tfms: string[], sdk: string?, output: string,
---           is_test: boolean, refs: string[], packages: { id: string, version: string? }[] }
function M.project_info(path, text)
  text = text or proj.read(path) or ""
  local name = vim.fs.basename(path):gsub("%.%a+proj$", "")
  return {
    path = path,
    name = name,
    assembly = proj.assembly(text, name),
    tfms = proj.tfms(text),
    sdk = proj.sdk(text),
    output = proj.output_type(text),
    is_test = proj.is_test_project(text),
    refs = proj.project_refs(text),
    packages = proj.package_refs(text),
  }
end

--- What a solution looks like: its projects with their info, grouped by folder (pure over the given texts)
---@param root string
---@param solution string? the .sln/.slnx path (nil = every .csproj under root)
---@return { root: string, solution: string?, projects: table[], groups: { name: string, projects: table[] }[] }
function M.model(root, solution)
  local projects = {}
  if solution then
    local sln_dir = vim.fs.dirname(solution)
    for _, p in ipairs(proj.solution_projects(solution)) do
      if p.kind == "project" then
        local rel = (p.path or ""):gsub("\\", "/")
        local abs = rel:sub(1, 1) == "/" and rel or (sln_dir .. "/" .. rel)
        if vim.uv.fs_stat(abs) == nil then
          abs = root .. "/" .. rel
        end
        projects[#projects + 1] = M.project_info(abs, proj.read(abs) or "")
      end
    end
  end
  if #projects == 0 then
    for _, path in ipairs(proj.projects(root)) do
      projects[#projects + 1] = M.project_info(path, proj.read(path) or "")
    end
  end
  -- resolve a ProjectReference include (`..\Domain\Domain.csproj`) to the project it names
  local by_path = {}
  for _, p in ipairs(projects) do
    by_path[p.path] = p
    by_path[proj.relative(root, p.path)] = p
  end
  for _, p in ipairs(projects) do
    local dir = vim.fs.dirname(p.path)
    local deps = {}
    for _, inc in ipairs(p.refs) do
      local clean = inc:gsub("\\", "/")
      local abs = vim.fs.normalize(dir .. "/" .. clean)
      local target = by_path[abs] or by_path[proj.relative(root, abs)]
      deps[#deps + 1] = target and target.name or vim.fs.basename(clean):gsub("%.%a+proj$", "")
    end
    p.dependencies = deps
  end
  -- group by first folder segment, root first, then alphabetical
  local groups, order = {}, {}
  for _, p in ipairs(projects) do
    local g = M.group_of(M.folder_of(root, p.path))
    if not groups[g] then
      groups[g] = { name = g, projects = {} }
      order[#order + 1] = g
    end
    groups[g].projects[#groups[g].projects + 1] = p
  end
  table.sort(order, function(a, b)
    if a == "(root)" then
      return true
    end
    if b == "(root)" then
      return false
    end
    return a < b
  end)
  local gs = {}
  for _, g in ipairs(order) do
    gs[#gs + 1] = groups[g]
    table.sort(groups[g].projects, function(a, b)
      return a.name < b.name
    end)
  end
  return { root = root, solution = solution, projects = projects, groups = gs }
end

--- The rows of the explorer for `model` (pure): title, groups, projects (for the market)
---@param model table
---@return table[]
function M.rows(model)
  local rows = {
    {
      title = ("SOLUTION · %s (%d)"):format(
        model.solution and vim.fs.basename(model.solution) or "projects",
        #model.projects
      ),
    },
    { spacer = true },
  }
  for _, group in ipairs(model.groups or {}) do
    rows[#rows + 1] = { group = group.name }
    for _, p in ipairs(group.projects) do
      rows[#rows + 1] = { project = p, group = group.name }
    end
    rows[#rows + 1] = { spacer = true }
  end
  if #model.projects == 0 then
    rows[#rows + 1] = { title = "NO PROJECTS" }
  end
  return rows
end

--- The detail pane of one project (pure): lines of `{ text, hl }` segments are built here as plain strings
--- (the view wraps them); returns the facts one per line
---@param model table
---@param p table
---@return string[]
function M.detail(model, p)
  if not p then
    return { "No project under the cursor." }
  end
  local out = {
    ("  %s"):format(p.name:upper()),
    ("  %s"):format(proj.relative(model.root, p.path)),
    "",
    ("  TFM %s"):format(table.concat(p.tfms, ", ")),
    ("  SDK %s"):format(p.sdk or "-"),
    ("  Output %s"):format(p.output),
    ("  Assembly %s"):format(p.assembly),
    ("  Kind %s"):format(p.is_test and "test" or "project"),
    "",
    ("  DEPENDENCIES (%d)"):format(#p.dependencies),
  }
  if #p.dependencies == 0 then
    out[#out + 1] = "  - none"
  else
    for _, d in ipairs(p.dependencies) do
      out[#out + 1] = ("  → %s"):format(d)
    end
  end
  out[#out + 1] = ""
  out[#out + 1] = ("  PACKAGES (%d direct)"):format(#p.packages)
  if #p.packages == 0 then
    out[#out + 1] = "  - none (central packages or none)"
  else
    for _, pkg in ipairs(p.packages) do
      out[#out + 1] = ("  %s%s"):format(pkg.id, pkg.version and (" " .. pkg.version) or "")
    end
  end
  return out
end

return M
