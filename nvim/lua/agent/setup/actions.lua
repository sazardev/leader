-- ── Setup actions: start, download, save, apply ──────────────────────────────
-- The only thing that MODIFIES anything. Each function is explicit (the caller already asked for confirmation or passed the flag): start
-- `ollama serve`, download a model through the Ollama API (works the same for a remote server), remember the servers
-- found and set backend/model per tier.
local backends = require "agent.backends"
local http = require "agent.backends.http"
local ndjson = require "agent.backends.ndjson"
local selection = require "agent.selection"

local M = {}

---@param url string
---@param cb fun(ok: boolean)
local function ping(url, cb)
  vim.system(http.curl(url .. "/api/version", { max_time = 2, connect_timeout = 1 }), { text = true }, function(out)
    vim.schedule(function()
      cb(out.code == 0 and (out.stdout or ""):find("version", 1, true) ~= nil)
    end)
  end)
end

--- Starts `ollama serve` in the background (survives nvim) and waits for it to respond
---@param url string  where it must respond (the backend's host)
---@param cb fun(ok: boolean, err: string?)
---@param timeout_s integer?
function M.start_ollama(url, cb, timeout_s)
  ping(url, function(up)
    if up then
      return cb(true)
    end
    if vim.fn.executable "ollama" ~= 1 then
      return cb(
        false,
        "`ollama` is not installed (https://ollama.com/download, or run the Docker image shown in the report)"
      )
    end
    local ok, err = pcall(vim.system, { "ollama", "serve" }, { detach = true, stdout = false, stderr = false })
    if not ok then
      return cb(false, "could not start `ollama serve`: " .. tostring(err))
    end
    local deadline = vim.uv.hrtime() + (timeout_s or 20) * 1e9
    local function poll()
      ping(url, function(ready)
        if ready then
          cb(true)
        elseif vim.uv.hrtime() > deadline then
          cb(false, ("`ollama serve` started but %s did not answer in time"):format(url))
        else
          vim.defer_fn(poll, 500)
        end
      end)
    end
    poll()
  end)
end

--- Downloads a model with /api/pull (streaming) and reports progress
---@param url string
---@param model string
---@param on_progress fun(status: string, pct: integer?)
---@param cb fun(ok: boolean, err: string?)
function M.pull(url, model, on_progress, cb)
  local failed
  local feed = ndjson.new(function(ev)
    if ev.error then
      failed = type(ev.error) == "table" and (ev.error.message or vim.json.encode(ev.error)) or tostring(ev.error)
      return nil
    end
    local pct = ev.total and ev.total > 0 and math.floor((ev.completed or 0) / ev.total * 100) or nil
    vim.schedule(function()
      on_progress(ev.status or "", pct)
    end)
  end)
  vim.system(http.curl(url .. "/api/pull", { stream = true, body = true }), {
    text = true,
    stdin = vim.json.encode { model = model, name = model, stream = true },
    stdout = function(_, chunk)
      if chunk then
        feed(chunk)
      end
    end,
  }, function(out)
    vim.schedule(function()
      if failed then
        cb(false, failed)
      elseif out.code ~= 0 then
        cb(false, http.explain(out.code, out.stderr, url, "start it with `ollama serve`"))
      else
        cb(true)
      end
    end)
  end)
end

---@return boolean
local function ollama_pinned()
  return require("core.settings").agent.ollama.host ~= nil or (vim.env.OLLAMA_HOST or "") ~= ""
end

--- Remembers the servers found (the backend uses them if nothing is configured or in the environment)
---@param snap AgentSnapshot
---@return string[] what was saved
function M.remember(snap)
  local saved = {}
  local o = snap.ollama_servers[1]
  if o and not ollama_pinned() then
    http.save("ollama", o.url)
    saved[#saved + 1] = "ollama → " .. o.url
  end
  local a = snap.openai_servers[1]
  if a then
    http.save("openai", a.url .. "/v1")
    saved[#saved + 1] = "openai → " .. a.url .. "/v1"
  end
  return saved
end

--- Sets backend and model per tier; returns what was applied so it can be shown
---@param rec AgentRecommendation
---@return string[]
function M.apply(rec)
  local applied = {}
  if rec.main then
    selection.set(rec.main.backend, rec.main.model, "main")
    applied[#applied + 1] = ("main  → %s/%s"):format(rec.main.backend, rec.main.model)
  end
  if rec.light then
    selection.set(rec.light.backend, rec.light.model, "light")
    applied[#applied + 1] = ("light → %s/%s"):format(rec.light.backend, rec.light.model)
  end
  return applied
end

--- "backend/model" → backend, model (the model may contain "/" and ":")
---@param spec string
---@return string? backend, string? model
function M.parse_spec(spec)
  local backend, model = spec:match "^([^/]+)/(.+)$"
  if not backend then
    return nil, nil
  end
  if not vim.tbl_contains(backends.names(), backend) then
    return nil, nil
  end
  return backend, model
end

return M
