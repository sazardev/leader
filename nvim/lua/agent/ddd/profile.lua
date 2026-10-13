-- ── La sección <ddd> que va al modelo ────────────────────────────────────────
-- Solo lo que importa para ESTE objetivo: su capa y de quién puede depender, cómo se nombra aquí, qué piezas
-- rodean a las entidades que toca, qué viola ya el archivo y el modismo del lenguaje. Todo sale del análisis local.
local idioms = require "agent.ddd.idioms"
local layers = require "agent.ddd.layers"
local naming_mod = require "agent.ddd.naming"
local settings = require("core.settings").agent.ddd

local M = {}

---@param tbl table<string, boolean>
---@return string
local function allowed_list(tbl)
  local out = {}
  for _, layer in ipairs(layers.ORDER) do
    if tbl[layer] then
      out[#out + 1] = layer
    end
  end
  return table.concat(out, ", ")
end

---@param a DddAggregate
---@return string
local function aggregate_line(a)
  local parts = {}
  parts[#parts + 1] = a.port and ("port %s (%s:%d)"):format(a.port.name, a.port.file, a.port.line) or "port ✗"
  if a.port or a.impl then
    parts[#parts + 1] = a.impl
        and ("impl %s (%s:%d)%s"):format(
          a.impl.name,
          a.impl.file,
          a.impl.line,
          a.wired == true and " wired ✓" or (a.wired == false and " wired ✗" or "")
        )
      or "impl ✗"
  end
  parts[#parts + 1] = #a.usecases > 0 and ("use cases %s"):format(table.concat(a.usecases, ", ")) or "use cases ✗"
  return ("%s: %s"):format(a.name, table.concat(parts, " · "))
end

---@param index DddIndex
---@param rel string  ruta del archivo del objetivo, relativa a la raíz
---@param naming DddNaming
---@param related DddAggregate[]
---@param violations DddViolation[]  las del archivo del objetivo
---@return string
function M.build(index, rel, naming, related, violations)
  local lines = {}
  local layer = layers.of(rel)
  if layer then
    lines[#lines + 1] = ("layer: %s (may depend on: %s)"):format(layer, allowed_list(layers.ALLOWED[layer]))
  else
    lines[#lines + 1] = "layer: this file is not under a recognised layer directory"
  end

  local present = {}
  for _, l in ipairs(layers.ORDER) do
    if index.counts[l] then
      present[#present + 1] = ("%s(%d)"):format(l, index.counts[l])
    end
  end
  if #present > 0 then
    lines[#lines + 1] = "layers in project: " .. table.concat(present, " ")
  end

  local roles = {}
  for _, r in ipairs(naming.roles) do
    roles[#roles + 1] = ("%s(%d)"):format(r.name, r.count)
  end
  local conv = "files: " .. naming.label
  if #roles > 0 then
    conv = conv .. " · roles: " .. table.concat(roles, " ")
  end
  if naming.example then
    conv = conv .. " · e.g. " .. naming.example
  end
  lines[#lines + 1] = conv

  local dir = vim.fn.fnamemodify(rel, ":h")
  local siblings = {}
  for _, f in ipairs(index.list) do
    if not f.test and vim.fn.fnamemodify(f.rel, ":h") == dir and f.rel ~= rel and #siblings < 4 then
      siblings[#siblings + 1] = vim.fn.fnamemodify(f.rel, ":t")
    end
  end
  if #siblings > 0 then
    lines[#lines + 1] = ("in this directory: %s"):format(table.concat(siblings, ", "))
  end

  for i, a in ipairs(related) do
    if i <= 3 then
      lines[#lines + 1] = aggregate_line(a)
    end
  end
  for i, v in ipairs(violations) do
    if i <= 5 then
      lines[#lines + 1] = ("violation line %d: %s"):format(v.line, v.message)
    end
  end

  local idiom = idioms.for_ext(rel:match "%.([%w]+)$" or "")
  if idiom then
    lines[#lines + 1] = idiom
  end

  local text = table.concat(lines, "\n")
  return #text > settings.max_context_chars and text:sub(1, settings.max_context_chars) or text
end

return M
