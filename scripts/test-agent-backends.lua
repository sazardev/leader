-- Pruebas de los backends locales (Ollama, OpenAI-compatible, comandos) y del setup. Se ejecutan con
-- scripts/test-agent.sh, tras test-agent.lua (archivo aparte: el otro agotó el límite de 200 locales de Lua).
local fails = 0
local function print(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), "\t"), "\n")
end
local function eq(name, got, want)
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. "\n  got:  " .. vim.inspect(got) .. "\n  want: " .. vim.inspect(want))
  end
end
local protocol = require "agent.protocol"
local real_selection = package.loaded["agent.selection"]

-- ── Backends locales y setup ─────────────────────────────────────────────────
-- Hermético: el estado (agent.json) se sustituye EN SITIO por uno en memoria y los servidores son falsos
-- (scripts/fake-llm.py habla Ollama y la API de OpenAI). Nada toca tu estado real ni la red.
do
  local agent_state = require "agent.state"
  local real_get, real_set = agent_state.get, agent_state.set
  local fake_store = {}
  agent_state.get = function(key)
    return fake_store[key]
  end
  agent_state.set = function(key, value)
    fake_store[key] = value
  end

  local http = require "agent.backends.http"
  eq("http: contexto mínimo 4096", http.context_size(100, {}), 4096)
  eq("http: el contexto crece con el prompt (potencia de dos)", http.context_size(40000, {}), 16384)
  eq("http: el contexto respeta el tope", http.context_size(900000, { max_ctx = 32768 }), 32768)
  eq("http: num_ctx fijo manda", http.context_size(900000, { num_ctx = 8192 }), 8192)
  eq(
    "http: normalize",
    { http.normalize("0.0.0.0:11434", 11434), http.normalize("localhost", 11434), http.normalize("http://x:1/", 11434) },
    { "http://127.0.0.1:11434", "http://localhost:11434", "http://x:1" }
  )
  eq(
    "http: curl con cuerpo por stdin y streaming",
    http.curl("http://h/x", { stream = true, body = true, connect_timeout = 1 }),
    {
      "curl",
      "-sS",
      "-N",
      "--no-buffer",
      "-X",
      "POST",
      "--connect-timeout",
      "1",
      "-H",
      "Content-Type: application/json",
      "--data-binary",
      "@-",
      "http://h/x",
    }
  )
  eq(
    "http: curl 7 explica qué hacer",
    http.explain(7, "", "http://h", "start it"):find("start it", 1, true) ~= nil,
    true
  )

  -- Ollama: construcción y lectura (sin servidor)
  local ollama = require "agent.backends.ollama"
  local ob = ollama.build { system = "SYS", prompt = "PROMPT", model = "m:7b", action = "docs" }
  local obody = vim.json.decode(ob.stdin)
  eq("ollama: cuerpo (modelo, streaming, contexto automático, keep_alive)", {
    obody.model,
    obody.stream,
    obody.options.num_ctx,
    obody.keep_alive,
    obody.messages[1].role,
    obody.messages[2].content,
  }, { "m:7b", true, 4096, require("core.settings").agent.ollama.keep_alive, "system", "PROMPT" })
  eq("ollama: curl al endpoint de chat", vim.endswith(ob.cmd[#ob.cmd], "/api/chat"), true)
  local op = ollama.parser()
  local streamed =
    op.feed '{"message":{"content":"<think>hm</think>He"},"done":false}\n{"message":{"content":"llo"},"done":false}\n'
  local ofin = op.feed '{"done":true,"prompt_eval_count":12,"eval_count":3,"total_duration":2000000000}\n'
  local ores = op.finish(0, "")
  eq(
    "ollama: texto en streaming, sin <think>, con uso y coste 0",
    { streamed, ofin, ores.ok, ores.text, ores.usage.tokens_in, ores.usage.tokens_out, ores.usage.cost, ores.usage.ms },
    { "<think>hm</think>Hello", nil, true, "Hello", 12, 3, 0, 2000 }
  )
  local oe = ollama.parser()
  oe.feed '{"error":"model \\"x\\" not found, try pulling it first"}\n'
  eq("ollama: modelo ausente sugiere descargarlo", oe.finish(0, "").err:find("pull", 1, true) ~= nil, true)
  eq(
    "ollama: servidor caído → qué hacer",
    ollama.parser().finish(7, "").err:find("ollama serve", 1, true) ~= nil,
    true
  )

  -- OpenAI-compatible: construcción y lectura
  local openai = require "agent.backends.openai"
  local oai = require("core.settings").agent.openai
  oai.base_url = "http://127.0.0.1:1234"
  eq("openai: base_url acaba en /v1", openai.base_url(), "http://127.0.0.1:1234/v1")
  local oab = openai.build { system = "S", prompt = "P", model = "gguf", action = "docs" }
  eq("openai: endpoint y cuerpo", { oab.cmd[#oab.cmd], vim.json.decode(oab.stdin).stream_options.include_usage }, {
    "http://127.0.0.1:1234/v1/chat/completions",
    true,
  })
  local oap = openai.parser()
  oap.feed 'data: {"choices":[{"delta":{"content":"Hi "}}]}\n\ndata: {"choices":[{"delta":{"content":"there"}}]}\n\n'
  oap.feed 'data: {"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":2}}\n\ndata: [DONE]\n'
  local oar = oap.finish(0, "")
  eq("openai: SSE → texto y uso", { oar.text, oar.usage.tokens_in, oar.usage.tokens_out }, { "Hi there", 7, 2 })
  oai.base_url = nil

  -- backend declarativo (Hermes Agent, Gemini CLI...)
  local command = require "agent.backends.command"
  local hermes = command.from_spec("hermes", {
    label = "Hermes Agent",
    cmd = { "hermes", "chat", "-q", "{prompt}" },
    model_flag = { "-m", "{model}" },
    models = { "hermes3" },
  })
  local hb = hermes.build { system = "SYS", prompt = "PROMPT", model = "hermes3", action = "explain" }
  eq(
    "command: {prompt} y bandera de modelo; el system va dentro del mensaje",
    { hb.cmd[1], hb.cmd[4]:find("SYS", 1, true) ~= nil, hb.cmd[4]:find("PROMPT", 1, true) ~= nil, hb.cmd[5], hb.cmd[6] },
    { "hermes", true, true, "-m", "hermes3" }
  )
  eq("command: sin el ejecutable no está disponible", hermes.available(), false)
  local jsonb = command.from_spec("j", { cmd = { "x" }, json = "msg.text" })
  local jp = jsonb.parser()
  jp.feed '{"msg":{"text":"alpha "}}\n{"msg":{"text":"beta"}}\n{"other":1}\n'
  eq("command: texto por ruta JSON", jp.finish(0, "").text, "alpha beta")
  eq("command: error de proceso", command.from_spec("z", { cmd = { "x" } }).parser().finish(3, "boom").err, "boom")
  local registered = require "agent.backends"
  registered.register("hermes", hermes)
  eq("registro: un backend en caliente aparece en names()", vim.tbl_contains(registered.names(), "hermes"), true)

  -- recomendación y estado (puros)
  local recommend = require "agent.setup.recommend"
  local report = require "agent.setup.report"
  local function snap(extra)
    return vim.tbl_extend("force", {
      clis = {},
      ollama_servers = {},
      openai_servers = {},
      custom = {},
      warnings = {},
      docker = false,
    }, extra or {})
  end
  local cloud = { { name = "claude", path = "/bin/claude" } }
  eq(
    "recommend: 24 GB de VRAM → 32b principal",
    recommend.tier(snap { gpu = { name = "g", vram_gb = 24 } }).main,
    "qwen2.5-coder:32b"
  )
  eq(
    "recommend: 8 GB de VRAM → 7b",
    recommend.tier(snap { gpu = { name = "g", vram_gb = 8 } }).main,
    "qwen2.5-coder:7b"
  )
  eq("recommend: CPU con 32 GB de RAM → tope de 8 GB útiles", recommend.budget_gb(snap { ram_gb = 32 }), 8)
  eq("recommend: CPU con 4 GB de RAM → 3b", recommend.tier(snap { ram_gb = 4 }).main, "qwen2.5-coder:3b")
  local nothing = recommend.pick(snap { clis = cloud, gpu = { name = "g", vram_gb = 12 } })
  eq(
    "recommend: sin modelos y con Claude → solo se sugiere el ligero",
    { nothing.main, nothing.light, vim.tbl_map(function(p)
      return p.model
    end, nothing.pulls) },
    { nil, nil, { "qwen2.5-coder:3b" } }
  )
  local only_local = recommend.pick(snap { gpu = { name = "g", vram_gb = 12 } })
  eq(
    "recommend: sin CLI de nube se sugieren ligero y principal",
    vim.tbl_map(function(p)
      return p.model
    end, only_local.pulls),
    { "qwen2.5-coder:3b", "qwen2.5-coder:14b" }
  )
  local models = {
    { name = "llama3:8b", params = "8B" },
    { name = "qwen2.5-coder:7b", params = "7.6B" },
    { name = "qwen2.5-coder:1.5b", params = "1.5B" },
    { name = "nomic-embed-text", params = "137M" },
  }
  local with_models =
    recommend.pick(snap { clis = cloud, ollama_servers = { { url = "u", models = models, loaded = {} } } })
  eq(
    "recommend: con modelos instalados → el de código más pequeño para el ligero; el principal sigue en la nube",
    { with_models.main, with_models.light, #with_models.pulls },
    { nil, { backend = "ollama", model = "qwen2.5-coder:1.5b" }, 0 }
  )
  local local_only = recommend.pick(snap { ollama_servers = { { url = "u", models = models, loaded = {} } } })
  eq(
    "recommend: sin nube el local es también el principal (el mayor de código)",
    { local_only.main.model, local_only.light.model },
    { "qwen2.5-coder:7b", "qwen2.5-coder:1.5b" }
  )
  eq("report: sin nada listo → no ready", report.ready(snap {}), false)
  eq(
    "report: con un servidor con modelos → ready",
    report.ready(snap { ollama_servers = { { url = "u", models = models, loaded = {} } } }),
    true
  )
  eq("report: un backend custom cuenta como listo", report.ready(snap { custom = { "hermes" } }), true)
  local text_report = table.concat(report.build(snap { docker = true }, recommend.pick(snap {}), nil), "\n")
  eq(
    "report: sin servidor explica cómo conseguir Ollama (incluido Docker con GPU)",
    { text_report:find("ollama.com/download", 1, true) ~= nil, text_report:find("--gpus all", 1, true) ~= nil },
    { true, true }
  )

  -- servidores falsos reales: Ollama + OpenAI-compatible
  local have_python = vim.fn.executable "python3" == 1
  if not have_python then
    print "skip servidores falsos (sin python3)"
  else
    local fake_ollama =
      vim.system { "python3", "-I", (vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()) .. "/scripts/fake-llm.py", "18434" }
    local fake_openai =
      vim.system { "python3", "-I", (vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()) .. "/scripts/fake-llm.py", "18435" }
    local function wait_up(port)
      return vim.wait(4000, function()
        return vim.system({ "curl", "-s", "--max-time", "1", ("127.0.0.1:%d/api/version"):format(port) }):wait().code
          == 0
      end, 150)
    end
    eq("servidores falsos arrancan", { wait_up(18434), wait_up(18435) }, { true, true })

    local cfg = require("core.settings").agent
    local prev_host, prev_base = cfg.ollama.host, cfg.openai.base_url
    cfg.ollama.host, cfg.openai.base_url = "127.0.0.1:18434", "http://127.0.0.1:18435/v1"

    --- Ejecuta una petición completa de un backend (como el runner) y devuelve su resultado
    local function roundtrip(backend, req)
      local spec = backend.build(req)
      local parser = backend.parser()
      local out = vim
        .system(spec.cmd, {
          text = true,
          stdin = spec.stdin,
          env = spec.env,
          cwd = spec.cwd,
          stdout = function(_, chunk)
            if chunk then
              parser.feed(chunk)
            end
          end,
        })
        :wait()
      return parser.finish(out.code, out.stderr or ""), spec
    end
    local last_request = function(port)
      return vim.json.decode(
        vim.system({ "curl", "-s", ("127.0.0.1:%d/__last"):format(port) }, { text = true }):wait().stdout
      )
    end

    -- modelos
    local listed
    ollama.models(function(list)
      listed = list
    end)
    vim.wait(3000, function()
      return listed ~= nil
    end)
    eq(
      "ollama: lista los modelos del servidor (con tamaño)",
      { #listed, listed[1].id, listed[1].label:find("7.6B", 1, true) ~= nil },
      { 3, "qwen2.5-coder:7b", true }
    )
    local oai_listed
    openai.models(function(list)
      oai_listed = list
    end)
    vim.wait(3000, function()
      return oai_listed ~= nil
    end)
    eq(
      "openai: lista /v1/models",
      vim.tbl_map(function(m)
        return m.id
      end, oai_listed),
      { "fake-gguf", "fake-small" }
    )

    -- una acción completa de extremo a extremo
    local code_req = { system = "x", prompt = "implement this", model = "qwen2.5-coder:7b", action = "implement" }
    local res = roundtrip(ollama, code_req)
    eq(
      "ollama e2e: respuesta, uso y coste 0",
      { res.ok, res.usage.tokens_in, res.usage.tokens_out, res.usage.cost },
      { true, 321, 45, 0 }
    )
    eq(
      "ollama e2e: el protocolo extrae el bloque de código",
      (protocol.extract_code(res.text)),
      { "func Add(a, b int) int {", "\treturn a + b", "}" }
    )
    local seen = last_request(18434)
    eq(
      "ollama e2e: el servidor recibió modelo y num_ctx",
      { seen.body.model, seen.body.options.num_ctx },
      { "qwen2.5-coder:7b", 4096 }
    )
    local review =
      roundtrip(ollama, { system = "OUTPUT, one finding per line", prompt = "p", model = "m", action = "review" })
    eq("ollama e2e: los hallazgos se leen con el protocolo", #protocol.parse_findings(review.text), 2)
    local missing = roundtrip(ollama, { system = "s", prompt = "p", model = "missing", action = "docs" })
    eq(
      "ollama e2e: modelo inexistente → error con la pista de descargarlo",
      { missing.ok, missing.err:find("not found", 1, true) ~= nil, missing.err:find("pull", 1, true) ~= nil },
      { false, true, true }
    )
    local long_prompt = ("x"):rep(30000)
    roundtrip(ollama, { system = "s", prompt = long_prompt, model = "m", action = "docs" })
    eq(
      "ollama e2e: un prompt largo amplía num_ctx (no se trunca en silencio)",
      last_request(18434).body.options.num_ctx,
      16384
    )

    vim.env.TEST_AGENT_KEY = "secret-key"
    cfg.openai.api_key_env = "TEST_AGENT_KEY"
    local ores2, ospec2 =
      roundtrip(openai, { system = "x", prompt = "implement this", model = "fake-gguf", action = "implement" })
    eq("openai e2e: texto y uso", { ores2.ok, ores2.usage.tokens_in, ores2.usage.tokens_out }, { true, 210, 33 })
    eq("openai e2e: la clave viaja como Authorization", last_request(18435).authorization, "Bearer secret-key")
    eq(
      "openai: la clave NO está en los argumentos del proceso",
      table.concat(ospec2.cmd, " "):find("secret-key", 1, true),
      nil
    )
    cfg.openai.api_key_env = "OPENAI_API_KEY"
    vim.env.TEST_AGENT_KEY = nil

    -- detección contra los servidores falsos
    local detect = require "agent.setup.detect"
    local found
    detect.run(function(s)
      found = s
    end)
    vim.wait(8000, function()
      return found ~= nil
    end, 100)
    eq("detect: termina", found ~= nil, true)
    local srv = found.ollama_servers[1]
    eq(
      "detect: encuentra Ollama, sus modelos y lo cargado (GPU)",
      { srv.url, srv.version, #srv.models, srv.loaded[1].name, srv.loaded[1].vram == srv.loaded[1].size },
      { "http://127.0.0.1:18434", "0.5.0-fake", 3, "qwen2.5-coder:7b", true }
    )
    eq(
      "detect: encuentra el servidor OpenAI-compatible (y no repite el de Ollama)",
      vim.tbl_map(function(s)
        return s.url
      end, found.openai_servers),
      { "http://127.0.0.1:18435" }
    )
    eq("detect: ve los CLIs presentes con su versión", vim.tbl_filter(function(c)
      return c.name == "claude"
    end, found.clis)[1].path ~= nil or vim.fn.executable "claude" == 0, true)
    local text2 = table.concat(report.build(found, recommend.pick(found), "claude/sonnet"), "\n")
    eq("report: muestra servidores, modelos y dónde corre lo cargado", {
      text2:find("Ollama 0.5.0-fake", 1, true) ~= nil,
      text2:find("qwen2.5-coder:7b", 1, true) ~= nil,
      text2:find("on GPU", 1, true) ~= nil,
    }, { true, true, true })

    -- acciones: descarga con progreso, arranque cuando ya está arriba, recordar y aplicar
    local setup_actions = require "agent.setup.actions"
    local pct_seen, pull_ok = {}, nil
    setup_actions.pull("http://127.0.0.1:18434", "qwen2.5-coder:3b", function(_, pct)
      pct_seen[#pct_seen + 1] = pct
    end, function(ok)
      pull_ok = ok
    end)
    vim.wait(5000, function()
      return pull_ok ~= nil
    end)
    eq(
      "actions: pull con progreso",
      { pull_ok, vim.tbl_contains(pct_seen, 30), vim.tbl_contains(pct_seen, 100) },
      { true, true, true }
    )
    local started
    setup_actions.start_ollama("http://127.0.0.1:18434", function(ok)
      started = ok
    end)
    vim.wait(3000, function()
      return started ~= nil
    end)
    eq("actions: start con el servidor ya arriba no lanza nada y devuelve ok", started, true)
    cfg.ollama.host = nil -- sin fijar el host, el setup SÍ recuerda lo detectado
    eq(
      "actions: recuerda los servidores detectados",
      setup_actions.remember(found),
      { "ollama → http://127.0.0.1:18434", "openai → http://127.0.0.1:18435/v1" }
    )
    eq("actions: el backend lee el servidor recordado", ollama.host(), "http://127.0.0.1:18434")
    cfg.ollama.host = "127.0.0.1:18434"

    -- selección: el modelo ligero puede vivir en otro backend (gratis, local) sin mover el principal
    package.loaded["agent.selection"] = nil
    local sel = require "agent.selection"
    fake_store.backend, fake_store.models = "claude", nil
    sel.set("ollama", "qwen2.5-coder:1.5b", "light")
    local actions_reg = require "agent.actions"
    eq("selection: elegir el ligero en otro backend no cambia el principal", fake_store.backend, "claude")
    if require("agent.backends").is_available "claude" then
      local docs_sel, impl_sel = sel.current(actions_reg.get "docs"), sel.current(actions_reg.get "implement")
      eq(
        "selection: docs va al backend local; implement sigue en Claude",
        { docs_sel.backend, docs_sel.model, impl_sel.backend },
        { "ollama", "qwen2.5-coder:1.5b", "claude" }
      )
    end
    fake_store.light_backend = "no-existe"
    eq(
      "selection: un backend ligero inexistente se ignora",
      sel.current(actions_reg.get "docs").backend ~= "no-existe",
      true
    )
    fake_store.backend, fake_store.models = "ollama", nil
    eq(
      "selection: Ollama sin modelo elegido → model nil y el backend lo exige",
      { sel.current(actions_reg.get "implement").model, ollama.requires_model },
      { nil, true }
    )
    local applied =
      setup_actions.apply { main = { backend = "ollama", model = "a" }, light = { backend = "ollama", model = "b" } }
    eq(
      "actions: apply fija principal y ligero",
      { fake_store.models.ollama, fake_store.light_models.ollama, #applied },
      { "a", "b", 2 }
    )
    eq(
      "actions: parse_spec acepta modelos con / y :",
      { setup_actions.parse_spec "ollama/hf.co/x/y:q4" },
      { "ollama", "hf.co/x/y:q4" }
    )
    eq("actions: parse_spec rechaza backends desconocidos y specs sin modelo", {
      (setup_actions.parse_spec "nada/x"),
      (setup_actions.parse_spec "ollama"),
    }, {})

    cfg.ollama.host, cfg.openai.base_url = prev_host, prev_base
    fake_ollama:kill(15)
    fake_openai:kill(15)
  end

  -- sin servidor: Ollama no responde → la petición falla con un mensaje que dice qué hacer
  do
    local cfg = require("core.settings").agent
    local prev = cfg.ollama.host
    cfg.ollama.host = "127.0.0.1:1"
    local spec = ollama.build { system = "s", prompt = "p", model = "m", action = "docs" }
    local parser = ollama.parser()
    local out = vim.system(spec.cmd, { text = true, stdin = spec.stdin }):wait()
    local res = parser.finish(out.code, out.stderr or "")
    eq(
      "ollama sin servidor: error accionable",
      { res.ok, res.err:find("ollama serve", 1, true) ~= nil },
      { false, true }
    )
    cfg.ollama.host = prev
  end
  agent_state.get, agent_state.set = real_get, real_set
  package.loaded["agent.selection"] = real_selection
end

print(fails == 0 and "\nTODO OK" or ("\nFALLOS: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
