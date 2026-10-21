-- ── What a model can be trusted with (capability profiles) ───────────────────
-- A strong model gets the task and a short prompt. A small local one gets a smaller target, a tighter context, output
-- the server is forced to shape, and a second try with the real error when its answer is unusable. The point is that the
-- pipeline compensates for the model, not the other way round. Which class a model belongs to is decided, in this order:
--
--   1. the user:       settings.agent.capability.models["ollama/qwen2.5-coder:7b"] = "small" | { class = …, repairs = … }
--   2. what was measured: `make eval EVAL_PROFILE=1` writes pass rates per action; `from_results` turns them into a class
--                      and per-action advice (more repairs where it is shaky, "declined" where it fails)
--   3. its name:       "7b" → small, "haiku"/"mini"/"flash" → medium, "sonnet"/"opus"/"gpt-5" → strong; unknown local models are
--                      small (the cautious guess), unknown hosted ones medium
--
-- Pure (settings and the measured table come in as arguments), tested in scripts/test-agent-capability.lua.
local M = {}

---@alias AgentClass "small"|"medium"|"strong"

---@class AgentProfile
---@field name AgentClass
---@field max_target_lines integer?   a bigger target is declined before anything is sent (nil = the global limit only)
---@field repairs integer             extra attempts when the answer is unusable (no code block, syntax error)
---@field context_chars integer?      budget of the extra context (nil = settings.agent.context.max_chars)
---@field schema boolean              ask the server for schema-constrained output (Ollama, OpenAI-compatible)
---@field decompose boolean           run an instruction that is several things as a chain of single steps (agent/decompose.lua)
---@field declined string?            why an action is not attempted with this model, when measured to fail

--- The classes' defaults; settings.agent.capability.<class> overrides any field
M.DEFAULTS = {
  small = { max_target_lines = 60, repairs = 2, context_chars = 4000, schema = true, decompose = true },
  medium = { max_target_lines = 150, repairs = 1, context_chars = 6000, schema = false, decompose = false },
  strong = { max_target_lines = nil, repairs = 1, context_chars = nil, schema = false, decompose = false },
}

local STRONG = { "opus", "sonnet", "fable", "gpt%-4", "gpt%-5", "gemini.*pro", "^o%d" }
local MEDIUM = { "haiku", "mini", "flash", "nano", "lite" }

---@param model string
---@param words string[]
---@return boolean
local function has(model, words)
  for _, w in ipairs(words) do
    if model:find(w) then
      return true
    end
  end
  return false
end

--- Billions of parameters a model's name admits to ("qwen2.5-coder:7b" → 7, "llama3.1:70b" → 70)
---@param model string
---@return number?
function M.size_b(model)
  local best
  for n in model:lower():gmatch "(%d+%.?%d*)b%f[%W]" do
    best = math.max(best or 0, tonumber(n) or 0)
  end
  return best
end

--- The class a model's NAME suggests
---@param backend string?
---@param model string?
---@return AgentClass
function M.by_name(backend, model)
  local name = (model or ""):lower()
  if has(name, STRONG) then
    return "strong"
  end
  if has(name, MEDIUM) then
    return "medium"
  end
  local size = M.size_b(name)
  if size then
    return size <= 14 and "small" or (size <= 40 and "medium" or "strong")
  end
  if backend == "ollama" then
    return "small"
  end
  if backend == "claude" or name == "" then
    return "strong"
  end
  return "medium"
end

---@param backend string?
---@param model string?
---@return string
function M.key(backend, model)
  return (backend or "?") .. "/" .. (model or "default")
end

---@class AgentMeasured
---@field class AgentClass?
---@field repairs table<string, integer>?   per action
---@field declined table<string, string>?   per action: why

--- Per model: what the eval measured, as advice. Needs 3+ cases of an action to say anything about it
---@param groups AgentEvalGroup[] from agent/eval/report.aggregate
---@return table<string, AgentMeasured> by "backend/model"
function M.from_results(groups)
  local by = {}
  for _, g in ipairs(groups) do
    if not g.model:find "^replay" then
      local m = by[g.model] or { sum = 0, n = 0, repairs = {}, declined = {} }
      by[g.model] = m
      m.sum, m.n = m.sum + g.pass1 * g.n, m.n + g.n
      if g.cases >= 3 then
        if g.pass1 < 0.4 then
          m.declined[g.action] = ("passed %d%% of the %s cases (make eval)"):format(
            math.floor(g.pass1 * 100 + 0.5),
            g.action
          )
        elseif g.pass1 < 0.9 then
          m.repairs[g.action] = 2
        end
      end
    end
  end
  local out = {}
  for model, m in pairs(by) do
    local mean = m.n > 0 and m.sum / m.n or 0
    out[model] = {
      class = mean >= 0.85 and "strong" or (mean >= 0.5 and "medium" or "small"),
      repairs = m.repairs,
      declined = m.declined,
    }
  end
  return out
end

---@param sel { backend: string, model: string? }
---@param action string? the action's name (measured advice is per action)
---@param cfg table settings.agent.capability
---@param measured table<string, AgentMeasured>?
---@return AgentProfile
function M.resolve(sel, action, cfg, measured)
  local key = M.key(sel.backend, sel.model)
  local user = cfg.models and cfg.models[key]
  local m = cfg.measured ~= false and measured and measured[key] or nil
  local class = (type(user) == "string" and user)
    or (type(user) == "table" and user.class)
    or (m and m.class)
    or M.by_name(sel.backend, sel.model)
  local profile = vim.tbl_extend("force", { name = class }, M.DEFAULTS[class] or M.DEFAULTS.strong, cfg[class] or {})
  profile.name = class
  if m and action then
    profile.repairs = (m.repairs and m.repairs[action]) or profile.repairs
    profile.declined = m.declined and m.declined[action] or nil
  end
  if type(user) == "table" then
    for k, v in pairs(user) do
      if k ~= "class" then
        profile[k] = v
      end
    end
  end
  return profile
end

---@return string
function M.path()
  return vim.fn.stdpath "state" .. "/agent-profiles.json"
end

local loaded ---@type { mtime: integer, data: table }?

---@return table<string, AgentMeasured>
function M.load()
  local stat = vim.uv.fs_stat(M.path())
  if not stat then
    return {}
  end
  if loaded and loaded.mtime == stat.mtime.sec * 1e9 + stat.mtime.nsec then
    return loaded.data
  end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(M.path()), "\n"))
  data = ok and type(data) == "table" and data or {}
  loaded = { mtime = stat.mtime.sec * 1e9 + stat.mtime.nsec, data = data }
  return data
end

--- Keeps what an eval measured (merged over what was known: a model not in this run keeps its profile)
---@param measured table<string, AgentMeasured>
function M.save(measured)
  local all = vim.tbl_extend("force", M.load(), measured)
  vim.fn.mkdir(vim.fs.dirname(M.path()), "p")
  vim.fn.writefile(vim.split(vim.json.encode(all), "\n", { plain = true }), M.path())
end

return M
