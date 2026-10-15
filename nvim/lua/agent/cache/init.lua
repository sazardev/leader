-- ── Answer cache ─────────────────────────────────────────────────────────────
-- Asking the same thing about the same code costs nothing the second time. The pipeline asks `lookup` once the prompt is
-- built (before the budget guard: a hit spends nothing) and the runner calls `store` when a call succeeds. Only the
-- answers that are text or findings are kept by default (see core.eligible). Persistent in stdpath("state"), saved a
-- moment after the last change and on exit; a broken or missing file is just an empty cache.
local core = require "agent.cache.core"
local settings = require("core.settings").agent.cache

local M = {}

---@type string?
local override
---@type table<string, AgentCacheEntry>?
local entries
---@type { hits: integer, tokens: integer, cost: number }
local stats = { hits = 0, tokens = 0, cost = 0 }
local dirty, timer = false, nil

---@return string
function M.path()
  return override or (vim.fn.stdpath "state" .. "/agent-cache.json")
end

--- Changes the file and forgets what is in memory (tests)
---@param path string?
function M.use(path)
  override, entries, dirty = path, nil, false
  stats = { hits = 0, tokens = 0, cost = 0 }
end

---@return table<string, AgentCacheEntry>
local function load()
  if entries then
    return entries
  end
  entries = {}
  local f = io.open(M.path(), "r")
  if f then
    local ok, data = pcall(vim.json.decode, f:read "*a")
    f:close()
    if ok and type(data) == "table" and type(data.entries) == "table" then
      entries = data.entries
      stats = vim.tbl_extend("force", stats, type(data.stats) == "table" and data.stats or {})
      core.prune(entries, os.time(), settings)
    end
  end
  return entries
end

function M.flush()
  if not dirty or not entries then
    return
  end
  dirty = false
  core.prune(entries, os.time(), settings)
  vim.fn.mkdir(vim.fn.fnamemodify(M.path(), ":h"), "p")
  local f = io.open(M.path(), "w")
  if f then
    f:write(vim.json.encode { entries = entries, stats = stats })
    f:close()
  end
end

local function touch()
  dirty = true
  if not timer then
    timer = vim.uv.new_timer()
  end
  timer:stop()
  timer:start(2000, 0, vim.schedule_wrap(M.flush))
end

vim.api.nvim_create_autocmd("VimLeavePre", { callback = M.flush })

--- Does this job take part in the cache? (`meta.fresh` skips the lookup, never the storing)
---@param job table
---@return boolean
function M.eligible(job)
  return core.eligible(job.action, settings)
end

---@param job table AgentJob with `system`, `prompt` and `selection`
---@return string
function M.key_of(job)
  local sel = job.selection
  return core.key {
    backend = sel.backend,
    model = sel.model,
    effort = sel.effort,
    system = job.system,
    prompt = job.prompt,
  }
end

--- The stored answer for this job as a backend result, or nil. Marks the job with its key either way.
---@param job table
---@return table? result
function M.lookup(job)
  if not M.eligible(job) then
    return nil
  end
  job.cache_key = M.key_of(job)
  if job.meta and job.meta.fresh then
    return nil
  end
  local e = load()[job.cache_key]
  if not e then
    return nil
  end
  e.used = os.time()
  stats.hits, stats.tokens, stats.cost = stats.hits + 1, stats.tokens + (e.tokens or 0), stats.cost + (e.cost or 0)
  touch()
  return {
    ok = true,
    text = e.text,
    cached = true,
    usage = { cached = true, tokens_in = 0, tokens_out = 0, cost = 0, saved_tokens = e.tokens, saved_cost = e.cost },
  }
end

--- Keeps what a successful call answered
---@param job table
---@param result table
function M.store(job, result)
  if not job.cache_key or result.cached or not core.storable(result.text, settings) then
    return
  end
  local u = result.usage or {}
  local now = os.time()
  load()[job.cache_key] = {
    text = result.text,
    ts = now,
    used = now,
    action = job.action.name,
    tokens = (u.tokens_in or 0) + (u.tokens_out or 0),
    cost = u.cost,
  }
  touch()
end

---@return integer count, integer bytes
function M.size()
  local n, bytes = 0, 0
  for _, e in pairs(load()) do
    n, bytes = n + 1, bytes + #e.text
  end
  return n, bytes
end

--- What the cache has done for you: answers kept, times it answered, and what those calls would have cost
---@return { answers: integer, bytes: integer, hits: integer, tokens: integer, cost: number }
function M.stats()
  local n, bytes = M.size()
  return { answers = n, bytes = bytes, hits = stats.hits, tokens = stats.tokens, cost = stats.cost }
end

--- Forgets every stored answer (the counters stay: they are what it saved you so far). Returns how many there were.
---@return integer
function M.clear()
  local n = M.size()
  entries, dirty = {}, true
  M.flush()
  return n
end

return M
