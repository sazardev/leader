-- ── User settings (single configurable source of truth) ──────────────────────
-- Everything "adjustable" lives here with its default value. To change it without
-- touching the repo, create `lua/local.lua` (git-ignored) returning a partial
-- table, or define `vim.g.nvim_settings` before loading the config:
--
--   -- lua/local.lua
--   return { theme = { name = "catppuccin" }, languages = { disabled = { "astro" } } }
local defaults = {
  theme = {
    -- Default theme (the one restored when picking "default" in <leader>S)
    name = "gruvbox",
    toggle = { "gruvbox", "gruvbox_light" },

    -- Theme inherited from the terminal (Alacritty): see lua/appearance/
    terminal = {
      enabled = true,
      config = nil, -- path to alacritty.toml; nil = autodetect (Linux, Windows, WSL)
      min_contrast = 3.0, -- minimum contrast of the accent colors against the background
      watch_ms = 1000, -- polling of the Alacritty config to follow it live (0 = off)
    },
  },

  -- Flat design (lua/ui/flat): filled blocks instead of boxed windows, every color derived from the active theme
  -- (also the terminal one). Same look as the landing page's demo editor.
  ui = {
    flat = true, -- false = the plugins' own look (single borders, their colors)
    notify = true, -- flat notifications (bottom right, colored bar) instead of the default vim.notify
    fresh_ms = 450, -- fade of the "just changed" flash on yank and on what the agent writes (0 = off)
    blink_cursor = true, -- blinking cursor: block in normal mode, bar in insert
  },

  -- Dashboard: initial ASCII art (see lua/ui/arts/): a name from the catalog.
  -- The one picked from the dashboard ("Change Art") takes priority.
  dashboard = {
    art = "hornet",
  },

  -- Light mode (low-RAM machines): no resident LSP nor go.nvim.
  -- `force`: true/false forces the mode; nil = autodetect by RAM.
  -- The NVIM_LIGHT=1|0 environment variable takes priority over this.
  light = {
    force = nil,
    ram_threshold_gb = 2,
  },

  -- Languages (see lua/languages/): disable by name the ones you do not use.
  languages = {
    disabled = {},
  },

  -- Sessions (persistence.nvim saves on exit; see core/autocmds/session.lua)
  session = {
    autosave_ms = 60000, -- saves in the background if something changed, to survive a power cut (0 = only on exit)
    herdr = false, -- inside Herdr, registers nvim as an "agent" to reopen the pane after the server restarts. Off: Herdr 0.9.x ignores resume and nvim gets in the way in the Agents panel (requires Herdr >= 0.10.0)
  },

  -- Inline agent (lua/agent/): ONE-SHOT actions over what you are looking at (implement,
  -- review, explain...) via `claude -p` or `opencode run`. Menu <leader>a. No chat or sidebar.
  agent = {
    backend = "auto", -- "auto" | "claude" | "opencode". What you pick with <leader>am (backend + model) is remembered and wins
    order = { "claude", "opencode", "ollama", "openai" }, -- autodetection order with "auto" (those in `custom` go last)
    -- Backend for LIGHT actions (docs, explain...). nil = same as the main one. With "ollama" (or "openai") those
    -- actions run on a LOCAL, free model while implement/fix stay on Claude: pick it with <leader>am.
    light_backend = nil,
    language = "English", -- language of the agent's explanations, answers and findings (code is not translated)
    rules = nil, -- extra text (conventions) for EVERY prompt; per project: `.agent.md` at the root
    timeout_ms = 120000,
    -- Which actions run on the LIGHT model (cheap and fast) instead of the main one. Each action ships
    -- with its own default (docs and explain: light); change it here: { review = "light", docs = "main" }
    tiers = {},
    -- Run history (<leader>ah): prompt, response, tokens and cost of each action, in
    -- stdpath("state")/agent-history.jsonl. `store_text = false` stores only metrics (no code of yours).
    history = {
      enabled = true,
      store_text = true,
      max_entries = 1000, -- past ~1.5x it is compacted down to the most recent ones
    },
    -- DDD (<leader>aD): local static analysis (free) + agent actions that follow your layers and naming.
    -- Layers are recognized by DIRECTORY NAME (first path segment that matches).
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
      composition_roots = { "main", "cmd", "bootstrap", "container", "di", "wire", "server" }, -- may wire everything
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
      max_context_chars = 1800, -- cap of the <ddd> section sent to the model
    },
    context = {
      max_chars = 8000, -- cap of the EXTRA context (rules, schema, signatures, diagnostics); the target is separate
      max_target_lines = 400, -- a larger target is rejected (trimming it would break the replacement)
      window = 40, -- max lines if there is no function/class: paragraph around the cursor
      callees = 6, -- max called symbols whose signature is requested from the LSP
      diagnostic_lines = 12, -- inline fix: max lines the diagnostic under the cursor covers (if it spans more, only what starts there)
      around = 25, -- inline fix: lines of surrounding code (before and after) shown as context
      types = 4, -- max type definitions (struct/class/interface...) the target uses
      type_lines = 30, -- max lines per type definition
      hover_timeout_ms = 700, -- max wait for the LSP; whatever did not arrive in time is omitted
    },
    apply = { format = false }, -- when accepting a replacement, formats that range with conform
    keys = { accept = "<CR>", reject = "<Esc>" }, -- only while a proposal is visible in the buffer
    claude = {
      models = { "haiku", "sonnet", "opus" },
      model = "sonnet", -- main model (implement, fix, refactor, review, ask)
      light_model = "haiku", -- light model (actions of tier "light": docs, explain)
      -- CLI prompt cache: OFF. Every call carries a different message, so the cache never
      -- hits and only the WRITE is charged (up to 2x the input price). Measured: -40% cost per call.
      prompt_cache = false,
      max_cost_usd = 0.25, -- cap per call (`--max-budget-usd`): cuts off a runaway response; nil = no cap
    },
    opencode = {
      models = nil, -- nil = what `opencode models` returns (requested once per session)
      model = nil, -- e.g. "opencode-go/qwen3.8-flash"
      light_model = nil, -- light model; nil = the main one (opencode ids depend on your provider)
      agent = nil, -- opencode's own agent (by default, a tool-less one generated on the fly)
      attach = nil, -- "http://localhost:4096" (`opencode serve`): avoids paying the startup on every action
    },
    -- LOCAL models with Ollama (CPU or GPU/CUDA: it uses the GPU only if present). Connects by itself: <leader>am → Setup detects the server
    -- (OLLAMA_HOST, localhost, the Windows host from WSL), can start it and pull a model suited to your VRAM.
    ollama = {
      host = nil, -- "http://127.0.0.1:11434"; nil = autodetect
      model = nil, -- e.g. "qwen2.5-coder:7b"; nil = the one the setup picks
      light_model = nil, -- small model for light actions; nil = the main one
      models = nil, -- nil = what /api/tags returns
      num_ctx = nil, -- nil = computed per request (prompt + margin); an integer fixes it. Ollama silently TRUNCATES whatever does not fit
      max_ctx = 32768, -- cap of the automatic computation (context memory grows with it)
      keep_alive = "30m", -- keeps the model loaded between actions: what speeds up a local model the most
      temperature = 0.1, -- more deterministic answers (code block / findings format)
      think = nil, -- true/false forces reasoning mode on models that support it; nil = the model's own
    },
    -- Any OpenAI-API-compatible server: LM Studio (1234), llama.cpp (8080), vLLM (8000), LiteLLM, OpenRouter...
    openai = {
      base_url = nil, -- "http://127.0.0.1:1234/v1"; nil = autodetect the usual ports (or OPENAI_BASE_URL)
      api_key_env = "OPENAI_API_KEY", -- environment variable holding the key (local servers do not ask for it)
      model = nil,
      light_model = nil,
      models = nil, -- nil = what /v1/models returns
      temperature = 0.1,
    },
    -- Other command-line agents (Hermes Agent, Gemini CLI, Codex, Aider...): one declarative entry per CLI. See
    -- docs/cheatsheets/agent.md → "Backends". Example (CHECK the flags of your version):
    --   custom = { hermes = { cmd = { "hermes", "chat", "-q", "{prompt}" }, system_in_prompt = true, models = { "default" } } }
    custom = {},
  },

  format_on_save = {
    enabled = true,
    timeout_ms = 2000,
  },

  -- Clipboard via OSC 52 (WSL/SSH without a graphical server): "auto" | true | false
  clipboard = {
    osc52 = "auto",
  },

  -- Integrated terminal (toggleterm): used by the per-language menus and lazydocker.
  -- position: "right" (side panel) | "bottom" | "float". With fewer than
  -- `narrow_columns` columns the side panel moves to the bottom (it does not squash the code).
  terminal = {
    position = "right",
    width = 0.38, -- fraction of the columns (side panel)
    min_width = 50,
    height = 0.35, -- fraction of the lines (bottom panel)
    min_height = 8,
    narrow_columns = 120,
    float_scale = 0.85, -- fraction of the screen in float mode
  },

  -- Linters that do NOT run on InsertLeave (analyze the whole package: heavy)
  -- Long comments (menu <leader>C, lua/utils/comments.lua): folded with nvim-ufo
  comments = {
    min_lines = 4, -- a comment (block or consecutive lines) with fewer lines is not folded
    auto_collapse = false, -- INITIAL value of "comments folded"; what you pick with <leader>Cc / <leader>Ce is saved and wins
  },

  -- Git (lua/commit/, menu <leader>G): commits with Conventional Commits
  git = {
    commit = {
      -- { type, description }. The .githooks/commit-msg hook validates the same types: if you change
      -- the list here, change it there too.
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
      subject_max = 72, -- max length of the first line ("type(scope): subject")
      history = 300, -- recent commits read to suggest scopes
      diff_max_chars = 6000, -- cap of the compact diff sent to the AI (split across files); less = faster and cheaper
      -- <leader>GM (automatic commit): if nothing is staged, stages EVERYTHING modified except what matches these
      -- Lua patterns (secrets and keys: you stage those by hand). Whatever you already staged is never filtered.
      sensitive = { "^%.env", "%.env%.", "%.pem$", "%.key$", "%.p12$", "%.pfx$", "id_rsa", "id_ed25519", "credentials", "secrets?%.", "%.kdbx$" },
    },
  },

  lint = {
    skip_insert_leave = { "go" },
  },

  -- vim.diagnostic.config(...): how LSP/linter errors are shown
  diagnostics = {
    severity_sort = true, -- the error shows before the warning on the same line
    update_in_insert = false, -- no half-typed errors while you write: in insert mode the blocks are hidden and return on leaving
    virtual_text = false, -- the text on the right gets cut off: the inline blocks (below) replace it
    signs = false, -- no icons next to the number: the number's background says it (diagnostic_blocks.number)
  },

  -- Diagnostic blocks under their line (utils/diagblocks.lua). `auto` and `mode` are the INITIAL value: what
  -- you pick with <leader>xa / <leader>xc is saved in stdpath("state")/diagblocks.json and overrides them
  diagnostic_blocks = {
    auto = true, -- appear on their own in every buffer that has diagnostics
    mode = "expanded", -- "expanded" all open | "compact" one line each (the one under the cursor opens)
    number = true, -- the line number is painted with the severity pill (centered on the digits), like the statusline (git is the signcolumn bar)
  },

  -- vim.o.<key> = value
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
    ignorecase = true, -- search ignoring case...
    smartcase = true, -- ...unless the pattern contains an uppercase letter
    inccommand = "split", -- live preview of :s/…/…/
    autoread = true, -- reloads what changes outside nvim (git, formatters); see autocmds/autoread.lua
    scrolloff = 5,
    sidescrolloff = 8,
    cursorline = true,
    cursorlineopt = "number",
    signcolumn = "no", -- signs (the git bar) are drawn by the statuscolumn in ONE cell; "yes" gives them two
    -- signs + number; the number is painted by utils/diagblocks.lua (centered severity pill)
    statuscolumn = "%s%{%v:lua.require'utils.diagblocks'.statuscolumn()%}",
    jumpoptions = "view", -- <C-o>/<C-i> also restore the view (scroll), not just the cursor
    undofile = true, -- undo survives closing nvim (and a power cut)
    exrc = true, -- loads .nvim.lua per project (guarded by :trust)
    -- What a session saves (persistence.nvim); without `terminal`/`blank`: they are not restored
    sessionoptions = "buffers,curdir,tabpages,winsize,help,globals,skiprtp,folds",
  },
}

local overrides = {}

-- NVIM_NO_LOCAL=1 ignores lua/local.lua (used by scripts/gen-cheatsheet.sh so that
-- the generated cheatsheet does not depend on the machine)
local ok, localcfg = pcall(require, "local")
if ok and type(localcfg) == "table" and not vim.env.NVIM_NO_LOCAL then
  overrides = localcfg
end

return vim.tbl_deep_extend("force", defaults, overrides, vim.g.nvim_settings or {})
