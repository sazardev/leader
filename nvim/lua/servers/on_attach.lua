-- ── Extra keymaps and labels when attaching an LSP server ────────────────────
local M = {}

--- Names the <leader>r group (NvChad: <leader>ra = renamer) unless the buffer
--- already has a contextual menu with that prefix (e.g. Rust).
local function label_rename_group(buf)
  if (vim.b[buf].menu_contexts or {}).r then
    return
  end
  local ok, wk = pcall(require, "which-key")
  if ok then
    wk.add { { "<leader>r", group = "Rename", buffer = buf } }
  end
end

--- Buffer-local keymaps created when a server attaches: { lhs, fn, desc }.
--- The cheatsheet generator (utils/cheatsheet.lua) reads this same list.
---@return table[]
function M.keymaps()
  local lsp = require "utils.lsp"
  return {
    -- NvChad v2.5 does not map code actions
    { "<leader>ca", vim.lsp.buf.code_action, "LSP code action" },
    -- Navigation with clear messages and a Telescope picker. grr is the
    -- standard Neovim 0.11+ key (opens quickfix by default)
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
