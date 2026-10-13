-- ── Ajustes del usuario (única fuente de verdad configurable) ────────────────
-- Todo lo "ajustable" vive aquí con su valor por defecto. Para cambiarlo sin
-- tocar el repo, crea `lua/local.lua` (ignorado por git) devolviendo una tabla
-- parcial, o define `vim.g.nvim_settings` antes de cargar la config:
--
--   -- lua/local.lua
--   return { theme = { name = "catppuccin" }, languages = { disabled = { "astro" } } }
local defaults = {
  theme = {
    -- Tema por defecto (el que vuelve al elegir "default" en <leader>S)
    name = "gruvbox",
    toggle = { "gruvbox", "gruvbox_light" },

    -- Tema heredado de la terminal (Alacritty): ver lua/appearance/
    terminal = {
      enabled = true,
      config = nil, -- ruta a alacritty.toml; nil = autodetección (Linux, Windows, WSL)
      min_contrast = 3.0, -- contraste mínimo de los colores de acento contra el fondo
      watch_ms = 1000, -- sondeo de la config de Alacritty para seguirla en vivo (0 = apagado)
    },
  },

  -- Dashboard: arte ASCII inicial (ver lua/ui/arts/): un nombre del catálogo.
  -- El que se elige desde el dashboard ("Change Art") tiene prioridad.
  dashboard = {
    art = "hornet",
  },

  -- Modo ligero (equipos de poca RAM): sin LSP residente ni go.nvim.
  -- `force`: true/false fuerza el modo; nil = autodetección por RAM.
  -- La variable de entorno NVIM_LIGHT=1|0 tiene prioridad sobre esto.
  light = {
    force = nil,
    ram_threshold_gb = 2,
  },

  -- Lenguajes (ver lua/languages/): desactiva por nombre los que no uses.
  languages = {
    disabled = {},
  },

  -- Sesiones (persistence.nvim guarda al salir; ver core/autocmds/session.lua)
  session = {
    autosave_ms = 60000, -- guarda en segundo plano si algo cambió, para sobrevivir a un corte de luz (0 = solo al salir)
    herdr = false, -- dentro de Herdr, registra nvim como "agente" para reabrir el pane tras reiniciar el servidor. Apagado: Herdr 0.9.x ignora el resume y nvim estorba en el panel Agents (requiere Herdr >= 0.10.0)
  },

  -- Agente inline (lua/agent/): acciones de UN disparo sobre lo que estás viendo (implementar,
  -- revisar, explicar...) vía `claude -p` u `opencode run`. Menú <leader>a. Sin chat ni sidebar.
  agent = {
    backend = "auto", -- "auto" | "claude" | "opencode". Lo elegido con <leader>am (backend + modelo) se recuerda y gana
    order = { "claude", "opencode", "ollama", "openai" }, -- orden de la autodetección con "auto" (los de `custom` van al final)
    -- Backend de las acciones LIGERAS (docs, explain...). nil = el mismo que el principal. Con "ollama" (o "openai") esas
    -- acciones corren en un modelo LOCAL y gratis mientras implement/fix siguen en Claude: se elige con <leader>am.
    light_backend = nil,
    language = "English", -- idioma de explicaciones, respuestas y hallazgos del agente (el código no se traduce)
    rules = nil, -- texto extra (convenciones) para TODO prompt; por proyecto: `.agent.md` en la raíz
    timeout_ms = 120000,
    -- Qué acciones corren en el modelo LIGERO (barato y rápido) en vez del principal. Cada acción trae
    -- el suyo por defecto (docs y explain: ligero); aquí lo cambias: { review = "light", docs = "main" }
    tiers = {},
    -- Historial de ejecuciones (<leader>ah): prompt, respuesta, tokens y coste de cada acción, en
    -- stdpath("state")/agent-history.jsonl. `store_text = false` guarda solo métricas (sin tu código).
    history = {
      enabled = true,
      store_text = true,
      max_entries = 1000, -- al pasar de ~1.5x se compacta a las más recientes
    },
    -- DDD (<leader>aD): análisis estático local (gratis) + acciones del agente que siguen tus capas y tu nomenclatura.
    -- Las capas se reconocen por NOMBRE DE DIRECTORIO (primer segmento de la ruta que coincida).
    ddd = {
      layers = {
        domain = { "domain", "entities", "entity", "model", "models" },
        application = {
          "application",
          "usecase",
          "usecases",
          "use_cases",
          "use-cases",
          "services",
          "commands",
          "queries",
        },
        infrastructure = {
          "infrastructure",
          "infra",
          "adapters",
          "adapter",
          "persistence",
          "repositories",
          "db",
          "database",
          "gateways",
          "clients",
          "external",
        },
        interface = {
          "interface",
          "interfaces",
          "presentation",
          "api",
          "http",
          "handlers",
          "controllers",
          "web",
          "rest",
          "grpc",
          "cli",
          "ui",
          "transport",
        },
      },
      composition_roots = { "main", "cmd", "bootstrap", "container", "di", "wire", "server" }, -- pueden cablear todo
      ignore = {
        ".git",
        "node_modules",
        "vendor",
        "dist",
        "build",
        "target",
        ".venv",
        "venv",
        "__pycache__",
        ".next",
        "coverage",
        ".idea",
        ".cache",
      },
      max_files = 1500,
      max_context_chars = 1800, -- tope de la sección <ddd> que va al modelo
    },
    context = {
      max_chars = 8000, -- tope del contexto EXTRA (reglas, esquema, firmas, diagnósticos); el objetivo va aparte
      max_target_lines = 400, -- un objetivo mayor se rechaza (recortarlo rompería el reemplazo)
      window = 40, -- líneas máx. si no hay función/clase: párrafo alrededor del cursor
      callees = 6, -- máx. de símbolos llamados cuya firma se pide al LSP
      diagnostic_lines = 12, -- fix inline: líneas máx. que cubre el diagnóstico bajo el cursor (si abarca más, solo lo que empieza ahí)
      around = 25, -- fix inline: líneas de código de alrededor (antes y después) que se enseñan como contexto
      types = 4, -- máx. de definiciones de tipo (struct/clase/interfaz...) que usa el objetivo
      type_lines = 30, -- líneas máx. por definición de tipo
      hover_timeout_ms = 700, -- espera máx. al LSP; lo que no llegó a tiempo se omite
    },
    apply = { format = false }, -- al aceptar un reemplazo, formatea ese rango con conform
    keys = { accept = "<CR>", reject = "<Esc>" }, -- solo mientras hay una propuesta visible en el buffer
    claude = {
      models = { "haiku", "sonnet", "opus" },
      model = "sonnet", -- modelo principal (implementar, arreglar, refactorizar, revisar, preguntar)
      light_model = "haiku", -- modelo ligero (acciones de tier "light": docs, explain)
      -- Caché de prompts del CLI: APAGADA. Cada llamada lleva un mensaje distinto, así que la caché nunca
      -- acierta y solo cobra la ESCRITURA (hasta 2x el precio de entrada). Medido: -40% de coste por llamada.
      prompt_cache = false,
      max_cost_usd = 0.25, -- tope por llamada (`--max-budget-usd`): corta una respuesta desbocada; nil = sin tope
    },
    opencode = {
      models = nil, -- nil = lo que devuelve `opencode models` (se pide una vez por sesión)
      model = nil, -- p. ej. "opencode-go/qwen3.8-flash"
      light_model = nil, -- modelo ligero; nil = el principal (los ids de opencode dependen de tu proveedor)
      agent = nil, -- agente propio de opencode (por defecto, uno sin herramientas generado al vuelo)
      attach = nil, -- "http://localhost:4096" (`opencode serve`): evita pagar el arranque en cada acción
    },
    -- Modelos LOCALES con Ollama (CPU o GPU/CUDA: la usa solo si hay). Se conecta solo: <leader>am → Setup detecta el servidor
    -- (OLLAMA_HOST, localhost, el host de Windows desde WSL), puede arrancarlo y bajar un modelo adecuado a tu VRAM.
    ollama = {
      host = nil, -- "http://127.0.0.1:11434"; nil = autodetección
      model = nil, -- p. ej. "qwen2.5-coder:7b"; nil = el que elija el setup
      light_model = nil, -- modelo pequeño para las acciones ligeras; nil = el principal
      models = nil, -- nil = lo que devuelve /api/tags
      num_ctx = nil, -- nil = se calcula por petición (prompt + margen); un entero lo fija. Ollama TRUNCA en silencio lo que no cabe
      max_ctx = 32768, -- tope del cálculo automático (la memoria de contexto crece con él)
      keep_alive = "30m", -- mantiene el modelo cargado entre acciones: lo que más acelera un modelo local
      temperature = 0.1, -- respuestas más deterministas (formato de bloque de código / hallazgos)
      think = nil, -- true/false fuerza el modo de razonamiento en modelos que lo soportan; nil = el del modelo
    },
    -- Cualquier servidor compatible con la API de OpenAI: LM Studio (1234), llama.cpp (8080), vLLM (8000), LiteLLM, OpenRouter...
    openai = {
      base_url = nil, -- "http://127.0.0.1:1234/v1"; nil = autodetección de los puertos habituales (o OPENAI_BASE_URL)
      api_key_env = "OPENAI_API_KEY", -- variable de entorno con la clave (los servidores locales no la piden)
      model = nil,
      light_model = nil,
      models = nil, -- nil = lo que devuelve /v1/models
      temperature = 0.1,
    },
    -- Otros agentes por línea de comandos (Hermes Agent, Gemini CLI, Codex, Aider...): una entrada declarativa por CLI. Ver
    -- docs/cheatsheets/agent.md → "Backends". Ejemplo (REVISA las banderas de tu versión):
    --   custom = { hermes = { cmd = { "hermes", "chat", "-q", "{prompt}" }, system_in_prompt = true, models = { "default" } } }
    custom = {},
  },

  format_on_save = {
    enabled = true,
    timeout_ms = 2000,
  },

  -- Clipboard por OSC 52 (WSL/SSH sin servidor gráfico): "auto" | true | false
  clipboard = {
    osc52 = "auto",
  },

  -- Terminal integrada (toggleterm): la usan los menús por lenguaje y lazydocker.
  -- position: "right" (panel lateral) | "bottom" | "float". Con menos de
  -- `narrow_columns` columnas el panel lateral pasa abajo (no aplasta el código).
  terminal = {
    position = "right",
    width = 0.38, -- fracción de las columnas (panel lateral)
    min_width = 50,
    height = 0.35, -- fracción de las líneas (panel inferior)
    min_height = 8,
    narrow_columns = 120,
    float_scale = 0.85, -- fracción de la pantalla en modo float
  },

  -- Linters que NO corren en InsertLeave (analizan todo el paquete: pesados)
  -- Comentarios largos (menú <leader>C, lua/utils/comments.lua): se pliegan con nvim-ufo
  comments = {
    min_lines = 4, -- un comentario (bloque o líneas seguidas) con menos líneas no se pliega
    auto_collapse = false, -- true: los comentarios largos se abren ya plegados
  },

  -- Git (lua/commit/, menú <leader>G): commits con Conventional Commits
  git = {
    commit = {
      -- { tipo, descripción }. El hook .githooks/commit-msg valida los mismos tipos: si cambias
      -- la lista aquí, cámbiala también allí.
      types = {
        { "feat", "new feature" },
        { "fix", "bug fix" },
        { "refactor", "code change that neither fixes nor adds" },
        { "docs", "documentation only" },
        { "style", "formatting, no logic change" },
        { "perf", "performance improvement" },
        { "test", "add or fix tests" },
        { "build", "build system or dependencies" },
        { "ci", "CI configuration" },
        { "chore", "maintenance, tooling" },
        { "revert", "revert a previous commit" },
      },
      subject_max = 72, -- largo máximo de la primera línea ("tipo(scope): asunto")
      history = 300, -- commits recientes que se leen para sugerir scopes
      diff_max_chars = 6000, -- tope del diff compacto que se envía a la IA (repartido entre los archivos); menos = más rápido y barato
      -- <leader>GM (commit automático): si no hay nada preparado, prepara TODO lo modificado salvo lo que case con estos
      -- patrones de Lua (secretos y llaves: eso lo preparas tú a mano). Lo que ya preparaste nunca se filtra.
      sensitive = { "^%.env", "%.env%.", "%.pem$", "%.key$", "%.p12$", "%.pfx$", "id_rsa", "id_ed25519", "credentials", "secrets?%.", "%.kdbx$" },
    },
  },

  lint = {
    skip_insert_leave = { "go" },
  },

  -- vim.diagnostic.config(...): cómo se muestran los errores del LSP/linters
  diagnostics = {
    severity_sort = true, -- el error se ve antes que el aviso en la misma línea
    update_in_insert = false, -- sin errores a medias mientras se escribe
    virtual_text = false, -- el texto a la derecha se corta: lo reemplazan los bloques en línea (abajo)
    signs = false, -- sin iconos junto al número: el fondo del número y los bloques ya lo dicen (diagnostic_blocks)
  },

  -- Bloques de diagnóstico bajo su línea (utils/diagblocks.lua). `auto` y `mode` son el valor INICIAL: lo que
  -- eliges con <leader>xa / <leader>xc se guarda en stdpath("state")/diagblocks.json y manda sobre ellos
  diagnostic_blocks = {
    auto = true, -- aparecen solos en cada buffer que tenga diagnósticos
    mode = "expanded", -- "expanded" todos abiertos | "compact" una línea cada uno (se abre el del cursor)
    marker = true, -- con los bloques apagados: solo un icono de color (✖ ▲ ● ○) al final de la línea
    number = true, -- el fondo del número de línea se tiñe con la severidad (el git es la barra de la signcolumn)
  },

  -- vim.o.<clave> = valor
  options = {
    cmdheight = 0,
    showmode = false,
    showcmd = false,
    laststatus = 3,
    lazyredraw = true,
    synmaxcol = 200,
    updatetime = 350,
    more = false,
    pumblend = 0,
    winblend = 0,
    redrawtime = 1500,
    confirm = true,
    timeoutlen = 300,
    ttimeoutlen = 50,
    splitright = true,
    splitbelow = true,
    ignorecase = true, -- buscar sin distinguir mayúsculas...
    smartcase = true, -- ...salvo que el patrón lleve alguna
    inccommand = "split", -- vista previa en vivo de :s/…/…/
    autoread = true, -- recarga lo que cambia fuera de nvim (git, formatters); ver autocmds/autoread.lua
    scrolloff = 5,
    sidescrolloff = 8,
    cursorline = true,
    cursorlineopt = "number",
    signcolumn = "yes:1",
    jumpoptions = "view", -- <C-o>/<C-i> restauran también la vista (scroll), no solo el cursor
    undofile = true, -- el undo sobrevive a cerrar nvim (y a un corte de luz)
    exrc = true, -- carga .nvim.lua por proyecto (protegido por :trust)
    -- Qué guarda una sesión (persistence.nvim); sin `terminal`/`blank`: no se restauran
    sessionoptions = "buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds",
  },
}

local overrides = {}

-- NVIM_NO_LOCAL=1 ignora lua/local.lua (lo usa scripts/gen-cheatsheet.sh para que
-- el cheatsheet generado no dependa de la máquina)
local ok, localcfg = pcall(require, "local")
if ok and type(localcfg) == "table" and not vim.env.NVIM_NO_LOCAL then
  overrides = localcfg
end

return vim.tbl_deep_extend("force", defaults, overrides, vim.g.nvim_settings or {})
