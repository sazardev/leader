-- Autocompletar: nativo, sin íconos, ultra rápido.
local keys = require "utils.blinkkeys"

return {
  "saghen/blink.cmp",
  version = "1.*", -- v2 (main) requiere blink.lib compilado con Rust
  event = "InsertEnter",
  dependencies = { "rafamadriz/friendly-snippets" },
  opts = {
    -- Tab elige la opción de la lista, Enter la inserta (sin flechas)
    keymap = {
      preset = "enter",
      -- goerrors: con un `ErrX` a medio declarar, Tab acepta el texto fantasma y Enter lo acepta + línea nueva
      -- Con el menú abierto Tab/S-Tab ELIGEN sugerencia (Enter la inserta). Sin menú, dentro de un
      -- snippet (p. ej. `gorm.Open(dialector, opts)`) saltan de hueco. Para quedarte con lo que
      -- tecleaste y seguir: Esc (cierra el menú sin salir del snippet) y luego Tab.
      ["<Tab>"] = {
        keys.goerrors_accept,
        "select_next",
        keys.snippet_next,
        "fallback",
      },
      ["<CR>"] = {
        keys.goerrors_accept_newline,
        "accept",
        "fallback",
      },
      ["<S-Tab>"] = {
        "select_prev",
        keys.snippet_prev,
        "fallback",
      },
      -- Esc con el menú abierto SOLO lo cierra (y deshace la sugerencia que estuviera insertada);
      -- sigues en insert y en tu snippet. Sin menú, Esc sale de insert como siempre.
      ["<Esc>"] = { "cancel", "fallback" },
      ["<Up>"] = false,
      ["<Down>"] = false,
    },
    appearance = {
      -- sin íconos de kind (plano, minimalista)
      use_nvim_cmp_as_default = false,
      kind_icons = {},
    },
    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
      -- lazydev solo existe en archivos Lua (completa require() y módulos de plugins)
      -- gotags solo en Go: tags de struct derivados del nombre del campo (utils/gotags.lua)
      per_filetype = {
        lua = { "lazydev", "lsp", "path", "snippets", "buffer" },
        go = { "gotags", "gosmart", "lsp", "path", "snippets", "buffer" },
      },
      providers = {
        lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
        gotags = { name = "GoTags", module = "utils.gotags", score_offset = 100 },
        -- constructor / struct{} según el contexto, y filtra snippets que no aplican (utils/gosmart.lua)
        gosmart = { name = "GoSmart", module = "utils.gosmart", score_offset = 90 },
        -- flutter.json de friendly-snippets usa el language id "flutter", que no
        -- es un filetype real de Neovim (siempre es "dart"): se pide explícito.
        -- al empezar una declaración en Go: sin palabras sueltas del buffer ni el func/type genérico del LSP
        buffer = {
          transform_items = function(ctx, items)
            return require("utils.gosmart").quiet_buffer(ctx, items)
          end,
        },
        lsp = {
          transform_items = function(ctx, items)
            return require("utils.gosmart").quiet_lsp(ctx, items)
          end,
        },
        snippets = {
          transform_items = function(ctx, items)
            return require("utils.gosmart").filter_snippets(ctx, items)
          end,
          opts = {
            extended_filetypes = { dart = { "flutter" } },
          },
        },
      },
    },
    completion = {
      -- sin menú mientras hay un `ErrX` con texto fantasma (utils/goerrors.lua)
      menu = {
        auto_show = function()
          return not require("utils.goerrors").active()
        end,
      },
      -- sin preselección, salvo dentro de un struct tag de Go y en la línea nueva tras `x, err := …` (Enter acepta la sugerencia)
      list = {
        selection = {
          preselect = function()
            return require("utils.gotags").active() or require("utils.goiferr").active()
          end,
        },
      },
      documentation = {
        auto_show = true,
        auto_show_delay_ms = 0, -- sin espera al seleccionar (por defecto 500 ms)
        window = { border = "single" },
      },
    },
    signature = {
      enabled = true,
      window = { border = "single" },
    },
  },
  config = function(_, opts)
    require("blink.cmp").setup(opts)
    require("utils.gosmart").autotrigger()
    require("utils.goerrors").setup()
  end,
}
