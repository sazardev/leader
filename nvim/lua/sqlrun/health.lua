-- ── :checkhealth sqlrun ──────────────────────────────────────────────────────
-- What the SQL menu found: the connection of this project, which client every dialect needs, and what is installed.
-- Read-only: it never starts a database or a client.
local connections = require "sqlrun.connections"
local dialects = require "sqlrun.dialects"
local runner = require "sqlrun.runner"

local M = {}

function M.check()
  vim.health.start "SQL (sqlrun)"
  local root = require("sqlrun").root()
  vim.health.info("Project: " .. root)
  local c = connections.current(root)
  if c then
    vim.health.ok(("Connection: %s · %s · %s"):format(c.name, c.kind, connections.shown(c.target)))
    local list = connections.of(root)
    if #list > 1 then
      vim.health.info(("Found %d connections (the first one is used):"):format(#list))
      for _, item in ipairs(list) do
        vim.health.info(("  %s · %s · %s"):format(item.name, item.kind, connections.shown(item.target)))
      end
    end
  else
    vim.health.warn "No connection: put DATABASE_URL in .env, add a .db/.duckdb file, or use <leader>Qc → New connection"
  end
  if c then
    local d = dialects.get(c.kind)
    local binary = runner.binary(c)
    if vim.fn.executable(binary) == 1 then
      vim.health.ok(("Client: %s"):format(binary))
    else
      vim.health.error(("Client: %s is not installed"):format(binary), { d and d.install or "" })
    end
  end
  local install = {
    sqls = ":MasonInstall sqls",
    sqlfluff = ":MasonInstall sqlfluff",
    ["sql-formatter"] = ":MasonInstall sql-formatter",
  }
  for _, name in ipairs { "sqls", "sqlfluff", "sql-formatter" } do
    if vim.fn.executable(name) == 1 then
      vim.health.ok(name .. " is installed")
    else
      vim.health.warn(name .. " is not installed", { install[name] })
    end
  end
  local clients = vim.lsp.get_clients { name = "sqls" }
  if #clients > 0 then
    vim.health.ok(("sqls: %d client(s) attached"):format(#clients))
  elseif vim.fn.executable "sqls" == 1 then
    vim.health.info "sqls: starts when a .sql buffer opens"
  end
  vim.health.info "Dialects:"
  for _, d in ipairs(dialects.all()) do
    vim.health.info(
      ("  %-10s %-12s client %-8s sqls %-10s SQLFluff %-10s formatter %s"):format(
        d.id,
        d.label,
        d.client,
        d.sqls or "—",
        d.sqlfluff,
        d.formatter
      )
    )
  end
end

return M
