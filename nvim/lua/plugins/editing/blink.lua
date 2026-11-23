-- Autocompletion: native, no icons, ultra fast.
local keys = require "utils.blinkkeys"

return {
  "saghen/blink.cmp",
  version = "1.*", -- v2 (main) requires blink.lib compiled with Rust
  event = "InsertEnter",
  dependencies = {
    "rafamadriz/friendly-snippets",
    -- Enter between `{}`/`()`/`[]` expands through mini.pairs (utils/blinkkeys.pair_expand):
    -- loaded before blink so the pairs are registered when the first Enter lands.
    "echasnovski/mini.pairs",
  },
  opts = {
    -- Tab picks the option from the list, Enter inserts it (no arrows)
    keymap = {
      preset = "enter",
      -- goerrors: with a half-declared `ErrX`, Tab accepts the ghost text and Enter accepts it + newline
      -- With the menu open Tab/S-Tab PICK a suggestion (Enter inserts it). Without a menu, inside a
      -- snippet (e.g. `gorm.Open(dialector, opts)`) they jump between placeholders. To keep what
      -- you typed and move on: Esc (closes the menu without leaving the snippet) and then Tab.
      ["<Tab>"] = {
        keys.goerrors_accept,
        "select_next",
        keys.snippet_next,
        "fallback",
      },
      ["<CR>"] = {
        keys.goerrors_accept_newline,
        "accept",
        keys.pair_expand,
        "fallback",
      },
      ["<S-Tab>"] = {
        "select_prev",
        keys.snippet_prev,
        "fallback",
      },
      -- Esc with the menu open ONLY closes it (and undoes the suggestion that was inserted);
      -- you stay in insert and in your snippet. Without a menu, Esc leaves insert as usual.
      ["<Esc>"] = { "cancel", "fallback" },
      ["<Up>"] = false,
      ["<Down>"] = false,
    },
    appearance = {
      -- no kind icons (flat, minimalist)
      use_nvim_cmp_as_default = false,
      kind_icons = {},
    },
    sources = {
      default = { "lsp", "path", "snippets", "buffer" },
      -- lazydev only exists in Lua files (completes require() and plugin modules)
      -- gotags only in Go: struct tags derived from the field name (utils/gotags.lua)
      per_filetype = {
        -- pysmart: canonical imports (pd, np, train_test_split…) added at the top of the file; pydata: real data
        -- paths inside read_csv("…") and the columns of the df that was read (0 tokens, cached per file); pyattrs:
        -- exported names of an installed module; pybuiltins: print/len/for/if… — both instant while basedpyright works
        python = { "pysmart", "pydata", "pyattrs", "pybuiltins", "lsp", "path", "snippets", "buffer" },
        lua = { "lazydev", "lsp", "path", "snippets", "buffer" },
        go = { "gotags", "gosmart", "lsp", "path", "snippets", "buffer" },
        cs = { "csharpsmart", "lsp", "path", "snippets", "buffer" },
        dart = { "dartsmart", "lsp", "path", "snippets", "buffer" },
        -- sqlschema: real tables/columns from the connection (also without sqls); sqlkeywords: LIMIT/ORDER BY/...
        sql = { "sqlschema", "sqlkeywords", "sqlpredict", "lsp", "path", "snippets", "buffer" },
      },
      providers = {
        pysmart = { name = "PyImport", module = "utils.pysmart", score_offset = 95 },
        pydata = { name = "PyData", module = "utils.pydata", score_offset = 95 },
        pyattrs = { name = "PyAttr", module = "utils.pyattrs", score_offset = 90 },
        pybuiltins = { name = "PyBuiltin", module = "utils.pybuiltins", score_offset = 92 },
        lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
        gotags = { name = "GoTags", module = "utils.gotags", score_offset = 100 },
        -- constructor / struct{} depending on context, and filters out snippets that do not apply (utils/gosmart.lua)
        gosmart = { name = "GoSmart", module = "utils.gosmart", score_offset = 90 },
        -- C#: ctor/props/DbSet/DI from the project's own types, with the using each one needs (utils/csharpsmart.lua)
        csharpsmart = { name = "C# Smart", module = "utils.csharpsmart", score_offset = 90 },
        -- Dart: widgets, Riverpod providers and freezed classes for the project's stack, named after the file, with
        -- their import and `part` lines (utils/dartsmart.lua)
        dartsmart = { name = "DartSmart", module = "utils.dartsmart", score_offset = 90 },
        -- real tables/columns from the project's database, cached (utils/sqlschema.lua)
        sqlschema = { name = "SqlSchema", module = "utils.sqlschema", score_offset = 88 },
        -- dialect-aware keywords and functions: instant, 0 tokens (utils/sqlkeywords.lua)
        sqlkeywords = { name = "SqlKeyword", module = "utils.sqlkeywords" },
        -- your own past queries in this project (utils/sqlpredict.lua)
        sqlpredict = { name = "SqlQuery", module = "utils.sqlpredict", score_offset = 70 },
        -- friendly-snippets' flutter.json uses the language id "flutter", which is not
        -- a real Neovim filetype (it is always "dart"): requested explicitly.
        -- when starting a declaration in Go: no stray buffer words nor the generic func/type from the LSP
        buffer = {
          transform_items = function(ctx, items)
            return require("utils.gosmart").quiet_buffer(ctx, items)
          end,
        },
        lsp = {
          -- blink waits for EVERY provider before showing the menu (2 s by default). A language server can take that
          -- long for the first completion at a new position: show what the local sources already have, then merge the
          -- LSP items when they arrive instead of holding the menu open.
          timeout_ms = 150,
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
      -- no menu while there is an `ErrX` with ghost text (utils/goerrors.lua)
      menu = {
        -- flat: `label … detail` only, no kind-icon column (the detail says what it is), detail pushed right; no blank
        -- rows above/below and the selection spans the whole block, like the demo's list
        border = "none",
        draw = { columns = { { "label", "label_description", gap = 3 } }, padding = { 1, 1 } },
        auto_show = function()
          return not require("utils.goerrors").active()
        end,
      },
      -- no preselection, except inside a Go struct tag and on the new line after `x, err := …` (Enter accepts the suggestion)
      list = {
        selection = {
          preselect = function()
            return require("utils.gotags").active() or require("utils.goiferr").active()
          end,
        },
      },
      documentation = {
        -- Resolving a doc costs ~120–400 ms the first time for a pandas/numpy symbol. Moving through the list must
        -- not pay that per item: <C-space> still shows the documentation on demand (and hides it again).
        auto_show = false,
        window = { border = require("ui.flat").border "beside" },
      },
    },
    signature = {
      enabled = true,
      window = { border = require("ui.flat").border "float" },
    },
  },
  config = function(_, opts)
    require("blink.cmp").setup(opts)
    require("utils.gosmart").autotrigger()
    require("utils.goerrors").setup()
  end,
}
