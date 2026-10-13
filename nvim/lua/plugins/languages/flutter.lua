-- flutter-tools.nvim (Dart Language Server + Flutter tools).
-- Docs: https://github.com/nvim-flutter/flutter-tools.nvim

--- Capabilities: blink.cmp's if available
local function capabilities()
  local has_blink, blink = pcall(require, "blink.cmp")
  return vim.tbl_deep_extend(
    "force",
    vim.lsp.protocol.make_client_capabilities(),
    has_blink and blink.get_lsp_capabilities({}, false) or {}
  )
end

--- Type colors: native Neovim 0.12+ support (flutter-tools' lsp.color is deprecated)
local function enable_document_colors()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("FlutterDocumentColor", { clear = true }),
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if client and client.name == "dartls" then
        vim.lsp.document_color.enable(true, { bufnr = ev.buf }, { style = "■" })
      end
    end,
  })
end

return {
  "akinsho/flutter-tools.nvim",
  enabled = not vim.tbl_contains(require("core.settings").languages.disabled, "dart"),
  ft = { "dart" },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "saghen/blink.cmp",
  },
  config = function()
    enable_document_colors()

    require("flutter-tools").setup {
      ui = {
        border = "single",
        notification_style = "native",
      },

      decorations = {
        statusline = {
          app_version = true, -- app version in the statusline
          device = true, -- active device
        },
      },

      -- Visual guides for nested widgets
      widget_guides = { enabled = true },

      -- Shows `// ClassName` at the end of the closing parenthesis
      closing_tags = {
        highlight = "Comment",
        prefix = " // ",
        enabled = true,
      },

      dev_log = {
        enabled = true,
        filter = nil,
        open_cmd = "tabedit",
      },

      flutter_path = nil, -- auto-detect from PATH
      flutter_lookup_cmd = nil,

      lsp = {
        capabilities = capabilities(),
        settings = {
          dart = {
            completeFunctionCalls = true,
            showTodos = true,
            analysisExcludedFolders = { ".dart_tool", ".pub-cache" },
            renameFilesWithClasses = "prompt",
            enableSnippets = true,
            updateImportsOnRename = true,
          },
        },
      },

      debugger = {
        enabled = true,
        run_via_dap = true,
        register_configurations = function(_)
          require("dap").configurations.dart = {}
          require("dap.ext.vscode").load_launchjs()
        end,
      },
    }
  end,
}
