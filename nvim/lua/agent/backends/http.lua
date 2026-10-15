-- ── HTTP layer shared by the local backends (Ollama, OpenAI-compatible) ───────────
-- Talks through curl (ships with every system): no dependencies, with streaming and the same `vim.system` the other
-- backends use. Resolves WHERE the server is (setting > environment variable > what the setup detected > the usual),
-- including WSL with the server on the Windows host, and turns curl errors into messages that say
-- what to do.
local state = require "agent.state"

local M = {}

--- Normalizes "host:port", "0.0.0.0:11434" or "http://x" to a base URL without trailing slash
---@param raw string
---@param default_port integer
---@return string
function M.normalize(raw, default_port)
  local url = vim.trim(raw)
  if not url:find "^https?://" then
    url = "http://" .. url
  end
  url = url:gsub("/+$", "")
  local host = url:match "^https?://([^/:]+)"
  if host == "0.0.0.0" then
    url = url:gsub("0%.0%.0%.0", "127.0.0.1", 1)
  end
  if not url:match "^https?://[^/]+:%d+" and default_port then
    url = url:gsub("^(https?://[^/]+)", "%1:" .. default_port, 1)
  end
  return url
end

--- Server saved by the setup (stdpath state) for a kind ("ollama" | "openai")
---@param kind string
---@return string?
function M.saved(kind)
  return (state.get "endpoints" or {})[kind]
end

---@param kind string
---@param url string?
function M.save(kind, url)
  local all = state.get "endpoints" or {}
  all[kind] = url
  state.set("endpoints", all)
end

--- Candidates where a local server may be, in order. On WSL2 the server usually lives on Windows: its IP is the
--- default gateway or the nameserver in /etc/resolv.conf (depending on the network mode).
---@param port integer
---@return string[]
function M.candidates(port)
  local out, seen = {}, {}
  local function add(host)
    if host and host ~= "" and not seen[host] then
      seen[host] = true
      out[#out + 1] = ("http://%s:%d"):format(host, port)
    end
  end
  add "127.0.0.1"
  add "host.docker.internal"
  local resolv = io.open("/etc/resolv.conf", "r")
  if resolv then
    for line in resolv:lines() do
      add(line:match "^nameserver%s+(%d+%.%d+%.%d+%.%d+)")
    end
    resolv:close()
  end
  local route = vim.fn.executable "ip" == 1 and vim.fn.system { "ip", "route" } or ""
  add(route:match "default via (%d+%.%d+%.%d+%.%d+)")
  return out
end

--- curl arguments for a streaming JSON request; the body goes through stdin
---@param url string
---@param opts { method: string?, headers: string[]?, stream: boolean?, max_time: integer?, connect_timeout: integer?, body: boolean? }?
---@return string[]
function M.curl(url, opts)
  opts = opts or {}
  local cmd = { "curl", "-sS" }
  if opts.stream then
    vim.list_extend(cmd, { "-N", "--no-buffer" })
  end
  vim.list_extend(cmd, { "-X", opts.method or (opts.body and "POST" or "GET") })
  if opts.max_time then
    vim.list_extend(cmd, { "--max-time", tostring(opts.max_time) })
  end
  if opts.connect_timeout then
    vim.list_extend(cmd, { "--connect-timeout", tostring(opts.connect_timeout) })
  end
  for _, h in ipairs(opts.headers or {}) do
    vim.list_extend(cmd, { "-H", h })
  end
  if opts.body then
    vim.list_extend(cmd, { "-H", "Content-Type: application/json", "--data-binary", "@-" })
  end
  cmd[#cmd + 1] = url
  return cmd
end

--- Useful message from a curl failure
---@param code integer
---@param stderr string?
---@param url string
---@param hint string  what to do if it does not answer
---@return string
function M.explain(code, stderr, url, hint)
  if code == 7 then
    return ("cannot connect to %s: %s"):format(url, hint)
  elseif code == 6 then
    return ("cannot resolve the host of %s"):format(url)
  elseif code == 28 then
    return ("%s did not answer in time (is the model still loading?)"):format(url)
  elseif code == 22 or code == 56 then
    return ("%s rejected the request: %s"):format(url, vim.trim(stderr or ""))
  end
  local msg = vim.trim(stderr or "")
  return msg ~= "" and msg or ("curl exited with code %d"):format(code)
end

--- Approximate tokens of a text (to size a local model's context)
---@param chars integer
---@return integer
function M.approx_tokens(chars)
  return math.ceil(chars / 3.2) -- code tokenizes worse than prose: rounded up
end

--- Context window for this request: what the prompt takes + room for the answer, rounded to a power of
--- two between 4096 and `max_ctx`. Ollama SILENTLY TRUNCATES whatever does not fit `num_ctx` (default 2k-4k): without this a
--- prompt with real context would lose exactly its beginning (the rules) without warning.
---@param prompt_chars integer
---@param opts { num_ctx: integer?, max_ctx: integer? }
---@return integer
function M.context_size(prompt_chars, opts)
  if opts.num_ctx then
    return opts.num_ctx
  end
  local needed = M.approx_tokens(prompt_chars) + 2048
  local size = 4096
  while size < needed and size < (opts.max_ctx or 32768) do
    size = size * 2
  end
  return math.min(size, opts.max_ctx or 32768)
end

---@type table<string, integer>
local widest = {}

--- A window that never shrinks while the model stays loaded. Ollama reloads the model (and drops its KV cache, which is
--- what makes the second call on the same code fast) whenever `num_ctx` changes: a small action after a big one must keep
--- the big one's window.
---@param model string
---@param size integer
---@return integer
function M.sticky(model, size)
  widest[model] = math.max(widest[model] or 0, size)
  return widest[model]
end

--- Forgets the windows (tests, or the server was restarted)
function M.unstick()
  widest = {}
end

return M
