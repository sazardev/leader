-- ── Answer cache: pure logic ─────────────────────────────────────────────────
-- A request is identified by EVERYTHING that goes to the model: the system prompt, the message (file, context sections,
-- target, task, the user's instruction) and who answers it (backend, model, effort). Same hash = same question, so the
-- stored answer is still valid; any change to the code, a type it uses, a diagnostic or the instruction changes the hash.
-- No I/O here (agent/cache/init.lua persists), so it is covered by plain tests.
local M = {}

---@class AgentCacheEntry
---@field text string
---@field ts integer      when it was stored
---@field used integer    last time it answered (what the pruning keeps)
---@field action string
---@field tokens integer? what the original call cost: shown as "saved"
---@field cost number?

--- Hash of a request
---@param req { backend: string?, model: string?, effort: string?, system: string, prompt: string }
---@return string
function M.key(req)
  local head = table.concat({ req.backend or "", req.model or "", req.effort or "" }, "\0")
  return vim.fn.sha256(head .. "\1" .. req.system .. "\1" .. req.prompt)
end

--- Does this action's answer get cached? `action.cache = false` opts out, `true` opts in; otherwise by its output kind
--- (a `replace` proposal is a decision on live code: asking again should give a fresh one)
---@param action table
---@param cfg { enabled: boolean?, outputs: string[]? }
---@return boolean
function M.eligible(action, cfg)
  if not cfg.enabled or action.cache == false then
    return false
  end
  if action.cache == true then
    return true
  end
  return vim.tbl_contains(cfg.outputs or {}, action.output)
end

--- Is this answer worth keeping?
---@param text string?
---@param cfg { max_chars: integer? }
---@return boolean
function M.storable(text, cfg)
  return type(text) == "string" and text:match "%S" ~= nil and #text <= (cfg.max_chars or 20000)
end

--- Drops what expired, then what is least recently used beyond the limit. Returns how many it dropped.
---@param entries table<string, AgentCacheEntry>
---@param now integer
---@param cfg { ttl_days: number?, max_entries: integer? }
---@return integer
function M.prune(entries, now, cfg)
  local dropped = 0
  local ttl = (cfg.ttl_days or 30) * 86400
  local live = {}
  for key, e in pairs(entries) do
    if type(e) ~= "table" or type(e.text) ~= "string" or now - (e.used or e.ts or 0) > ttl then
      entries[key] = nil
      dropped = dropped + 1
    else
      live[#live + 1] = key
    end
  end
  local max = cfg.max_entries or 300
  if #live > max then
    table.sort(live, function(a, b)
      return (entries[a].used or 0) > (entries[b].used or 0)
    end)
    for i = max + 1, #live do
      entries[live[i]] = nil
      dropped = dropped + 1
    end
  end
  return dropped
end

return M
