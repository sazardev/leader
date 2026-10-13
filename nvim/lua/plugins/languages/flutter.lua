-- flutter-tools.nvim (Dart Language Server + herramientas Flutter).
-- Docs: https://github.com/nvim-flutter/flutter-tools.nvim

--- Capabilities: las de blink.cmp si está disponible
local function capabilities()
  local has_blink, blink = pcall(require, "blink.cmp")
  return vim.tbl_deep_extend(
    "force",
    vim.lsp.protocol.make_client_capabilities(),
    has_blink and blink.get_lsp_capabilities({}, false) or {}
  )
end

--- Colores de tipo: soporte nativo de Neovim 0.12+ (lsp.color de flutter-tools está deprecado)
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
          app_version = true, -- versión de la app en statusline
          device = true, -- dispositivo activo
        },
      },

      -- Guías visuales para widgets anidados
      widget_guides = { enabled = true },

      -- Muestra `// ClassName` al final del paréntesis de cierre
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

      flutter_path = nil, -- auto-detect desde PATH
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
