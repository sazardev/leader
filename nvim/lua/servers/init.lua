-- ── LSP server loader ────────────────────────────────────────────────────────
-- The server list comes from lua/languages/ (`lsp` field). Each server's overrides
-- live in lua/servers/<name>.lua and are applied with
-- vim.lsp.config() (higher precedence than lsp/*.lua in the runtimepath, where
-- nvim-lspconfig's files would win).
local M = {}

--- NvChad + blink.cmp capabilities for all clients
local function configure_defaults()
  -- NvChad defines vim.lsp.config("*") with capabilities and on_init (turns off
  -- semantic tokens) and enables lua_ls. We take its capabilities as a base and
  -- force blink's on top, preserving on_init.
  require("nvchad.configs.lspconfig").defaults()
  vim.diagnostic.config(require("core.settings").diagnostics) -- NvChad re-enables virtual_text

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

--- Server overrides (lua/servers/<name>.lua), if they exist
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
    return -- light mode: no resident LSP
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
