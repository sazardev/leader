-- ── Capa HTTP compartida por los backends locales (Ollama, OpenAI-compatible) ─────
-- Habla con curl (viene con todos los sistemas): sin dependencias, con streaming y con el mismo `vim.system` que usan los
-- demás backends. Resuelve DÓNDE está el servidor (ajuste > variable de entorno > lo que el setup detectó > lo habitual),
-- incluido el caso de WSL con el servidor en el host de Windows, y convierte los errores de curl en mensajes que dicen
-- qué hacer.
local state = require "agent.state"

local M = {}

--- Normaliza "host:port", "0.0.0.0:11434" o "http://x" a una URL base sin barra final
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

--- Servidor guardado por el setup (stdpath state) para un tipo ("ollama" | "openai")
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

--- Candidatos donde puede estar un servidor local, en orden. En WSL2 el servidor suele vivir en Windows: su IP es la
--- puerta de enlace por defecto o el nameserver de /etc/resolv.conf (según el modo de red).
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

--- Argumentos de curl para una petición JSON con streaming; el cuerpo va por stdin
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

--- Mensaje útil a partir de un fallo de curl
---@param code integer
---@param stderr string?
---@param url string
---@param hint string  qué hacer si no responde
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

--- Tokens aproximados de un texto (para dimensionar el contexto de un modelo local)
---@param chars integer
---@return integer
function M.approx_tokens(chars)
  return math.ceil(chars / 3.2) -- el código tokeniza peor que la prosa: se redondea hacia arriba
end

--- Ventana de contexto para esta petición: lo que ocupa el prompt + margen para la respuesta, redondeado a una potencia de
--- dos entre 4096 y `max_ctx`. Ollama TRUNCA en silencio lo que no cabe en `num_ctx` (por defecto, 2k-4k): sin esto un
--- prompt con contexto de verdad perdería justo el principio (las reglas) sin avisar.
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

return M
