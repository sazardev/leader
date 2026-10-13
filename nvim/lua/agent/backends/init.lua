-- ── Registro de backends ─────────────────────────────────────────────────────
-- Un backend = un CLI de agente que sabe (a) construir su comando y (b) interpretar
-- su salida. Contrato (todos los campos obligatorios salvo los marcados):
--
--   name, label     string
--   default_model   string?                     modelo si nada más lo define
--   efforts         string[]?                   niveles de esfuerzo que entiende
--   available()     boolean                     ¿el CLI está instalado?
--   models(cb)      cb({ {id, label?}... })     modelos elegibles (puede ser async)
--   build(req)      { cmd, stdin?, env?, cwd }  petición -> proceso a lanzar
--   parser()        { feed(chunk) -> string?,   texto nuevo (streaming), si lo hay
--                     finish(code, stderr) -> AgentResult }
--
--   AgentRequest: { system, prompt, model, effort?, action }
--   AgentResult:  { ok, text?, err?, usage? = { cost?, tokens_in?, tokens_out?, ms? } }
--
-- Añadir un backend: crea `agent/backends/<nombre>.lua` y agrégalo a NAMES (o
-- regístralo en runtime con `register`). Nada más cambia.
local M = {}

local NAMES = { "claude", "opencode", "ollama", "openai" }

---@type table<string, table>
local registry = {}

--- Registra, una sola vez, los backends declarados en `settings.agent.custom` (Hermes Agent, Gemini CLI...)
local custom_loaded = false
local function load_custom()
  if custom_loaded then
    return
  end
  custom_loaded = true
  for name, spec in pairs(require("core.settings").agent.custom or {}) do
    if type(spec) == "table" and not registry[name] then
      registry[name] = require("agent.backends.command").from_spec(name, spec)
      if not vim.tbl_contains(NAMES, name) then
        NAMES[#NAMES + 1] = name
      end
    end
  end
end

---@return string[]
function M.names()
  load_custom()
  return vim.list_extend({}, NAMES)
end

---@param name string
---@return table
function M.get(name)
  load_custom()
  if not registry[name] then
    registry[name] = require("agent.backends." .. name)
  end
  return registry[name]
end

--- Registra un backend en caliente (extensiones, pruebas)
---@param name string
---@param impl table
function M.register(name, impl)
  registry[name] = impl
  if not vim.tbl_contains(NAMES, name) then
    table.insert(NAMES, name)
  end
end

---@param name string
---@return boolean
function M.is_available(name)
  local ok, backend = pcall(M.get, name)
  return ok and backend.available()
end

---@return table[]
function M.available()
  load_custom()
  local list = {}
  for _, name in ipairs(NAMES) do
    if M.is_available(name) then
      table.insert(list, M.get(name))
    end
  end
  return list
end

---@param order string[]?
---@return string?
function M.first_available(order)
  load_custom()
  local tried = {}
  for _, list in ipairs { order or {}, NAMES } do -- primero el orden pedido; luego el resto (los `custom` incluidos)
    for _, name in ipairs(list) do
      if not tried[name] then
        tried[name] = true
        if M.is_available(name) then
          return name
        end
      end
    end
  end
end

return M
