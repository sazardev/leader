-- ── Reglas de DDD sobre el índice (puro, sin LLM: cuesta 0 tokens) ───────────
--   violations(index)         dependencias que apuntan hacia fuera, frameworks en dominio/aplicación, archivos mal nombrados
--   aggregates(index)         por entidad: su puerto de repositorio, su implementación, sus casos de uso y lo que falta
--   wire(index, aggs, cb)     ¿cada implementación se usa en algún otro archivo? (ripgrep, asíncrono)
--   next_steps(index, naming) lo que falta, en una lista accionable
local layers = require "agent.ddd.layers"
local naming_mod = require "agent.ddd.naming"

local M = {}

---@class DddViolation
---@field file string
---@field line integer
---@field severity integer
---@field rule string
---@field message string

local SEV = vim.diagnostic.severity

-- Lenguajes donde el archivo se llama como su clase (la regla de nombres no aplica)
local FILE_IS_TYPE = { java = true, kt = true, cs = true, scala = true, php = true }
local ROLE_SUFFIX =
  { "Repository", "Service", "Handler", "Controller", "UseCase", "Dto", "DTO", "Command", "Query", "Factory", "Mapper" }
local ENTITY_EXCLUDE = {
  "Repository",
  "Service",
  "Handler",
  "Controller",
  "UseCase",
  "Dto",
  "DTO",
  "Command",
  "Query",
  "Event",
  "Error",
  "Exception",
  "Factory",
  "Mapper",
  "Config",
  "Options",
  "Request",
  "Response",
}
local REPO_WORDS = { "repository", "repo", "store", "storage", "gateway", "dao", "port" }

---@param name string
---@param words string[]
---@return boolean
local function has_word(name, words)
  local lower = name:lower()
  for _, w in ipairs(words) do
    if lower:find(w, 1, true) then
      return true
    end
  end
  return false
end

---@param name string
---@param suffixes string[]
---@return boolean
local function ends_with(name, suffixes)
  for _, suffix in ipairs(suffixes) do
    if name:sub(-#suffix) == suffix then
      return true
    end
  end
  return false
end

---@param index DddIndex
---@return DddViolation[]
function M.violations(index)
  local out = {}
  for _, f in ipairs(index.list) do
    if f.layer and not f.test and not layers.is_composition_root(f.rel) then
      for _, imp in ipairs(f.imports) do
        if imp.layer and not layers.ALLOWED[f.layer][imp.layer] then
          out[#out + 1] = {
            file = f.rel,
            line = imp.line,
            severity = f.layer == "domain" and SEV.ERROR or SEV.WARN,
            rule = "dependency",
            message = ('%s must not depend on %s (imports "%s"): dependencies point inward'):format(
              f.layer,
              imp.layer,
              imp.spec
            ),
          }
        elseif imp.framework and (f.layer == "domain" or f.layer == "application") then
          out[#out + 1] = {
            file = f.rel,
            line = imp.line,
            severity = f.layer == "domain" and SEV.ERROR or SEV.WARN,
            rule = "framework",
            message = ('%s imports the framework "%s": define a port (interface) and implement it in infrastructure'):format(
              f.layer,
              imp.framework
            ),
          }
        end
      end
      if not FILE_IS_TYPE[f.ext] then
        local stem = vim.fn.fnamemodify(f.rel, ":t:r"):lower():gsub("[_%-%.]", "")
        for _, t in ipairs(f.types) do
          for _, suffix in ipairs(ROLE_SUFFIX) do
            if t.name ~= suffix and t.name:sub(-#suffix) == suffix and not stem:find(suffix:lower(), 1, true) then
              out[#out + 1] = {
                file = f.rel,
                line = t.first,
                severity = SEV.INFO,
                rule = "naming",
                message = ('%s is declared in %s: the file name should mention "%s"'):format(
                  t.name,
                  vim.fn.fnamemodify(f.rel, ":t"),
                  suffix:lower()
                ),
              }
              break
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.severity ~= b.severity then
      return a.severity < b.severity
    end
    return a.file == b.file and a.line < b.line or a.file < b.file
  end)
  return out
end

---@class DddAggregate
---@field name string
---@field file string
---@field line integer
---@field port { name: string, file: string, line: integer }?
---@field impl { name: string, file: string, line: integer }?
---@field usecases string[]
---@field wired boolean?  nil = sin comprobar

--- Entidades del dominio (tipos con identidad) y las piezas que las rodean
---@param index DddIndex
---@return DddAggregate[]
function M.aggregates(index)
  local entities, all = {}, {}
  for _, f in ipairs(index.list) do
    if not f.test then
      for _, t in ipairs(f.types) do
        all[#all + 1] = { file = f, type = t }
        if f.layer == "domain" and t.kind == "class" and t.has_id and not ends_with(t.name, ENTITY_EXCLUDE) then
          entities[#entities + 1] = { file = f, type = t }
        end
      end
    end
  end

  local out = {}
  for _, e in ipairs(entities) do
    local lower = e.type.name:lower()
    local agg = { name = e.type.name, file = e.file.rel, line = e.type.first, usecases = {} }
    for _, c in ipairs(all) do
      local name = c.type.name
      if name ~= e.type.name and name:lower():find(lower, 1, true) then
        if
          c.type.kind == "interface"
          and has_word(name, REPO_WORDS)
          and (c.file.layer == "domain" or c.file.layer == "application")
        then
          agg.port = agg.port or { name = name, file = c.file.rel, line = c.type.first }
        elseif c.type.kind == "class" and has_word(name, REPO_WORDS) then
          agg.impl = agg.impl or { name = name, file = c.file.rel, line = c.type.first }
        elseif c.file.layer == "application" and c.type.kind == "class" and #agg.usecases < 5 then
          agg.usecases[#agg.usecases + 1] = name
        end
      end
    end
    out[#out + 1] = agg
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

--- Marca `wired` en cada agregado con implementación: ¿el nombre aparece en algún otro archivo que no sea test?
---@param index DddIndex
---@param aggs DddAggregate[]
---@param cb fun()
function M.wire(index, aggs, cb)
  local pending = 0
  local function done()
    pending = pending - 1
    if pending <= 0 then
      cb()
    end
  end
  if vim.fn.executable "rg" ~= 1 then
    return cb()
  end
  for _, agg in ipairs(aggs) do
    if agg.impl then
      pending = pending + 1
      vim.system({
        "rg",
        "-l",
        "-w",
        "--glob",
        "!*_test.*",
        "--glob",
        "!*.test.*",
        "--glob",
        "!*.spec.*",
        "--glob",
        "!**/test/**",
        "--glob",
        "!**/tests/**",
        "--",
        agg.impl.name,
        index.root,
      }, { text = true }, function(out) -- stylua: ignore
        vim.schedule(function()
          local wired = false
          for file in (out.stdout or ""):gmatch "[^\r\n]+" do
            if file:sub(#index.root + 2) ~= agg.impl.file then
              wired = true
              break
            end
          end
          agg.wired = wired
          done()
        end)
      end)
    end
  end
  if pending == 0 then
    cb()
  end
end

---@class DddStep
---@field text string
---@field severity integer

--- Lo que falta, como lista accionable, con nombres de archivo según la convención del proyecto
---@param index DddIndex
---@param aggs DddAggregate[]
---@param naming DddNaming
---@return DddStep[]
function M.next_steps(index, aggs, naming)
  local steps = {}
  for _, a in ipairs(aggs) do
    local dir = vim.fn.fnamemodify(a.file, ":h")
    local ext = a.file:match "%.([%w]+)$" or ""
    if not a.port then
      steps[#steps + 1] = {
        severity = SEV.WARN,
        text = ("Define the repository port for %s: `%sRepository` in `%s/%s`"):format(
          a.name,
          a.name,
          dir,
          naming_mod.suggest(naming, ext, a.name, "repository")
        ),
      }
    elseif not a.impl then
      steps[#steps + 1] = {
        severity = SEV.WARN,
        text = ("Implement `%s` in infrastructure (e.g. `%s`)"):format(
          a.port.name,
          naming_mod.suggest(naming, ext, a.name, "repository")
        ),
      }
    elseif a.wired == false then
      steps[#steps + 1] = {
        severity = SEV.WARN,
        text = ("Wire `%s` in the composition root: nothing outside its own file uses it"):format(a.impl.name),
      }
    end
    if #a.usecases == 0 then
      steps[#steps + 1] = {
        severity = SEV.INFO,
        text = ("No use case in application mentions %s: add one (e.g. `%s`)"):format(
          a.name,
          naming_mod.suggest(naming, ext, "Create" .. a.name, "usecase")
        ),
      }
    end
  end
  return steps
end

return M
