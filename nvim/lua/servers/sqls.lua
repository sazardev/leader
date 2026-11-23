-- The connections come from the project (lua/sqlrun/connections.lua: the ones added with <leader>Qn, DATABASE_URL in
-- .env or the environment, the SQLite/DuckDB files, `settings.sql.connections`), so completion knows the real tables and
-- columns and the picked connection is sqls' default. sqls speaks PostgreSQL, MySQL, MariaDB, SQLite and SQL Server;
-- DuckDB has no driver (it still completes keywords). A config.yml at the root (sqls' own) wins.
local MARKERS = {
  "config.yml",
  ".env",
  ".git",
  ".sqlfluff",
  "compose.yaml",
  "docker-compose.yml",
  "Makefile",
  "package.json",
  "pyproject.toml",
  "go.mod",
  "Cargo.toml",
}

local function lsp()
  return require "sqlrun.lsp"
end

--- sqls tells the editor it could not connect through window/showMessage. Mask any DSN in the message, record the
--- failure for the chip/info/health, then show the original (now safe) message.
local function show_message(err, result, ctx, config)
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  local root = client and client.config.root_dir or require("sqlrun").root()
  local raw = type(result) == "table" and result.message or tostring(result or "")
  local message = lsp().redact(raw)
  if message:lower():find("database connection", 1, true) or message:lower():find("establish a connection", 1, true) then
    local previous = lsp().get(root)
    if previous.status == "error" and previous.detail == message then
      return -- the same reason is already on the chip and in :Sql info
    end
    lsp().set(root, { status = "error", detail = message })
  end
  local shown = type(result) == "table" and vim.deepcopy(result) or {}
  shown.message = message
  local default = vim.lsp.handlers["window/showMessage"]
  return default(err, shown, ctx, config)
end

return {
  root_markers = MARKERS,
  -- A lone .sql file in a folder with no marker still gets a server: the file's own folder is the workspace.
  root_dir = function(bufnr, on_dir)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then
      return
    end
    local dir = vim.fs.dirname(vim.fn.fnamemodify(name, ":p"))
    on_dir(vim.fs.root(dir, MARKERS) or dir)
  end,
  -- A missing binary is a normal laptop state: don't let LspStart spam an error on every .sql buffer.
  enabled = function()
    return vim.fn.executable "sqls" == 1
  end,
  handlers = { ["window/showMessage"] = show_message },
  before_init = function(params, config)
    local root = config.root_dir
    if not root then
      return
    end
    if vim.uv.fs_stat(root .. "/config.yml") then
      lsp().set(root, { status = "starting", detail = "config.yml" }) -- the server's own config wins
      return
    end
    local connections = require "sqlrun.connections"
    local list = connections.sqls(root)
    local missing = connections.missing(root)
    if #list == 0 then
      local detail = missing and ("file not found: " .. vim.fn.fnamemodify(missing, ":~"))
        or (#connections.of(root) == 0 and "no connection in this project" or "no sqls driver for this dialect")
      lsp().set(root, { status = "error", detail = detail })
      return
    end
    config.settings = vim.tbl_deep_extend("force", config.settings or {}, { sqls = { connections = list } })
    -- sqls connects at `initialize` only from initializationOptions.connectionConfig; otherwise it answers
    -- "no database connection" until it gets a workspace/didChangeConfiguration notification (see on_attach).
    -- `params` (not config.init_options) is what goes on the wire: Neovim copies init_options into init_params
    -- BEFORE before_init runs, so changing config.init_options here would be too late.
    params.initializationOptions = vim.tbl_deep_extend("force", params.initializationOptions or {}, {
      connectionConfig = list[1],
    })
    lsp().set(root, {
      status = "starting",
      detail = list[1].alias
        .. (missing and (" · skipped missing " .. vim.fn.fnamemodify(missing, ":~")) or ""),
    })
  end,
  -- Neovim does not send workspace/didChangeConfiguration on attach, and sqls reads its connections ONLY from that
  -- notification (config.settings is never pushed to it). Without this, completion has no real tables or columns.
  on_attach = function(client)
    local root = client.config.root_dir
    local settings = client.config.settings
    if type(settings) == "table" and settings.sqls then
      client:notify("workspace/didChangeConfiguration", { settings = settings })
      if root then
        local detail = settings.sqls.connections[1] and settings.sqls.connections[1].alias or ""
        local missing = require("sqlrun.connections").missing(root)
        if missing then
          detail = detail .. " · skipped missing " .. vim.fn.fnamemodify(missing, ":~")
        end
        lsp().set(root, { status = "connected", detail = detail })
      end
    elseif root then
      local current = lsp().get(root)
      if current.status == "starting" and current.detail == "config.yml" then
        lsp().set(root, { status = "connected", detail = "config.yml" }) -- its own config connected it
      elseif current.status == "off" then
        lsp().set(root, { status = "unsupported", detail = "keywords only" })
      end
    end
  end,
}
