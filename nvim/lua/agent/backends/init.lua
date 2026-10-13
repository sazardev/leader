-- ── Backend registry ─────────────────────────────────────────────────────────
-- A backend = an agent CLI that knows (a) how to build its command and (b) how to parse
-- its output. Contract (all fields required unless marked):
--
--   name, label     string
--   default_model   string?                     model if nothing else defines one
--   efforts         string[]?                   effort levels it understands
--   available()     boolean                     is the CLI installed?
--   models(cb)      cb({ {id, label?}... })     selectable models (may be async)
--   build(req)      { cmd, stdin?, env?, cwd }  request -> process to launch
--   parser()        { feed(chunk) -> string?,   new text (streaming), if any
--                     finish(code, stderr) -> AgentResult }
--
--   AgentRequest: { system, prompt, model, effort?, action }
--   AgentResult:  { ok, text?, err?, usage? = { cost?, tokens_in?, tokens_out?, ms? } }
--
-- Adding a backend: create `agent/backends/<name>.lua` and add it to NAMES (or
-- register it at runtime with `register`). Nothing else changes.
local M = {}

local NAMES = { "claude", "opencode", "ollama", "openai" }

---@type table<string, table>
local registry = {}

--- Registers, once, the backends declared in `settings.agent.custom` (Hermes Agent, Gemini CLI...)
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

--- Registers a backend on the fly (extensions, tests)
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
  for _, list in ipairs { order or {}, NAMES } do -- requested order first; then the rest (`custom` ones included)
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
