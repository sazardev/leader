-- flutter-tools.nvim (Dart Language Server + Flutter tools). Debugging goes through nvim-dap (plugins/tools/dap.lua),
-- code generation through lua/dartgen (build_runner).
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
  -- translations: saving an .arb runs `flutter gen-l10n` (lua/dartgen); dartls still starts only for Dart buffers
  event = { "BufReadPre *.arb", "BufNewFile *.arb" },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "saghen/blink.cmp",
  },
  config = function()
    -- light mode: flutter run, hot reload and the rest stay; the resident language server (dartls) does not start.
    -- flutter-tools starts it from its ftplugin on every Dart buffer, through this one function
    if require("core.light").enabled then
      require("flutter-tools.lsp").attach = function() end
    end
    enable_document_colors()
    require("dartrun").setup()
    -- log "hidden": flutter-tools opens the split at the first line of output unless it believes it already showed it;
    -- the lines go to a hidden buffer instead, and <leader>dl opens it
    if require("core.settings").flutter.log == "hidden" then
      require("flutter-tools.log").shown = true
    end
    require("dartgen").setup()
    require("darttest").setup()
    require("dartpub").setup()
    require("dartgen").check_parts(vim.api.nvim_get_current_buf()) -- the file that loaded the plugin already fired BufReadPost

    require("flutter-tools").setup {
      ui = {
        border = require("ui.flat").border(),
        notification_style = "native",
      },

      decorations = {
        statusline = {
          -- off: our statusline does not show it, and it reads pubspec.yaml on every Dart buffer (a loose .dart file
          -- outside a package got a "We tried to open this file but couldn't" message)
          app_version = false,
          device = true, -- the device the app runs on: the statusline's `▶ device` chip (lua/dartrun)
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

      -- the app's log in a bottom split that does not take the focus (`<leader>dl` toggles it); errors also as notes
      dev_log = {
        enabled = true,
        filter = nil,
        open_cmd = ("botright %dsplit"):format(math.max(8, math.floor(vim.o.lines * 0.3))),
        focus_on_open = false,
        notify_errors = true,
      },

      flutter_path = nil, -- auto-detect from PATH
      -- FVM: the project's own SDK when it has one installed (.fvm/flutter_sdk), the one in PATH otherwise
      fvm = vim.uv.fs_stat(vim.fn.getcwd() .. "/.fvm/flutter_sdk") ~= nil,
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

      -- run and debug through nvim-dap: breakpoints work in any run. flutter-tools registers "Launch flutter"
      -- (lib/main.dart, or the target of the project config); never empty its configurations, or nothing launches
      debugger = {
        enabled = true,
        run_via_dap = true,
      },
    }
  end,
}
