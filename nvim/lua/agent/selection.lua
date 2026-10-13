-- ── Qué backend y modelo se usan ─────────────────────────────────────────────
-- Prioridad: lo elegido con <leader>am (state) > settings.agent > autodetección.
-- Los backends no saben nada de esto: reciben el modelo ya resuelto en la petición.
local settings = require("core.settings").agent
local backends = require "agent.backends"
local state = require "agent.state"

local M = {}

---@class AgentSelection
---@field backend string
---@field model string?
---@field effort string?
---@field tier "main"|"light"?

---@return string?
local function backend_name()
  local wanted = state.get "backend"
  if wanted and backends.is_available(wanted) then
    return wanted
  end
  if settings.backend ~= "auto" and backends.is_available(settings.backend) then
    return settings.backend
  end
  return backends.first_available(settings.order)
end

---@param name string
---@return string?
local function main_model(name)
  return (state.get "models" or {})[name] or (settings[name] or {}).model or backends.get(name).default_model
end

--- Modelo ligero del backend; si no hay uno definido, el principal (nunca se inventa un id)
--- Backend de las acciones ligeras: el elegido para ellas (`light_backend`, en el estado o en settings) si está
--- disponible; si no, el mismo que el principal. Así docs/explain pueden correr en un modelo local gratis
--- mientras implement/fix siguen en Claude.
---@param main string
---@return string
local function light_backend(main)
  local wanted = state.get "light_backend" or settings.light_backend
  if wanted and wanted ~= main and backends.is_available(wanted) then
    return wanted
  end
  return main
end

---@param name string
---@return string?
local function light_model(name)
  return (state.get "light_models" or {})[name] or (settings[name] or {}).light_model or main_model(name)
end

--- "main" o "light": de la acción, salvo que `settings.agent.tiers` la reasigne
---@param action table?
---@return "main"|"light"
function M.tier_of(action)
  if not action then
    return "main"
  end
  return settings.tiers[action.name] or action.tier or "main"
end

--- Selección para una acción: su tier decide el modelo. Las acciones ligeras tampoco heredan
--- el esfuerzo que fijaste: son las baratas, no deben salir caras por un ajuste pensado para otras.
---@param action table?
---@return AgentSelection?
function M.current(action)
  local name = backend_name()
  if not name then
    return nil
  end
  local light = M.tier_of(action) == "light"
  if light then
    name = light_backend(name)
  end
  return {
    backend = name,
    model = light and light_model(name) or main_model(name),
    effort = (not light) and state.get "effort" or nil,
    tier = light and "light" or "main",
  }
end

---@param sel AgentSelection
---@return string
function M.label(sel)
  return sel.backend .. "/" .. (sel.model or "default")
end

---@param backend string
---@param model string
---@param tier "main"|"light"? por defecto "main"
function M.set(backend, model, tier)
  local key = tier == "light" and "light_models" or "models"
  local models = state.get(key) or {}
  models[backend] = model
  state.set(key, models)
  -- elegir el modelo ligero NO cambia el backend principal: fija el backend de las acciones ligeras
  state.set(tier == "light" and "light_backend" or "backend", backend)
end

---@param effort string? nil = el valor por defecto del modelo
function M.set_effort(effort)
  state.set("effort", effort)
end

return M
