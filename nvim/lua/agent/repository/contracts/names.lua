-- ── Nombres: del adaptador al puerto, de la entidad a la tabla (puro) ────────
--   candidates("PostgresOrderRepository") → { "OrderRepository" }      el puerto que implementa
--   entity_of("PostgresOrderRepository")  → "Order"                      lo que persiste
--   tables("OrderItem")                   → { "order_items", "order_item" }
local M = {}

-- Palabras de un adaptador: no forman parte del nombre del puerto
M.ADAPTERS = {
  "postgres",
  "postgresql",
  "pg",
  "pgx",
  "mysql",
  "maria",
  "mariadb",
  "sqlite",
  "sql",
  "mongo",
  "mongodb",
  "redis",
  "dynamo",
  "dynamodb",
  "memory",
  "inmemory",
  "mock",
  "fake",
  "stub",
  "gorm",
  "sqlx",
  "prisma",
  "typeorm",
  "http",
  "rest",
  "grpc",
  "default",
  "base",
  "cached",
  "caching",
  "smtp",
} -- stylua: ignore

-- Roles que, solos, no identifican un puerto concreto
local GENERIC = {
  repository = true,
  repo = true,
  store = true,
  service = true,
  handler = true,
  client = true,
  manager = true,
  controller = true,
  provider = true,
  gateway = true,
  storage = true,
  dao = true,
  impl = true,
  adapter = true,
}
local REPO_WORDS = { repository = true, repo = true, store = true, dao = true, gateway = true, storage = true }
local SUFFIXES = { impl = true, implementation = true, adapter = true }

---@param name string
---@return string[] palabras (la primera en mayúscula inicial) de un nombre PascalCase/camelCase
local function split(name)
  name = name:sub(1, 1):upper() .. name:sub(2)
  local out = {}
  for w in name:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2"):gmatch "%S+" do
    out[#out + 1] = w
  end
  -- "InMemory" es un solo adaptador, no "In" + "Memory"
  for i = #out - 1, 1, -1 do
    if out[i] == "In" and out[i + 1] == "Memory" then
      out[i] = "InMemory"
      table.remove(out, i + 1)
    end
  end
  return out
end

---@param ws string[]
---@return string
local function join(ws)
  return table.concat(ws)
end

--- Nombres con los que podría llamarse el puerto que implementa `name`, del más específico al menos
---@param name string
---@return string[]
function M.candidates(name)
  local ws = split(name)
  while #ws > 1 and SUFFIXES[ws[#ws]:lower()] do
    ws[#ws] = nil
  end
  local out = {}
  local original = join(split(name))
  for i = 1, #ws - 1 do
    local rest = vim.list_slice(ws, i + 1, #ws)
    local candidate = join(rest)
    if not (#rest == 1 and GENERIC[rest[1]:lower()]) and candidate ~= original then
      out[#out + 1] = candidate
    end
    -- solo se sigue quitando palabras mientras lo quitado sea un adaptador o el primer nombre propio
    if i >= 2 then
      break
    end
  end
  if #ws == 1 or #out == 0 then
    local single = join(ws)
    if single ~= original and not GENERIC[single:lower()] then
      out[#out + 1] = single
    end
  end
  return out
end

--- ¿El nombre parece un adaptador o implementación (candidato a implementar un puerto)?
---@param name string
---@return boolean
function M.looks_like_implementation(name)
  local ws = split(name)
  local last = ws[#ws] and ws[#ws]:lower()
  if last and SUFFIXES[last] then
    return true
  end
  for _, w in ipairs(ws) do
    for _, adapter in ipairs(M.ADAPTERS) do
      if w:lower() == adapter then
        return true
      end
    end
  end
  return #M.candidates(name) > 0 and last ~= nil and REPO_WORDS[last] == true
end

--- La entidad que persiste un repositorio: sin adaptador delante ni rol de repositorio detrás
---@param name string
---@return string?
function M.entity_of(name)
  local ws = split(name)
  while #ws > 1 and SUFFIXES[ws[#ws]:lower()] do
    ws[#ws] = nil
  end
  if #ws > 1 and REPO_WORDS[ws[#ws]:lower()] then
    ws[#ws] = nil
  end
  while #ws > 1 do
    local first = ws[1]:lower()
    local is_adapter = false
    for _, a in ipairs(M.ADAPTERS) do
      is_adapter = is_adapter or a == first
    end
    if not is_adapter then
      break
    end
    table.remove(ws, 1)
  end
  local entity = join(ws)
  return entity ~= "" and not GENERIC[entity:lower()] and entity or nil
end

---@param pascal string
---@return string
function M.snake(pascal)
  return (pascal:gsub("(%l)(%u)", "%1_%2"):gsub("(%u)(%u%l)", "%1_%2"):lower())
end

--- Nombres de tabla probables de una entidad: plural primero ("order" es palabra reservada de SQL)
---@param entity string
---@return string[]
function M.tables(entity)
  local s = M.snake(entity)
  local plural
  if s:match "[^aeiou]y$" then
    plural = s:sub(1, -2) .. "ies"
  elseif s:match "[sxz]$" or s:match "[cs]h$" then
    plural = s .. "es"
  else
    plural = s .. "s"
  end
  return { plural, s }
end

return M
