-- ── Diagnóstico DDD de todo el proyecto (0 tokens) ───────────────────────────
-- Análisis estático local: capas detectadas, nomenclatura, violaciones (como diagnósticos y lista de
-- quickfix), y por entidad las piezas que faltan y sus conexiones. Un panel lo resume; lo accionable
-- queda en el propio código.
local index_mod = require "agent.ddd.index"
local layers = require "agent.ddd.layers"
local log = require "utils.log"
local naming_mod = require "agent.ddd.naming"
local panel = require "agent.ui.panel"
local persist = require "agent.persist"
local rules = require "agent.ddd.rules"
local settings = require("core.settings").agent.ddd

local M = {}

local NS = vim.api.nvim_create_namespace "agent.ddd"

vim.diagnostic.config({
  virtual_text = false, -- se ve en los bloques en línea (utils/diagblocks.lua)
  underline = true,
  signs = false,
  severity_sort = true,
}, NS)

---@return integer
function M.namespace()
  return NS
end

--- Quita los diagnósticos de DDD (de todos los buffers)
function M.clear()
  vim.diagnostic.reset(NS)
  persist.forget_all "ddd"
end

--- Quita las violaciones locales que caen en un rango (se acaba de arreglar ese código)
---@param buf integer
---@param first integer 1-based
---@param last integer 1-based
---@return integer removed cuántas quitó
function M.resolve(buf, first, last)
  local all = vim.diagnostic.get(buf, { namespace = NS })
  local kept = vim.tbl_filter(function(d)
    return d.lnum + 1 < first or d.lnum + 1 > last
  end, all)
  vim.diagnostic.set(NS, buf, kept)
  persist.sync(buf, "ddd")
  return #all - #kept
end

---@param s string
---@return string
local function cell(s)
  return (s:gsub("|", "\\|"))
end

---@param index DddIndex
---@return table<string, string[]> capa → directorios (hasta el segmento que la nombra)
local function layer_dirs(index)
  local dirs = {}
  for _, f in ipairs(index.list) do
    if f.layer and not f.test then
      local acc = {}
      for seg in f.rel:gmatch "[^/]+" do
        acc[#acc + 1] = seg
        if layers.of(seg) == f.layer then
          break
        end
      end
      dirs[f.layer] = dirs[f.layer] or {}
      local path = table.concat(acc, "/")
      if not vim.tbl_contains(dirs[f.layer], path) then
        table.insert(dirs[f.layer], path)
      end
    end
  end
  return dirs
end

---@param index DddIndex
---@param violations DddViolation[]
local function publish(index, violations, steps, aggs)
  vim.diagnostic.reset(NS)
  local by_file, qf = {}, {}
  local type_of = {
    [vim.diagnostic.severity.ERROR] = "E",
    [vim.diagnostic.severity.WARN] = "W",
    [vim.diagnostic.severity.INFO] = "I",
  }
  for _, v in ipairs(violations) do
    by_file[v.file] = by_file[v.file] or {}
    table.insert(
      by_file[v.file],
      { lnum = v.line - 1, col = 0, severity = v.severity, message = v.message, source = "ddd" }
    )
    qf[#qf + 1] = {
      filename = index.root .. "/" .. v.file,
      lnum = v.line,
      col = 1,
      type = type_of[v.severity] or "I",
      text = "[ddd] " .. v.message,
    }
  end
  local persisted = {}
  for file, list in pairs(by_file) do
    persisted[index.root .. "/" .. file] = vim.tbl_map(function(d)
      return { line = d.lnum + 1, severity = d.severity, message = d.message, source = "ddd" }
    end, list)
    local buf = vim.fn.bufadd(index.root .. "/" .. file)
    vim.bo[buf].buflisted = false
    vim.diagnostic.set(NS, buf, list)
  end
  persist.replace_all("ddd", persisted) -- por atender: sobrevive a la sesión
  local at = {}
  for _, a in ipairs(aggs) do
    at[a.name] = a
  end
  for _, step in ipairs(steps) do
    local agg = at[step.text:match "for (%w+):" or step.text:match "mentions (%w+):" or ""] or aggs[1]
    qf[#qf + 1] = {
      filename = agg and (index.root .. "/" .. agg.file) or index.root,
      lnum = agg and agg.line or 1,
      col = 1,
      type = "I",
      text = "[ddd] missing: " .. step.text,
    }
  end
  vim.fn.setqflist({}, " ", { title = "DDD diagnosis", items = qf })
end

---@param index DddIndex
---@param naming DddNaming
---@param violations DddViolation[]
---@param aggs DddAggregate[]
---@param steps DddStep[]
---@return string[]
local function report(index, naming, violations, aggs, steps)
  local project = vim.fn.fnamemodify(index.root, ":t")
  local lines = {
    "# DDD diagnosis · " .. project,
    "",
    ("_Static analysis, **0 tokens**: %d layer files analysed (of %d source files)._"):format(#index.list, index.seen),
    "",
    "## Layers",
    "",
  }
  if vim.tbl_isempty(index.counts) then
    vim.list_extend(lines, {
      "No layer directories found. Looked for folders named like:",
      "",
    })
    for _, layer in ipairs(layers.ORDER) do
      lines[#lines + 1] = ("- **%s**: %s"):format(layer, table.concat(settings.layers[layer], ", "))
    end
    vim.list_extend(lines, { "", "Rename your folders or extend `settings.agent.ddd.layers` in `local.lua`." })
  else
    local dirs = layer_dirs(index)
    vim.list_extend(lines, { "| Layer | Files | Directories |", "|---|---|---|" })
    for _, layer in ipairs(layers.ORDER) do
      if index.counts[layer] then
        lines[#lines + 1] = ("| %s | %d | %s |"):format(
          layer,
          index.counts[layer],
          table.concat(
            vim.tbl_map(function(d)
              return "`" .. d .. "`"
            end, vim.list_slice(dirs[layer] or {}, 1, 4)),
            ", "
          )
        )
      end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] =
      "Dependency rule: **domain ← application ← infrastructure / interface** (arrows point inward)."
  end

  local roles = {}
  for _, r in ipairs(naming.roles) do
    roles[#roles + 1] = ("%s (%d)"):format(r.name, r.count)
  end
  vim.list_extend(lines, {
    "",
    "## Naming",
    "",
    ("Files: **%s**%s%s"):format(
      naming.label,
      #roles > 0 and (" · roles: " .. table.concat(roles, ", ")) or "",
      naming.example and (" · e.g. `" .. naming.example .. "`") or ""
    ),
  })

  lines[#lines + 1] = ""
  lines[#lines + 1] = ("## Violations (%d)"):format(#violations)
  lines[#lines + 1] = ""
  if #violations == 0 then
    lines[#lines + 1] = "None found ✓"
  else
    vim.list_extend(lines, { "| Where | Rule | Detail |", "|---|---|---|" })
    for i, v in ipairs(violations) do
      if i > 15 then
        lines[#lines + 1] = ("| … | | %d more: see the quickfix list (`:copen`) |"):format(#violations - 15)
        break
      end
      lines[#lines + 1] = ("| `%s:%d` | %s | %s |"):format(v.file, v.line, v.rule, cell(v.message))
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Aggregates: pieces and connections"
  lines[#lines + 1] = ""
  if #aggs == 0 then
    lines[#lines + 1] = "No entities found in the domain layer (types with an identity field)."
  else
    vim.list_extend(lines, { "| Aggregate | Port | Implementation | Wired | Use cases |", "|---|---|---|---|---|" })
    for _, a in ipairs(aggs) do
      lines[#lines + 1] = ("| %s | %s | %s | %s | %s |"):format(
        a.name,
        a.port and ("✓ `" .. a.port.name .. "`") or "✗",
        a.impl and ("✓ `" .. a.impl.name .. "`") or (a.port and "✗" or "–"),
        a.impl and (a.wired == true and "✓" or (a.wired == false and "✗" or "?")) or "–",
        #a.usecases > 0 and table.concat(a.usecases, ", ") or "✗"
      )
    end
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = ("## What is missing (%d)"):format(#steps)
  lines[#lines + 1] = ""
  if #steps == 0 then
    lines[#lines + 1] = "Nothing missing ✓"
  else
    for _, s in ipairs(steps) do
      lines[#lines + 1] = "- [ ] " .. s.text
    end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] =
    "_Violations are also diagnostics in the code (◈) and in the quickfix list. `<leader>ax` clears them._"
  return lines
end

function M.run()
  local root = index_mod.root(vim.api.nvim_get_current_buf())
  log.info "DDD: analysing the project…"
  index_mod.get(root, function(index)
    local naming = naming_mod.profile(index)
    local violations = rules.violations(index)
    local aggs = rules.aggregates(index)
    rules.wire(index, aggs, function()
      local steps = rules.next_steps(index, aggs, naming)
      publish(index, violations, steps, aggs)
      panel.open(
        report(index, naming, violations, aggs, steps),
        ("DDD diagnosis · %d violations · %d missing"):format(#violations, #steps)
      )
    end)
  end)
end

return M
