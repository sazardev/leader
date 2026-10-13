-- ── Nomenclatura que ya usa el proyecto ──────────────────────────────────────
-- En vez de imponer una convención, la DEDUCE de los archivos que existen (estilo de mayúsculas y
-- rol en el nombre: order_repository.go, order.entity.ts, OrderRepository.java) y se la da al modelo
-- y a las sugerencias de archivos faltantes.
local M = {}

M.ROLES = {
  "entity",
  "aggregate",
  "value",
  "vo",
  "repository",
  "repo",
  "service",
  "usecase",
  "handler",
  "controller",
  "dto",
  "command",
  "query",
  "event",
  "factory",
  "mapper",
  "model",
  "port",
  "adapter",
  "policy",
  "specification",
} -- stylua: ignore

local ROLE = {}
for _, r in ipairs(M.ROLES) do
  ROLE[r] = true
end

---@param stem string
---@return string[] palabras en minúscula
local function words(stem)
  local spaced = stem:gsub("(%l)(%u)", "%1_%2")
  local out = {}
  for w in spaced:gmatch "[^_%-%.]+" do
    out[#out + 1] = w:lower()
  end
  return out
end

---@param stem string
---@return string? "snake"|"kebab"|"dotted"|"pascal"
local function style_of(stem)
  if stem:find "%." then
    return "dotted"
  elseif stem:find "_" and not stem:find "%u" then
    return "snake"
  elseif stem:find "%-" then
    return "kebab"
  elseif stem:find "^%u" and stem:find "%l" then
    return "pascal"
  end
  return nil -- una sola palabra en minúsculas: no dice nada del estilo
end

local LABEL = { snake = "snake_case", kebab = "kebab-case", dotted = "dotted (order.entity.ts)", pascal = "PascalCase" }

---@class DddNaming
---@field style string
---@field label string
---@field roles { name: string, count: integer }[]
---@field example string?

--- Estilo dominante y roles más usados en los archivos con capa
---@param index DddIndex
---@return DddNaming
function M.profile(index)
  local styles, roles, example = {}, {}, {}
  for _, f in ipairs(index.list) do
    if f.layer and not f.test then
      local stem = vim.fn.fnamemodify(f.rel, ":t:r")
      local style = style_of(stem)
      if style then
        styles[style] = (styles[style] or 0) + 1
      end
      local seen = {}
      for _, w in ipairs(words(stem)) do
        if ROLE[w] and not seen[w] then
          seen[w] = true
          roles[w] = (roles[w] or 0) + 1
          example[w] = example[w] or vim.fn.fnamemodify(f.rel, ":t")
        end
      end
    end
  end
  local style, best = "snake", 0
  for name, n in pairs(styles) do
    if n > best then
      style, best = name, n
    end
  end
  local list = {}
  for name, n in pairs(roles) do
    list[#list + 1] = { name = name, count = n }
  end
  table.sort(list, function(a, b)
    return a.count == b.count and a.name < b.name or a.count > b.count
  end)
  return {
    style = style,
    label = LABEL[style],
    roles = vim.list_slice(list, 1, 5),
    example = list[1] and example[list[1].name] or nil,
  }
end

---@param pascal string "OrderItem"
---@return string "order_item"
local function snake(pascal)
  return (pascal:gsub("(%l)(%u)", "%1_%2"):lower())
end

--- Nombre de archivo para (entidad, rol) con el estilo del proyecto: order_repository.go, order.repository.ts...
---@param naming DddNaming
---@param ext string
---@param entity string "Order"
---@param role string "repository"
---@return string
function M.suggest(naming, ext, entity, role)
  local base = snake(entity)
  if naming.style == "dotted" then
    return ("%s.%s.%s"):format(base:gsub("_", "-"), role, ext)
  elseif naming.style == "kebab" then
    return ("%s-%s.%s"):format(base:gsub("_", "-"), role, ext)
  elseif naming.style == "pascal" then
    return ("%s%s.%s"):format(entity, role:sub(1, 1):upper() .. role:sub(2), ext)
  end
  return ("%s_%s.%s"):format(base, role, ext)
end

return M
