-- ── Puertos de los que depende un servicio ───────────────────────────────────
-- Un servicio de aplicación (caso de uso) solo puede llamar a los métodos que sus puertos declaran. Esto encuentra las
-- interfaces que el servicio recibe (campos, parámetros del constructor, parámetros del método) y las lee con sus firmas
-- reales, en cualquier lenguaje (rg + treesitter): así llama a `orders.ByID(ctx, id)`, no a un método que se inventó.
local contracts = require "agent.repository.contracts"
local discovery = require "agent.discovery"
local layers = require "agent.ddd.layers"
local scopes = require "agent.context.scopes"

local M = {}

local SERVICE_WORDS = { "service", "usecase", "interactor", "handler", "manager", "application", "command", "query" }
local IGNORED = {
  Context = true,
  Error = true,
  String = true,
  Number = true,
  Boolean = true,
  Promise = true,
  Array = true,
  Object = true,
  Date = true,
  Map = true,
  Set = true,
  Time = true,
  Duration = true,
  Self = true,
  Option = true,
  Result = true,
  Vec = true,
  None = true,
  Some = true,
}

--- ¿Parece un servicio de aplicación? (por su nombre o por vivir en la capa de aplicación)
---@param T string
---@param path string
---@return boolean
function M.looks_like_service(T, path)
  local lower = T:lower()
  for _, w in ipairs(SERVICE_WORDS) do
    if lower:find(w, 1, true) then
      return true
    end
  end
  return layers.of(path) == "application"
end

--- ¿La declaración es una interfaz/puerto?
---@param lines string[]
---@return boolean
local function is_interface(lines)
  local head = (lines[1] or ""):lower()
  return head:find "interface" ~= nil
    or head:find "trait%s" ~= nil
    or head:find "protocol" ~= nil
    or head:find "abstract" ~= nil
    or head:find "%(.*abc" ~= nil
end

--- Nombres de tipo candidatos a ser puertos: los de la declaración del servicio y los del objetivo
---@param target AgentTarget
---@param T string
---@return string[]
local function candidates(target, T)
  local words, seen = {}, { [T] = true }
  local function add(text)
    for w in text:gmatch "%f[%w_]%u[%w_]*" do
      if not seen[w] and not IGNORED[w] and #words < 10 then
        seen[w] = true
        words[#words + 1] = w
      end
    end
  end
  for _, d in ipairs(scopes.type_declarations(target.buf)) do
    if d.name == T and not d.kind:find("impl", 1, true) then
      add(table.concat(vim.api.nvim_buf_get_lines(target.buf, d.first - 1, d.last, false), "\n"))
    end
  end
  add(table.concat(target.lines, "\n"))
  -- constructor de Go: sus parámetros dicen qué se inyecta
  local text = table.concat(vim.api.nvim_buf_get_lines(target.buf, 0, -1, false), "\n")
  for params in text:gmatch "func%s+New[%w_]*%s*(%b())" do
    add(params)
  end
  return words
end

---@class AgentDependency
---@field name string
---@field path string
---@field line integer
---@field lines string[]
---@field methods string[]

--- Los puertos (interfaces del proyecto) que usa el servicio `T`, con sus firmas
---@param root string
---@param target AgentTarget
---@param T string
---@param ext string
---@param cb fun(list: AgentDependency[])
function M.dependencies(root, target, T, ext, cb)
  local words = candidates(target, T)
  local found, pending = {}, #words
  if pending == 0 then
    return cb {}
  end
  for _, word in ipairs(words) do
    discovery.find_type(root, word, ext, function(t)
      if t and is_interface(t.lines) and #found < 4 then
        t.methods = contracts.port_methods(t.lines, ext)
        found[#found + 1] = t
      end
      pending = pending - 1
      if pending == 0 then
        table.sort(found, function(a, b)
          return a.name < b.name
        end)
        cb(found)
      end
    end)
  end
end

--- Nombre del campo/parámetro con el que el servicio guarda un puerto (`orders` para `orders order.OrderRepository`)
---@param decl_text string
---@param port string
---@return string?
function M.field_name(decl_text, port)
  local p = vim.pesc(port)
  for line in decl_text:gmatch "[^\n]+" do
    if line:find("%f[%w_]" .. p .. "%f[^%w_]") then
      local name = line:match("^%s*([%a_][%w_]*)%s+[%w_%.%*%[%]]*" .. p) -- Go: orders order.OrderRepository
        or line:match("([%a_][%w_]*)%s*%??:%s*[%w_%.<>]*" .. p) -- TS / Python / Kotlin
        or line:match(p .. "%s+([%a_][%w_]*)%s*[;=,)]") -- Java / C#
      if name and name ~= "private" and name ~= "readonly" and name ~= "final" then
        return name
      end
    end
  end
  return nil
end

return M
