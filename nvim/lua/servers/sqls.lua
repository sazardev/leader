-- The connections come from the project (lua/sqlrun/connections.lua: DATABASE_URL in .env or the environment, the
-- SQLite files under the root, `settings.sql.connections`), so completion knows the real tables and columns. Without
-- any it still completes keywords. A config.yml at the root (sqls' own) wins.
return {
  root_markers = { "config.yml", ".env", ".git" },
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
