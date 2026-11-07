-- ── C# / .NET actions (dotnet) ───────────────────────────────────────────────
-- At the solution or project root (*.sln, *.slnx, *.csproj): run (with the launch profile), watch, build, test,
-- publish, packages, EF Core migrations, solution/project references and the setup files under `S`. Roslyn (or
-- csharp-ls), CSharpier, netcoredbg and the tests in the editor (langtest) do the rest.
local log = require "utils.log"
local modal = require "utils.modal"
local proj = require "utils.csharpproj"
local terminal = require "utils.terminal"

local function root()
  return proj.root()
end

---@param items table[]
---@param opts table
---@param on_select fun(value: any)
local function choose(items, opts, on_select)
  require("tasks.picker").choose(items, opts, on_select)
end

--- Runs `fn(project, dir)` with the only .csproj or the one picked
---@param fn fun(project: string, dir: string)
---@param prompt string?
local function with_project(fn, prompt)
  local dir = root()
  local list = proj.projects(dir)
  if #list == 0 then
    return log.warn "C#: no .csproj around this file"
  end
  if #list == 1 then
    return fn(list[1], dir)
  end
  local items = {}
  for _, path in ipairs(list) do
    local text = proj.read(path) or ""
    items[#items + 1] = {
      label = proj.relative(dir, path),
      desc = ("%s · %s"):format(proj.tfm(text), proj.assembly(text, vim.fs.basename(path):gsub("%.csproj$", ""))),
      path = path,
      value = path,
    }
  end
  choose(items, { title = prompt or "C# project", preview = true }, function(path)
    fn(path, dir)
  end)
end

---@param command string
---@param dir string
local function run(command, dir)
  terminal.run(command, dir)
end

---@param text string
---@param title string
---@param fn fun(text: string)
local function input(text, title, fn)
  modal.input({ text }, { title = title, confirm = "Run" }, function(value)
    if value ~= "" then
      fn(value)
    end
  end)
end

-- ── launch profiles ──────────────────────────────────────────────────────────

---@param project_path string
---@return { name: string, command: string, url: string?, env: table<string, string> }[]
local function profiles(project_path)
  return proj.profiles(vim.fs.dirname(project_path))
end

--- Runs `fn(profile?)` with the profile the settings ask for
---@param project_path string
---@param fn fun(profile: string?)
local function with_profile(project_path, fn)
  local list = profiles(project_path)
  local mode = (require("core.settings").csharp.run or {}).profile or "first"
  if #list == 0 or mode == "none" then
    return fn(nil)
  end
  if #list == 1 or mode == "first" then
    return fn(list[1].name)
  end
  choose(
    vim.tbl_map(function(p)
      return { label = p.name, desc = (p.url or p.command), value = p.name }
    end, list),
    { title = "Launch profile" },
    fn
  )
end

---@param sub "run"|"watch"
---@return fun()
local function launch(sub)
  return function()
    with_project(function(path, dir)
      with_profile(path, function(profile)
        local flag = profile and (" --launch-profile " .. vim.fn.shellescape(profile)) or ""
        if sub == "watch" then
          run(("dotnet watch --project %s run%s"):format(vim.fn.shellescape(path), flag), dir)
        else
          run(("dotnet run --project %s%s"):format(vim.fn.shellescape(path), flag), dir)
        end
      end)
    end)
  end
end

-- ── dotnet commands on a project ─────────────────────────────────────────────

---@param sub string
---@param opts? { project_flag?: boolean, extra?: string }
---@return fun()
local function dotnet(sub, opts)
  opts = opts or {}
  return function()
    with_project(function(path, dir)
      local arg = opts.project_flag and (" --project " .. vim.fn.shellescape(path)) or (" " .. vim.fn.shellescape(path))
      run(("dotnet %s%s%s"):format(sub, arg, opts.extra and (" " .. opts.extra) or ""), dir)
    end)
  end
end

-- ── packages ─────────────────────────────────────────────────────────────────

---@param project_path string
---@param dir string
---@param id string
---@param version string?
local function add_package(project_path, dir, id, version)
  local pin = version and (" --version " .. vim.fn.shellescape(version)) or ""
  run(("dotnet add %s package %s%s"):format(vim.fn.shellescape(project_path), vim.fn.shellescape(id), pin), dir)
end

local function add_package_prompt()
  with_project(function(path, dir)
    input("Package (e.g. Microsoft.EntityFrameworkCore.Sqlite)", "dotnet add package", function(value)
      add_package(path, dir, value, nil)
    end)
  end, "Package project")
end

local function remove_package()
  with_project(function(path, dir)
    input("Package to remove", "dotnet remove package", function(value)
      run(("dotnet remove %s package %s"):format(vim.fn.shellescape(path), vim.fn.shellescape(value)), dir)
    end)
  end, "Package project")
end

---@param n integer
---@return string
local function human(n)
  if n >= 1000000000 then
    return ("%.1fB"):format(n / 1000000000)
  elseif n >= 1000000 then
    return ("%.1fM"):format(n / 1000000)
  elseif n >= 1000 then
    return ("%.1fk"):format(n / 1000)
  end
  return tostring(n)
end

local function search_package()
  local word = vim.fn.expand "<cword>"
  local default = word:match "^[%w_%.%-]+$" and word or ""
  with_project(function(path, dir)
    input(
      "NuGet package" .. (default ~= "" and (" [" .. default .. "]") or ""),
      "dotnet package search",
      function(query)
        local take = (require("core.settings").csharp.packages or {}).take or 20
        vim.system(
          { "dotnet", "package", "search", query, "--take", tostring(take), "--format", "json" },
          { cwd = dir, text = true, timeout = 30000 },
          function(res)
            vim.schedule(function()
              if res.code ~= 0 then
                return log.warn(
                  ("C#: package search failed: %s"):format(vim.trim(res.stderr or ""):match "[^\n]+" or "?")
                )
              end
              local found = proj.parse_package_search(res.stdout or "")
              if #found == 0 then
                return log.info "C#: no packages found"
              end
              choose(
                vim.tbl_map(function(p)
                  return {
                    label = p.id,
                    desc = ("%s · %s downloads%s"):format(
                      p.version or "?",
                      human(p.downloads or 0),
                      p.owners and (" · " .. p.owners) or ""
                    ),
                    value = p,
                    search = p.id,
                  }
                end, found),
                { title = "NuGet · " .. query },
                function(p)
                  add_package(path, dir, p.id, p.version)
                end
              )
            end)
          end
        )
      end
    )
  end)
end

---@param text string
---@return string?
local function list_target(text)
  local target = proj.test_target(text)
  return target
end

local function update_packages()
  local dir = root()
  local target = list_target(dir)
  if not target then
    return log.warn "C#: no solution or project to update"
  end
  vim.system(
    { "dotnet", "list", target, "package", "--outdated", "--format", "json" },
    { cwd = dir, text = true, timeout = 30000 },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          return log.warn(("C#: dotnet list failed: %s"):format(vim.trim(res.stderr or ""):match "[^\n]+" or "?"))
        end
        local old = proj.parse_outdated(res.stdout or "")
        if #old == 0 then
          return log.info "C#: every package is up to date"
        end
        choose(
          vim.tbl_map(function(p)
            return {
              label = p.id,
              desc = ("%s → %s · %s"):format(
                p.requested or p.resolved or "?",
                p.latest,
                proj.relative(dir, p.project)
              ),
              value = p,
            }
          end, old),
          { title = "Outdated NuGet packages" },
          function(p)
            add_package(p.project, dir, p.id, p.latest)
          end
        )
      end)
    end
  )
end

local function vulnerable_packages()
  local dir = root()
  local target = list_target(dir)
  if not target then
    return log.warn "C#: no solution or project to inspect"
  end
  vim.system(
    { "dotnet", "list", target, "package", "--vulnerable", "--include-transitive", "--format", "json" },
    { cwd = dir, text = true, timeout = 30000 },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          return log.warn(("C#: dotnet list failed: %s"):format(vim.trim(res.stderr or ""):match "[^\n]+" or "?"))
        end
        local list = proj.parse_vulnerable(res.stdout or "")
        if #list == 0 then
          return log.info "C#: no vulnerable packages"
        end
        local items = {}
        for _, p in ipairs(list) do
          items[#items + 1] = {
            filename = p.project,
            lnum = 1,
            text = ("%s %s · %s · %s"):format(p.id, p.version or "?", p.severity or "?", p.advisory or ""),
            type = "W",
          }
        end
        vim.fn.setqflist({}, " ", { title = "Vulnerable NuGet packages", items = items })
        vim.cmd "copen"
        log.warn(("C#: %d vulnerable packages (quickfix)"):format(#list))
      end)
    end
  )
end

-- ── solutions and references ─────────────────────────────────────────────────

local function open_project()
  local dir = root()
  local items = {}
  for _, path in ipairs(proj.solutions(dir)) do
    items[#items + 1] = { label = proj.relative(dir, path), desc = "solution", path = path, value = path }
  end
  for _, path in ipairs(proj.projects(dir)) do
    local text = proj.read(path) or ""
    items[#items + 1] = {
      label = proj.relative(dir, path),
      desc = ("%s · %s"):format(proj.tfm(text), proj.assembly(text, vim.fs.basename(path):gsub("%.csproj$", ""))),
      path = path,
      value = path,
    }
  end
  if #items == 0 then
    return log.warn "C#: no solution or project around this file"
  end
  if #items == 1 then
    return vim.cmd.edit(vim.fn.fnameescape(items[1].value))
  end
  choose(items, { title = "C# solutions and projects", preview = true }, function(path)
    vim.cmd.edit(vim.fn.fnameescape(path))
  end)
end

---@param fn fun(solution: string)
local function with_solution(fn)
  local dir = root()
  local list = proj.solutions(dir)
  if #list == 0 then
    return log.warn "C#: no .sln/.slnx around this file (create one with `dotnet new sln`)"
  end
  if #list == 1 then
    return fn(list[1])
  end
  choose(
    vim.tbl_map(function(path)
      return { label = proj.relative(dir, path), value = path }
    end, list),
    { title = "C# solution", preview = true },
    fn
  )
end

local function add_to_solution()
  with_solution(function(solution)
    with_project(function(path, dir)
      run(("dotnet sln %s add %s"):format(vim.fn.shellescape(solution), vim.fn.shellescape(path)), dir)
    end, "Project to add")
  end)
end

local function add_reference()
  with_project(function(source, dir)
    local list = vim.tbl_filter(function(path)
      return path ~= source
    end, proj.projects(dir))
    if #list == 0 then
      return log.warn "C#: there is no other project to reference"
    end
    local function target(path)
      run(("dotnet add %s reference %s"):format(vim.fn.shellescape(source), vim.fn.shellescape(path)), dir)
    end
    if #list == 1 then
      return target(list[1])
    end
    choose(
      vim.tbl_map(function(path)
        return { label = proj.relative(dir, path), value = path }
      end, list),
      { title = "Reference from " .. proj.relative(dir, source), preview = true },
      target
    )
  end, "Referencing project")
end

-- ── project and tools ────────────────────────────────────────────────────────

local function new_project()
  input("Template and name (e.g. webapi -n MyApi)", "dotnet new", function(text)
    run("dotnet new " .. text, root())
  end)
end

local function ef(sub, ask_text, title)
  return function()
    with_project(function(path, dir)
      local function go(text)
        local args = text ~= "" and (" " .. text) or ""
        run(
          ('PATH="$HOME/.dotnet/tools:$PATH" dotnet ef %s%s --project %s'):format(sub, args, vim.fn.shellescape(path)),
          dir
        )
      end
      if ask_text then
        input(ask_text, title, go)
      else
        go ""
      end
    end)
  end
end

local function install_tool(args, name)
  return function()
    if vim.fn.executable "dotnet" ~= 1 then
      return log.warn "C#: dotnet is not installed"
    end
    run(("dotnet tool update --global %s || dotnet tool install --global %s"):format(args, args), root())
    log.info(("C#: when %s finishes, restart the language server (:LspRestart)"):format(name))
  end
end

local function toggle_inlay_hints()
  local prefs = require "prefs"
  local item = prefs.find "csharp.inlay_hints"
  if item then
    return prefs.set(item, not prefs.value(item))
  end
  local settings = require("core.settings").csharp
  settings.inlay_hints = not settings.inlay_hints
  log.info("C#: inlay hints " .. (settings.inlay_hints and "on" or "off"))
end

local maps = {
  { "r", "dotnet run", launch "run" },
  { "w", "dotnet watch (hot reload)", launch "watch" },
  { "b", "dotnet build", dotnet "build" },
  { "p", "dotnet publish Release", dotnet("publish", { extra = "-c Release" }) },
  {
    "f",
    "format (CSharpier)",
    function()
      require("conform").format { lsp_format = "fallback" }
    end,
  },
  { "F", "dotnet format", dotnet "format" },
  { "v", "verify formatting", dotnet("format", { extra = "--verify-no-changes" }) },
  { "o", "open solution/project", open_project },
  { "n", "new project (dotnet new)", new_project },
  { "P", "add NuGet package", add_package_prompt },
  { "R", "remove NuGet package", remove_package },
  { "N", "search NuGet packages", search_package },
  { "U", "update outdated packages", update_packages },
  { "Q", "vulnerable packages (quickfix)", vulnerable_packages },
  { "u", "dotnet restore", dotnet "restore" },
  { "e", "EF migration add", ef("migrations add", "Migration name", "dotnet ef migrations add") },
  { "E", "EF database update", ef("database update", nil, "dotnet ef database update") },
  {
    "I",
    "SDK info",
    function()
      run("dotnet --info", root())
    end,
  },
  { "H", "inlay hints", toggle_inlay_hints },
  { "Ll", "list solutions/projects", open_project },
  { "La", "add project to solution", add_to_solution },
  { "Lr", "add project reference", add_reference },
}

vim.list_extend(maps, require("langtest").maps())
vim.list_extend(maps, require("langdebug").maps "csharp")
vim.list_extend(maps, require("langsetup").maps "csharp")
vim.list_extend(maps, {
  { "Sr", "setup Roslyn server", install_tool("roslyn-language-server --prerelease", "Roslyn") },
  { "Sf", "setup dotnet-ef", install_tool("dotnet-ef", "dotnet-ef") },
})
return maps
