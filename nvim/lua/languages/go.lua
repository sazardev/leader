return {
  filetypes = { "go", "gomod", "gowork" },
  treesitter = { "go", "gomod", "gosum", "gowork" },
  lsp = { "gopls" },
  mason = {
    always = { "goimports", "gofumpt" },
    full = { "gopls", "golangci-lint" },
  },
  formatters = { go = { "goimports", "gofumpt" } }, -- imports first, then strict formatting
  linters = { go = { "golangcilint", "gohawk" } },
  linters_light = { go = { "govet" } }, -- go vet is ephemeral; golangci-lint is heavy

  -- nvim-lint does not ship "govet" out of the box (only "golangcilint"); go vet already comes
  -- with the toolchain, zero extra installation.
  setup_lint = function(lint)
    lint.linters.govet = {
      cmd = "go",
      args = { "vet", "./..." },
      stdin = false,
      ignore_exitcode = true,
      append_fname = false,
      stream = "stderr",
      parser = require("lint.parser").from_errorformat("%f:%l:%c: %m", { source = "govet" }),
    }

    -- golangci-lint from the buffer's module: nvim-lint runs it in Neovim's cwd and hands it the file's folder, so
    -- with a module nested inside the open one (a go.mod below another go.mod) it loads the parent module and exits
    -- 7 ("main module ... does not contain package ...") on every save. The nearest go.mod is the module the file
    -- belongs to; the folder (never the file) gives the package all its files.
    lint.linters.golangcilint = function()
      local base = require "lint.linters.golangcilint"
      local root = vim.api.nvim_buf_get_name(0) ~= "" and vim.fs.root(0, "go.mod") or nil
      if not root or type(base.args) ~= "table" then
        return base
      end
      local args = vim.list_extend({}, base.args)
      args[#args] = function()
        return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h")
      end
      return vim.tbl_extend("force", base, { args = args, cwd = root })
    end

    -- gohawk (utils/gohawk.lua) is a function linter: its module root and package argument depend on the buffer being
    -- linted. nvim-lint calls it again for the run, so the cwd is the current buffer's module and the JSON parser
    -- filters the package's findings to that buffer. Skipped when the binary is missing or lint is off.
    local settings = require "core.settings"
    local gohawk = require "utils.gohawk"
    lint.linters.gohawk = function()
      local cfg = settings.go.gohawk or {}
      local file = vim.api.nvim_buf_get_name(0)
      if cfg.lint == false or file == "" then
        return nil
      end
      local args = { "-json" }
      vim.list_extend(args, cfg.args or {})
      args[#args + 1] = vim.fn.fnamemodify(file, ":h")
      return {
        cmd = "gohawk",
        args = args,
        cwd = gohawk.root(file),
        stdin = false,
        append_fname = false,
        ignore_exitcode = true,
        stream = "stdout",
        parser = function(output, bufnr, cwd)
          return gohawk.diagnostics(output, bufnr, cwd)
        end,
      }
    end
  end,

  menu = { name = "Go", prefix = "g", maps = require "languages.actions.go", groups = { S = "setup" } },
}
