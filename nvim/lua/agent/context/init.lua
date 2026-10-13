-- ── Extra context, within a budget ───────────────────────────────────────────
-- Each action declares which providers it wants (`context = { "rules", "outline"... }`).
-- A provider is `{ cap, collect(target, done) }` and may be asynchronous. Here they are
-- launched in parallel and, when the last one finishes, assembled IN THE DECLARED ORDER
-- until `settings.agent.context.max_chars` runs out. The target does not count: it goes apart.
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
    -- a broken provider must not take the action down: it just contributes nothing
    if not pcall(p.collect, target, settle, { names = names, action = action }) then
      settle(nil)
    end
  end
end

return M
