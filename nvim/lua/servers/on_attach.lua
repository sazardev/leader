-- ── Keymaps y etiquetas extra al adjuntar un servidor LSP ────────────────────
local M = {}

--- Nombra el grupo <leader>r (NvChad: <leader>ra = renamer) salvo que el buffer
--- ya tenga un menú contextual con ese prefijo (p. ej. Rust).
local function label_rename_group(buf)
  if (vim.b[buf].menu_contexts or {}).r then
    return
  end
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add { { "<leader>r", group = "Rename", buffer = buf } }
  end
end

--- Keymaps buffer-locales que se crean al adjuntar un servidor: { lhs, fn, desc }.
--- El generador del cheatsheet (utils/cheatsheet.lua) lee esta misma lista.
---@return table[]
function M.keymaps()
  local lsp = require "utils.lsp"
  return {
    -- NvChad v2.5 no mapea code actions
    { "<leader>ca", vim.lsp.buf.code_action, "LSP code action" },
    -- Navegación con mensajes claros y selector de Telescope. grr es la tecla
    -- estándar de Neovim 0.11+ (por defecto abre quickfix)
    { "gd", lsp.goto_definition, "LSP go to DEFINITION" },
    { "grr", lsp.references, "LSP see WHERE IT'S USED (list)" },
  }
end

function M.setup()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("LspExtraKeymaps", { clear = true }),
    callback = function(args)
      for _, m in ipairs(M.keymaps()) do
        vim.keymap.set("n", m[1], m[2], { buffer = args.buf, desc = m[3] })
      end
      label_rename_group(args.buf)
    end,
  })
end

return M
