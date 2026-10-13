-- ── Backend: Ollama (local models; CPU or GPU/CUDA, Ollama uses the GPU only if there is one) ────────────────────
-- Talks to Ollama's HTTP API (/api/chat, /api/tags) through curl, with streaming. What makes it really good locally:
--   automatic num_ctx    Ollama SILENTLY TRUNCATES whatever does not fit the window (2k-4k by default): sized per request
--   keep_alive           the model stays loaded between actions: the first one is slow, the next ones are not
--   low temperature      a small model follows the format (code block, `L<n>|sev|msg`) much better
-- Costs 0: no bill, which is why light actions (docs, explain) are the ideal candidates (`light_backend`).
local http = require "agent.backends.http"
local ndjson = require "agent.backends.ndjson"
local settings = require("core.settings").agent.ollama
local text = require "agent.text"

local M = {
  name = "ollama",
  label = "Ollama",
  default_model = settings.model,
  requires_model = true,
}

---@return string url base, without trailing slash
function M.host()
  if settings.host then
    return http.normalize(settings.host, 11434)
  end
  if vim.env.OLLAMA_HOST and vim.env.OLLAMA_HOST ~= "" then
    return http.normalize(vim.env.OLLAMA_HOST, 11434)
  end
  return M.saved() or "http://127.0.0.1:11434"
end

---@return string?
function M.saved()
  return http.saved "ollama"
end

--- Cheap (no network): there is a binary, or a server configured / detected by the setup. If the server does not answer,
--- the request fails with a message saying what to do; the menu is not blocked by asking it.
---@return boolean
function M.available()
  return vim.fn.executable "ollama" == 1
    or settings.host ~= nil
    or (vim.env.OLLAMA_HOST or "") ~= ""
    or M.saved() ~= nil
end

---@param cb fun(models: table[])
function M.models(cb)
  if settings.models then
    return cb(vim.tbl_map(function(id)
      return { id = id }
    end, settings.models))
  end
  vim.system(http.curl(M.host() .. "/api/tags", { max_time = 4 }), { text = true }, function(out)
    vim.schedule(function()
      local ok, data = pcall(vim.json.decode, out.stdout or "")
      local list = {}
      for _, m in ipairs(ok and type(data) == "table" and data.models or {}) do
        local d = m.details or {}
        local gb = m.size and ("%.1f GB"):format(m.size / 1e9) or nil
        local extra = vim.tbl_filter(function(x)
          return x
        end, { d.parameter_size, gb })
        list[#list + 1] =
          { id = m.name, label = m.name .. (#extra > 0 and ("  (" .. table.concat(extra, " · ") .. ")") or "") }
      end
      cb(list)
    end)
  end)
end

---@param req table
---@return table
function M.build(req)
  local body = {
    model = req.model,
    stream = true,
    keep_alive = settings.keep_alive,
    options = {
      num_ctx = http.context_size(#req.system + #req.prompt, settings),
      temperature = settings.temperature,
    },
    messages = {
      { role = "system", content = req.system },
      { role = "user", content = req.prompt },
    },
  }
  if settings.think ~= nil then
    body.think = settings.think
  end
  return {
    cmd = http.curl(M.host() .. "/api/chat", { stream = true, body = true }),
    stdin = vim.json.encode(body),
    cwd = require("agent.sandbox").dir(),
  }
end

---@return table
function M.parser()
  local chunks, final, err = {}, nil, nil
  local feed = ndjson.new(function(ev)
    if ev.error then
      err = type(ev.error) == "table" and (ev.error.message or vim.json.encode(ev.error)) or tostring(ev.error)
      return nil
    end
    local content = ev.message and ev.message.content
    if ev.done then
      final = ev
    end
    if content and content ~= "" then
      chunks[#chunks + 1] = content
      return content
    end
  end)

  return {
    feed = feed,
    finish = function(code, stderr)
      feed "\n" -- an error body without a trailing newline is read too
      if err then
        local hint = err:find("not found", 1, true) and " (pull it: `ollama pull <model>` or <leader>am → Setup)"
          or ""
        return { ok = false, err = err .. hint }
      end
      if #chunks == 0 then
        if code ~= 0 then
          return {
            ok = false,
            err = http.explain(code, stderr, M.host(), "start it with `ollama serve` or run <leader>am → Setup"),
          }
        end
        return { ok = false, err = "empty response" }
      end
      -- reasoning models (qwen3, deepseek-r1) may return their thinking between <think>...</think>
      local body = table.concat(chunks):gsub("<think>.-</think>%s*", "")
      local u = final or {}
      return {
        ok = true,
        text = text.trim(body),
        usage = {
          tokens_in = u.prompt_eval_count,
          tokens_out = u.eval_count,
          cost = 0,
          ms = u.total_duration and math.floor(u.total_duration / 1e6) or nil,
        },
      }
    end,
  }
end

return M
