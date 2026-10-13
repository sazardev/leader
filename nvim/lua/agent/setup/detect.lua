-- ── Detección: qué hay en esta máquina para el agente ────────────────────────
-- Una foto (snapshot) de TODO lo que el agente puede usar, medida en paralelo y sin bloquear nvim: CLIs de agente, servidores
-- locales (Ollama y APIs compatibles con OpenAI, también los que viven en el host de Windows si estás en WSL), los modelos
-- que ya tienes, si cargan en GPU o CPU y cuánta VRAM/RAM hay para recomendar. No instala ni arranca nada: solo mira.
local http = require "agent.backends.http"
local settings = require("core.settings").agent

local M = {}

--- CLIs de agente que se buscan: ejecutable → para qué sirven
M.CLIS = {
  { name = "claude", role = "backend: Claude Code" },
  { name = "opencode", role = "backend: OpenCode" },
  { name = "ollama", role = "local models (CPU / CUDA)" },
  { name = "lms", role = "LM Studio CLI (serves an OpenAI-compatible API)" },
  { name = "llama-server", role = "llama.cpp server (OpenAI-compatible API)" },
  { name = "hermes", role = "Hermes Agent (use it via `settings.agent.custom`)" },
  { name = "gemini", role = "Gemini CLI (use it via `settings.agent.custom`)" },
  { name = "codex", role = "Codex CLI (use it via `settings.agent.custom`)" },
  { name = "aider", role = "Aider (use it via `settings.agent.custom`)" },
}

local OPENAI_PORTS = { 1234, 8080, 8000 } -- LM Studio, llama.cpp server, vLLM

---@param cmd string[]
---@param cb fun(out: vim.SystemCompleted)
local function run(cmd, cb)
  local ok = pcall(vim.system, cmd, { text = true, timeout = 4000 }, function(out)
    vim.schedule(function()
      cb(out)
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb { code = 127, stdout = "", stderr = "" }
    end)
  end
end

---@param url string
---@param cb fun(data: table?)
local function get_json(url, cb)
  run(http.curl(url, { max_time = 2, connect_timeout = 1 }), function(out)
    local ok, data = pcall(vim.json.decode, out.stdout or "")
    cb(out.code == 0 and ok and type(data) == "table" and data or nil)
  end)
end

--- RAM total en GB (Linux/WSL); nil si no se puede leer
---@return number?
local function ram_gb()
  local f = io.open("/proc/meminfo", "r")
  if not f then
    return nil
  end
  local kb = f:read("*a"):match "MemTotal:%s+(%d+)"
  f:close()
  return kb and math.floor(tonumber(kb) / 1048576 * 10) / 10 or nil
end

---@return string?
local function nvidia_smi()
  for _, bin in ipairs { "nvidia-smi", "/usr/lib/wsl/lib/nvidia-smi" } do
    if vim.fn.executable(bin) == 1 then
      return bin
    end
  end
end

--- Servidores donde mirar, sin repetir: lo configurado / el entorno / lo guardado primero
---@return string[]
local function ollama_urls()
  local out, seen = {}, {}
  local function add(url)
    if url and not seen[url] then
      seen[url] = true
      out[#out + 1] = url
    end
  end
  if settings.ollama.host then
    add(http.normalize(settings.ollama.host, 11434))
  end
  if (vim.env.OLLAMA_HOST or "") ~= "" then
    add(http.normalize(vim.env.OLLAMA_HOST, 11434))
  end
  add(http.saved "ollama")
  for _, url in ipairs(http.candidates(11434)) do
    add(url)
  end
  return out
end

---@return string[]
local function openai_urls()
  local out, seen = {}, {}
  local function add(url)
    if url and not seen[url] then
      seen[url] = true
      out[#out + 1] = url
    end
  end
  if settings.openai.base_url then
    add((http.normalize(settings.openai.base_url, nil):gsub("/v1$", "")))
  end
  if (vim.env.OPENAI_BASE_URL or "") ~= "" then
    add((http.normalize(vim.env.OPENAI_BASE_URL, nil):gsub("/v1$", "")))
  end
  local saved = http.saved "openai"
  if saved then
    add((saved:gsub("/v1$", "")))
  end
  for _, port in ipairs(OPENAI_PORTS) do
    for _, url in ipairs(http.candidates(port)) do
      add(url)
    end
  end
  return out
end

---@class AgentSnapshot
---@field clis { name: string, role: string, path: string?, version: string? }[]
---@field ollama_servers { url: string, version: string?, models: table[], loaded: table[] }[]
---@field openai_servers { url: string, models: string[] }[]
---@field gpu { name: string, vram_gb: number }?
---@field ram_gb number?
---@field docker boolean
---@field custom string[]
---@field warnings string[]

--- Mide todo en paralelo y entrega la foto
---@param cb fun(snapshot: AgentSnapshot)
function M.run(cb)
  local snap = {
    clis = {},
    ollama_servers = {},
    openai_servers = {},
    ram_gb = ram_gb(),
    docker = vim.fn.executable "docker" == 1,
    custom = vim.tbl_keys(settings.custom or {}),
    warnings = {},
  }
  table.sort(snap.custom)
  if vim.fn.executable "curl" ~= 1 then
    snap.warnings[#snap.warnings + 1] = "`curl` is not installed: Ollama and OpenAI-compatible backends need it"
  end

  local pending, done = 0, false
  local function start()
    pending = pending + 1
  end
  local function finish()
    pending = pending - 1
    if pending == 0 and not done then
      done = true
      table.sort(snap.ollama_servers, function(a, b)
        return a.url < b.url
      end)
      table.sort(snap.openai_servers, function(a, b)
        return a.url < b.url
      end)
      cb(snap)
    end
  end

  start() -- guarda de arranque: el callback final no se dispara antes de lanzar todas las sondas
  -- CLIs: ejecutable + versión
  for i, cli in ipairs(M.CLIS) do
    local path = vim.fn.exepath(cli.name)
    snap.clis[i] = { name = cli.name, role = cli.role, path = path ~= "" and path or nil }
    if path ~= "" then
      start()
      run({ path, "--version" }, function(out)
        snap.clis[i].version = (out.stdout or ""):match "(%d+%.%d+[%w%.%-]*)"
        finish()
      end)
    end
  end

  -- Ollama: versión, modelos instalados y cuáles están cargados (y dónde: GPU o CPU)
  for _, url in ipairs(ollama_urls()) do
    start()
    get_json(url .. "/api/version", function(ver)
      if not ver or not ver.version then
        return finish()
      end
      local server = { url = url, version = ver.version, models = {}, loaded = {} }
      snap.ollama_servers[#snap.ollama_servers + 1] = server
      pending = pending + 2
      get_json(url .. "/api/tags", function(tags)
        for _, m in ipairs(tags and tags.models or {}) do
          local d = m.details or {}
          server.models[#server.models + 1] = {
            name = m.name,
            size = m.size,
            params = d.parameter_size,
            quant = d.quantization_level,
          }
        end
        finish()
      end)
      get_json(url .. "/api/ps", function(ps)
        for _, m in ipairs(ps and ps.models or {}) do
          server.loaded[#server.loaded + 1] = { name = m.name, size = m.size, vram = m.size_vram }
        end
        finish()
      end)
      finish()
    end)
  end

  -- APIs compatibles con OpenAI (LM Studio, llama.cpp, vLLM...)
  for _, url in ipairs(openai_urls()) do
    start()
    get_json(url .. "/v1/models", function(models)
      local is_ollama = false
      for _, s in ipairs(snap.ollama_servers) do
        is_ollama = is_ollama or s.url == url
      end
      if models and type(models.data) == "table" and not is_ollama then
        local ids = {}
        for _, m in ipairs(models.data) do
          ids[#ids + 1] = m.id
        end
        snap.openai_servers[#snap.openai_servers + 1] = { url = url, models = ids }
      end
      finish()
    end)
  end

  -- GPU
  local smi = nvidia_smi()
  if smi then
    start()
    run({ smi, "--query-gpu=name,memory.total", "--format=csv,noheader,nounits" }, function(out)
      local name, mb = (out.stdout or ""):match "^([^,\n]+),%s*(%d+)"
      if out.code == 0 and name then
        snap.gpu = { name = vim.trim(name), vram_gb = math.floor(tonumber(mb) / 1024 * 10) / 10 }
      end
      finish()
    end)
  end

  finish() -- libera la guarda
end

return M
