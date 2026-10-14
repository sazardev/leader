-- ── Run history filters ──────────────────────────────────────────────────────
-- Narrow the history by agent (the backend: claude, opencode, ollama…), provider (who serves the model), model,
-- action, outcome or project. Filters combine (all must match). Pure: runs in, runs out (tested in test-agent).
local M = {}

---@class AgentRunFilterDim
---@field key string
---@field label string
---@field get fun(run: table): string

--- What the model's name says about who serves it: `anthropic/claude-sonnet` → `anthropic`; claude's CLI is Anthropic's;
--- a local server (ollama) or a custom command is its own provider
---@param run table
---@return string
local function provider(run)
  local model = run.model or ""
  local prefix = model:match "^([%w%-_%.]+)/"
  if prefix then
    return prefix
  end
  if run.backend == "claude" then
    return "anthropic"
  end
  if run.backend == "ollama" then
    return "local (ollama)"
  end
  return run.backend or "?"
end

---@type AgentRunFilterDim[]
M.DIMS = {
  {
    key = "backend",
    label = "Agent",
    get = function(run)
      return run.backend or "?"
    end,
  },
  { key = "provider", label = "Provider", get = provider },
  {
    key = "model",
    label = "Model",
    get = function(run)
      return run.model or "default"
    end,
  },
  {
    key = "action",
    label = "Action",
    get = function(run)
      return run.action or "?"
    end,
  },
  {
    key = "outcome",
    label = "Outcome",
    get = function(run)
      return run.outcome or "pending"
    end,
  },
  {
    key = "project",
    label = "Project",
    get = function(run)
      return vim.fn.fnamemodify(run.cwd or "?", ":t")
    end,
  },
}

---@param key string
---@return AgentRunFilterDim?
function M.dim(key)
  for _, d in ipairs(M.DIMS) do
    if d.key == key then
      return d
    end
  end
end

--- The runs that match every filter (`{ backend = "claude", model = "sonnet" }`)
---@param runs table[]
---@param filter table<string, string>?
---@return table[]
function M.apply(runs, filter)
  if not filter or next(filter) == nil then
    return runs
  end
  local out = {}
  for _, run in ipairs(runs) do
    local keep = true
    for key, want in pairs(filter) do
      local d = M.dim(key)
      if d and d.get(run) ~= want then
        keep = false
        break
      end
    end
    if keep then
      out[#out + 1] = run
    end
  end
  return out
end

--- The values a dimension takes in `runs`, with how many runs and how much they cost, most used first
---@param runs table[]
---@param key string
---@return { value: string, count: integer, cost: number }[]
function M.values(runs, key)
  local d = assert(M.dim(key), "unknown filter " .. key)
  local by = {}
  for _, run in ipairs(runs) do
    local v = d.get(run)
    by[v] = by[v] or { value = v, count = 0, cost = 0 }
    by[v].count = by[v].count + 1
    by[v].cost = by[v].cost + ((run.usage or {}).cost or 0)
  end
  local out = vim.tbl_values(by)
  table.sort(out, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.value < b.value
  end)
  return out
end

--- `agent claude · model sonnet`: the active filters, in the dimensions' order
---@param filter table<string, string>?
---@return string
function M.label(filter)
  local parts = {}
  for _, d in ipairs(M.DIMS) do
    if filter and filter[d.key] then
      parts[#parts + 1] = ("%s %s"):format(d.label:lower(), filter[d.key])
    end
  end
  return table.concat(parts, " · ")
end

return M
