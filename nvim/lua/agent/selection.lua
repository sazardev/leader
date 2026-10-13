-- ── Which backend and model are used ─────────────────────────────────────────
-- Priority: what was picked with <leader>am (state) > settings.agent > autodetection.
-- The backends know nothing about this: they receive the already-resolved model in the request.
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

--- Light model of the backend; if none is defined, the main one (an id is never invented)
--- Backend of the light actions: the one chosen for them (`light_backend`, in the state or in settings) if it is
--- available; otherwise the same as the main one. That way docs/explain can run on a free local model
--- while implement/fix stay on Claude.
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

--- "main" or "light": from the action, unless `settings.agent.tiers` reassigns it
---@param action table?
---@return "main"|"light"
function M.tier_of(action)
  if not action then
    return "main"
  end
  return settings.tiers[action.name] or action.tier or "main"
end

--- Selection for an action: its tier decides the model. Light actions do not inherit the
--- effort you set either: they are the cheap ones, they must not turn expensive because of a setting meant for others.
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
---@param tier "main"|"light"? default "main"
function M.set(backend, model, tier)
  local key = tier == "light" and "light_models" or "models"
  local models = state.get(key) or {}
  models[backend] = model
  state.set(key, models)
  -- picking the light model does NOT change the main backend: it sets the backend of the light actions
  state.set(tier == "light" and "light_backend" or "backend", backend)
end

---@param effort string? nil = the model's default value
function M.set_effort(effort)
  state.set("effort", effort)
end

return M
