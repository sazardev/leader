-- ── Contexto extra, dentro de un presupuesto ─────────────────────────────────
-- Cada acción declara qué proveedores quiere (`context = { "rules", "outline"... }`).
-- Un proveedor es `{ cap, collect(target, done) }` y puede ser asíncrono. Aquí se
-- lanzan en paralelo y, al terminar el último, se ensamblan EN EL ORDEN declarado
-- hasta agotar `settings.agent.context.max_chars`. El objetivo no cuenta: va aparte.
local settings = require("core.settings").agent.context
local text = require "agent.text"

local M = {}

---@param name string
---@return table
local function provider(name)
  return require("agent.context.providers." .. name)
end

---@param action table
---@param target AgentTarget
---@param done fun(sections: { name: string, text: string }[])
function M.build(action, target, done)
  local names = action.context or {}
  local results, pending = {}, #names
  if pending == 0 then
    return done {}
  end

  local function assemble()
    local sections, remaining = {}, settings.max_chars
    for i, name in ipairs(names) do
      local r = results[i]
      if r and remaining > 0 then
        local body = text.clip(r.text, math.min(r.cap, remaining))
        remaining = remaining - #body
        sections[#sections + 1] = { name = name, text = body }
      end
    end
    done(sections)
  end

  for i, name in ipairs(names) do
    local p = provider(name)
    local settled = false
    local function settle(body)
      if settled then
        return
      end
      settled = true
      results[i] = body and body ~= "" and { text = body, cap = p.cap } or false
      pending = pending - 1
      if pending == 0 then
        assemble()
      end
    end
    -- un proveedor roto no debe tumbar la acción: simplemente no aporta
    if not pcall(p.collect, target, settle, { names = names, action = action }) then
      settle(nil)
    end
  end
end

return M
