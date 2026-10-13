-- ── Cargador de servidores LSP ───────────────────────────────────────────────
-- La lista de servidores sale de lua/languages/ (campo `lsp`). Los overrides de
-- cada servidor viven en lua/servers/<nombre>.lua y se aplican con
-- vim.lsp.config() (mayor precedencia que lsp/*.lua del runtimepath, donde
-- ganarían los archivos de nvim-lspconfig).
local M = {}

--- Capabilities de NvChad + blink.cmp para todos los clientes
local function configure_defaults()
  -- NvChad define vim.lsp.config("*") con capabilities y on_init (apaga
  -- semantic tokens) y habilita lua_ls. Tomamos sus capabilities como base y
  -- forzamos encima las de blink, preservando on_init.
  require("nvchad.configs.lspconfig").defaults()
  vim.diagnostic.config(require("core.settings").diagnostics) -- NvChad vuelve a activar virtual_text

  local base = vim.lsp.config["*"] or {}
  vim.lsp.config("*", {
    capabilities = vim.tbl_deep_extend(
      "force",
      base.capabilities or vim.lsp.protocol.make_client_capabilities(),
      require("blink.cmp").get_lsp_capabilities({}, false)
    ),
    on_init = base.on_init,
  })
end

--- Overrides del servidor (lua/servers/<name>.lua), si existen
---@param name string
---@return table?
local function overrides(name)
  local module = "servers." .. name
  local ok, cfg = pcall(require, module)
  if ok then
    return cfg
  end
  if not tostring(cfg):find(("module '%s' not found"):format(module), 1, true) then
    require("utils.log").error(("servers.%s: %s"):format(name, cfg))
  end
end

function M.setup()
  local names = require("languages").lsp_servers()
  if #names == 0 then
    return -- modo ligero: ningún LSP residente
  end

  configure_defaults()
  require("servers.on_attach").setup()

  for _, name in ipairs(names) do
    local cfg = overrides(name)
    if cfg then
      vim.lsp.config(name, cfg)
    end
    vim.lsp.enable(name)
  end
end

return M
