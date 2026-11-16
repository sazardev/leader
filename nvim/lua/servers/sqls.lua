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
  before_init = function(_, config)
    if not config.root_dir or vim.uv.fs_stat(config.root_dir .. "/config.yml") then
      return
    end
    local list = require("sqlrun.connections").sqls(config.root_dir)
    if #list > 0 then
      config.settings = vim.tbl_deep_extend("force", config.settings or {}, { sqls = { connections = list } })
    end
  end,
}
