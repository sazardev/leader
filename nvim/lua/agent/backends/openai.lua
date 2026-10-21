-- ── Backend: servers compatible with the OpenAI API ──────────────────────────────────────────────────────────────
-- LM Studio (1234), llama.cpp `llama-server` (8080), vLLM (8000), LiteLLM, OpenRouter, Ollama's /v1 mode... They all
-- speak /v1/chat/completions with SSE streaming. The key (if the service asks for one) is read from an environment variable and
-- does NOT travel in the process arguments (it would show up in `ps`).
local http = require "agent.backends.http"
local settings = require("core.settings").agent.openai
local text = require "agent.text"

local M = {
  name = "openai",
  label = "OpenAI-compatible",
  default_model = settings.model,
  requires_model = true,
}

---@return string? url up to /v1, without trailing slash
function M.base_url()
  local raw = settings.base_url or (vim.env.OPENAI_BASE_URL ~= "" and vim.env.OPENAI_BASE_URL) or http.saved "openai"
  if not raw then
    return nil
  end
  local url = http.normalize(raw, nil):gsub("/+$", "")
  return url:find "/v1$" and url or url .. "/v1"
end

---@return boolean
function M.available()
  return M.base_url() ~= nil
end

---@return string? key, or nil if there is none (local servers do not ask for one)
local function api_key()
  local name = settings.api_key_env
  local key = name and vim.env[name]
  return key and key ~= "" and key or nil
end

---@param url string
---@param opts table
---@return table cmd, table? env
local function request(url, opts)
  local key = api_key()
  if key and vim.fn.executable "sh" == 1 then
    local args = http.curl(url, opts)
    local cmd = { "sh", "-c", 'exec curl -H "Authorization: Bearer $AGENT_API_KEY" "$@"', "sh" }
    vim.list_extend(cmd, vim.list_slice(args, 2))
    return cmd, { AGENT_API_KEY = key }
  end
  if key then
    opts.headers = { "Authorization: Bearer " .. key }
  end
  return http.curl(url, opts), nil
end

---@param cb fun(models: table[])
function M.models(cb)
  if settings.models then
    return cb(vim.tbl_map(function(id)
      return { id = id }
    end, settings.models))
  end
  local base = M.base_url()
  if not base then
    return cb {}
  end
  local cmd, env = request(base .. "/models", { max_time = 4 })
  vim.system(cmd, { text = true, env = env }, function(out)
    vim.schedule(function()
      local ok, data = pcall(vim.json.decode, out.stdout or "")
      local list = {}
      for _, m in ipairs(ok and type(data) == "table" and data.data or {}) do
        list[#list + 1] = { id = m.id }
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
    stream_options = { include_usage = true },
    temperature = settings.temperature,
    messages = {
      { role = "system", content = req.system },
      { role = "user", content = req.prompt },
    },
  }
  local shaped = req.schema and require "agent.schema"
  if shaped then
    body.response_format = {
      type = "json_schema",
      json_schema = { name = "answer", strict = true, schema = shaped.json(req.schema) },
    }
    body.messages[1].content = req.system .. shaped.suffix(req.schema)
  end
  local cmd, env = request((M.base_url() or "") .. "/chat/completions", { stream = true, body = true })
  return {
    cmd = cmd,
    env = env,
    stdin = vim.json.encode(body),
    cwd = require("agent.sandbox").dir(),
    schema = shaped and req.schema or nil,
  }
end

---@return table
function M.parser()
  local chunks, usage, err, pending = {}, nil, nil, ""

  local function handle(line)
    local payload = line:match "^data:%s*(.*)$" or (line:find "^%s*{" and line or nil)
    if not payload or payload == "[DONE]" then
      return nil
    end
    local ok, ev = pcall(vim.json.decode, payload)
    if not (ok and type(ev) == "table") then
      return nil
    end
    if ev.error then
      err = type(ev.error) == "table" and (ev.error.message or vim.json.encode(ev.error)) or tostring(ev.error)
      return nil
    end
    if ev.usage and ev.usage ~= vim.NIL then
      usage = ev.usage
    end
    local delta = ev.choices and ev.choices[1] and ev.choices[1].delta
    local piece = delta and delta.content
    if piece and piece ~= vim.NIL and piece ~= "" then
      chunks[#chunks + 1] = piece
      return piece
    end
  end

  return {
    feed = function(chunk)
      pending = pending .. chunk
      local out = {}
      while true do
        local nl = pending:find("\n", 1, true)
        if not nl then
          break
        end
        local piece = handle(pending:sub(1, nl - 1))
        pending = pending:sub(nl + 1)
        if piece then
          out[#out + 1] = piece
        end
      end
      return #out > 0 and table.concat(out) or nil
    end,
    finish = function(code, stderr)
      if pending ~= "" then
        handle(pending)
      end
      if err then
        return { ok = false, err = err }
      end
      if #chunks == 0 then
        if code ~= 0 then
          return {
            ok = false,
            err = http.explain(
              code,
              stderr,
              M.base_url() or "the server",
              "check `settings.agent.openai.base_url` or run <leader>am → Setup"
            ),
          }
        end
        return { ok = false, err = "empty response" }
      end
      local body = table.concat(chunks):gsub("<think>.-</think>%s*", "")
      return {
        ok = true,
        text = text.trim(body),
        usage = usage and { tokens_in = usage.prompt_tokens, tokens_out = usage.completion_tokens, cost = 0 } or nil,
      }
    end,
  }
end

return M
