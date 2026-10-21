-- ── Extra context, within a budget ───────────────────────────────────────────
-- Each action declares which providers it wants (`context = { "rules", "outline"... }`).
-- A provider is `{ cap, collect(target, done) }` and may be asynchronous. Here they are
-- launched in parallel and, when the last one finishes, assembled IN THE DECLARED ORDER
-- until `settings.agent.context.max_chars` runs out (so the declared order is the PRIORITY when the budget is tight).
-- The target does not count: it goes apart.
--
-- What is handed to the prompt is then ARRANGED by `provider.stability`: 1 = the same on every call of the project (rules),
-- 2 = changes only when the code does (types, outline, contracts...), 3 = changes with the cursor or the editor state
-- (diagnostics, findings, the code around, callers, history). Servers that keep the KV cache of the last prompt (Ollama,
-- llama.cpp, vLLM) and APIs with prefix caching only reuse what is IDENTICAL FROM THE START of the prompt: the stable
-- part goes first and the volatile one last, so a second call on the same code re-reads only the tail.
local settings = require("core.settings").agent.context
local text = require "agent.text"

local M = {}

---@param name string
---@return table
local function provider(name)
  return require("agent.context.providers." .. name)
end

---@param name string
---@return integer
local function stability_of(name)
  local ok, p = pcall(provider, name)
  return ok and p.stability or 2
end

--- Most stable first; the declared order is kept within each level (a stable sort)
---@param sections { name: string, text: string }[]
---@param rank fun(name: string): integer
---@return { name: string, text: string }[]
function M.arrange(sections, rank)
  local keyed = {}
  for i, s in ipairs(sections) do
    keyed[i] = { s = s, r = rank(s.name), i = i }
  end
  table.sort(keyed, function(a, b)
    if a.r ~= b.r then
      return a.r < b.r
    end
    return a.i < b.i
  end)
  return vim.tbl_map(function(k)
    return k.s
  end, keyed)
end

---@param action table
---@param target AgentTarget
---@param done fun(sections: { name: string, text: string }[])
---@param opts { max_chars: integer? }? a capability profile may ask for a tighter budget (a small model drowns in context)
function M.build(action, target, done, opts)
  local names = action.context or {}
  local results, pending = {}, #names
  if pending == 0 then
    return done {}
  end

  local function assemble()
    local sections, remaining = {}, (opts and opts.max_chars) or settings.max_chars
    for i, name in ipairs(names) do
      local r = results[i]
      if r and remaining > 0 then
        local body = text.clip(r.text, math.min(r.cap, remaining))
        remaining = remaining - #body
        sections[#sections + 1] = { name = name, text = body }
      end
    end
    done(M.arrange(sections, stability_of))
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
