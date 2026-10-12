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
  lint = {
    skip_insert_leave = { "go" },
  },

  -- vim.diagnostic.config(...): cómo se muestran los errores del LSP/linters
  diagnostics = {
    severity_sort = true, -- el error se ve antes que el aviso en la misma línea
    update_in_insert = false, -- sin errores a medias mientras se escribe
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
