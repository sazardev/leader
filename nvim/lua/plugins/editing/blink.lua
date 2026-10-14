-- Autocompletion: native, no icons, ultra fast.
local keys = require "utils.blinkkeys"

return {
  "saghen/blink.cmp",
  version = "1.*", -- v2 (main) requires blink.lib compiled with Rust
  event = "InsertEnter",
  dependencies = { "rafamadriz/friendly-snippets" },
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
        lua = { "lazydev", "lsp", "path", "snippets", "buffer" },
        go = { "gotags", "gosmart", "lsp", "path", "snippets", "buffer" },
      },
      providers = {
        lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
        gotags = { name = "GoTags", module = "utils.gotags", score_offset = 100 },
        -- constructor / struct{} depending on context, and filters out snippets that do not apply (utils/gosmart.lua)
        gosmart = { name = "GoSmart", module = "utils.gosmart", score_offset = 90 },
        -- friendly-snippets' flutter.json uses the language id "flutter", which is not
        -- a real Neovim filetype (it is always "dart"): requested explicitly.
        -- when starting a declaration in Go: no stray buffer words nor the generic func/type from the LSP
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
      -- no menu while there is an `ErrX` with ghost text (utils/goerrors.lua)
      menu = {
        -- flat: `label  detail` only, no kind-icon column (the detail says what it is); padding is the block's own
        draw = { columns = { { "label", "label_description", gap = 2 } }, padding = { 1, 1 } },
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
        auto_show = true,
        auto_show_delay_ms = 0, -- no wait on select (default is 500 ms)
        window = { border = require("ui.flat").border() },
      },
    },
    signature = {
      enabled = true,
      window = { border = require("ui.flat").border() },
    },
  },
  config = function(_, opts)
    require("blink.cmp").setup(opts)
    require("utils.gosmart").autotrigger()
    require("utils.goerrors").setup()
  end,
}
