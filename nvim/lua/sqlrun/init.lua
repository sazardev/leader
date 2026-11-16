-- ── Running SQL (<leader>Q) ──────────────────────────────────────────────────
-- The statement under the cursor, a selection or the whole file goes to the project's connection. The dialect is the
-- connection's (sqlrun/dialects): psql for PostgreSQL, sqlite3 for SQLite, mysql/mariadb, sqlcmd for SQL Server, duckdb
-- for DuckDB. The result lands in one split (`sql://results`: the connection, how long it took, the rows as the client
-- draws them; `r` runs it again, `q` closes, `<C-y>` copies). A statement that drops or changes data with no limit
-- (statement.lua `risky`) asks first; EXPLAIN ANALYZE, which runs the statement, only runs a read without asking.
-- Connections, the schema browser, history, SQLFluff, the info panel and the statusline chip hang off this module.
-- Knobs in `settings.sql`.
local connections = require "sqlrun.connections"
local diagnose = require "sqlrun.diagnose"
local dialects = require "sqlrun.dialects"
local history = require "sqlrun.history"
local info = require "sqlrun.info"
local results = require "sqlrun.results"
local runner = require "sqlrun.runner"
local schema = require "sqlrun.schema"
local statement = require "sqlrun.statement"
local log = require "utils.log"

local M = {}

---@return table
local function cfg()
  return require("core.settings").sql or {}
end

---@return integer
local function now_ms()
  return vim.uv.now()
end

--- The project of the current buffer. A panel (`sql://info`, `:checkhealth`) has no file: the working folder is the
--- project there, not the URI's "directory".
---@return string
function M.root()
  local name = vim.api.nvim_buf_get_name(0)
  local dir
  if name ~= "" and not name:match "^%a[%w+.-]*://" then
    dir = vim.fn.fnamemodify(name, ":p:h")
  else
    dir = vim.fn.getcwd()
  end
  return vim.fs.root(dir, {
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
  }) or dir
end

--- The dialect of the current project's connection, or the fallback from `settings.sql.dialect`
---@return SqlDialect
function M.dialect_info()
  local c = connections.current(M.root())
  return (c and dialects.get(c.kind)) or dialects.fallback()
end

--- The dialect id ("postgres", "sqlite", "mysql", "mariadb", "sqlserver", "duckdb")
---@return string
function M.dialect()
  return M.dialect_info().id
end

--- What sql-formatter calls it
---@return string
function M.formatter_dialect()
  return M.dialect_info().formatter
end

--- What SQLFluff calls it
---@return string
function M.linter_dialect()
  return M.dialect_info().sqlfluff
end

--- The client command of a connection (pure-ish; the binary is the one that is installed)
---@param c SqlConnection
---@return { cmd: string[], env: table<string, string>? }?, string?
function M.command(c)
  local d = dialects.get(c.kind)
  if not d then
    return nil, "unknown dialect " .. tostring(c.kind)
  end
  return d.command(c, runner.binary(c))
end

local last ---@type { text: string, c: SqlConnection, label: string }?
local handle ---@type vim.SystemObj?
local running = false
local stopping = false
local run_id = 0
local last_ok = true
local last_at = 0
local last_root = nil
local status_cache = { root = nil, at = 0, text = "" }

--- The connection to use, or a warning that says how to get one
---@return SqlConnection?
local function connection()
  local c = connections.current(M.root())
  if not c then
    log.warn "SQL: no connection: put DATABASE_URL in .env, add a .db/.duckdb file, or use <leader>Qc → New connection"
  end
  return c
end

--- Runs after a question when the statement drops or changes data with no limit
---@param text string
---@param go fun()
local function guarded(text, go)
  local why = cfg().confirm_risky ~= false and statement.risky(text)
  if not why then
    return go()
  end
  local modal = require "utils.modal"
  modal.confirm({
    { { (why:gsub("^%l", string.upper)), modal.hl.file } }, -- "A DELETE with no WHERE removes every row"
    { { (text:gsub("%s+", " ")):sub(1, 120), modal.hl.muted } },
  }, { title = "Run it?", confirm = "Run", danger = true }, go)
end

--- Sends `text` to the connection and shows what came back
---@param text string
---@param c SqlConnection
---@param label string what ran ("statement", "selection", "file", "explain")
local function send(text, c, label)
  if not text or vim.trim(text) == "" then
    return
  end
  if handle then
    pcall(function()
      handle:kill(15)
    end)
    handle = nil
  end
  last = { text = text, c = c, label = label }
  running = true
  stopping = false
  run_id = run_id + 1
  local this_run = run_id
  local d = dialects.get(c.kind)
  local head = ("-- %s · %s · %s · %s"):format(c.name, d and d.label or c.kind, connections.shown(c.target), label)
  results.show { name = "sql://results", lines = { head, "-- running…" }, rerun = M.again }
  local t0 = vim.uv.hrtime()
  local root = M.root()
  local obj, problem = runner.text(c, text, { cwd = root }, function(res)
    vim.schedule(function()
      if this_run ~= run_id then -- a newer run already replaced this one (or it was stopped)
        return
      end
      running = false
      handle = nil
      local was_stopped = stopping
      stopping = false
      local ms = math.floor((vim.uv.hrtime() - t0) / 1e6)
      local ok = res.code == 0
      if not was_stopped then
        last_ok = ok
        last_at = now_ms()
        last_root = root
      end
      local lines = {
        ("%s · %s · %d ms"):format(
          head,
          was_stopped and "stopped" or (ok and "ok" or ("failed (" .. tostring(res.code) .. ")")),
          ms
        ),
        "",
      }
      for _, line in ipairs(results.split((res.stdout or "") .. "\n" .. (res.stderr or ""))) do
        lines[#lines + 1] = line
      end
      results.show { name = "sql://results", lines = lines, rerun = M.again }
      if was_stopped then
        return
      end
      history.record(root, {
        text = text,
        label = label,
        connection = c.name,
        kind = c.kind,
        ok = ok,
        ms = ms,
        at = os.time(),
      })
      if not ok then
        local first = diagnose.first_line(res.stderr)
        local tip = diagnose.tip(res.stderr)
        log.warn("SQL: " .. (first ~= "" and first or "the statement failed") .. (tip and (" · " .. tip) or ""))
      end
    end)
  end)
  handle = obj
  if not obj then
    running = false
    last_ok = false
    last_at = now_ms()
    last_root = root
    local tip = runner.install(c)
    results.show {
      name = "sql://results",
      lines = { head, "", "-- " .. (problem or "could not start the client") .. (tip ~= "" and ("\n-- " .. tip) or "") },
      rerun = M.again,
    }
    log.warn("SQL: " .. (problem or "could not start the client") .. (tip ~= "" and (" · " .. tip) or ""))
  end
end

--- Stops the query or the schema query that is running
function M.stop()
  if not handle then
    return log.info "SQL: nothing is running"
  end
  stopping = true
  pcall(function()
    handle:kill(15)
  end)
  handle = nil
  log.info "SQL: stopped"
end

---@return string[]
local function buffer_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

--- <leader>Qr: the statement under the cursor (in visual mode: the selection)
function M.run()
  local c = connection()
  if not c then
    return
  end
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local text = table.concat(vim.fn.getregion(vim.fn.getpos "v", vim.fn.getpos ".", { type = mode }), "\n")
    vim.api.nvim_feedkeys(vim.keycode "<Esc>", "nx", false)
    return guarded(text, function()
      send(text, c, "selection")
    end)
  end
  local s = statement.at(buffer_lines(), vim.api.nvim_win_get_cursor(0)[1])
  if not s then
    return log.info "SQL: no statement here"
  end
  guarded(s.text, function()
    send(s.text .. ";", c, ("statement, lines %d-%d"):format(s.first, s.last))
  end)
end

--- <leader>Qa: the whole file
function M.run_file()
  local c = connection()
  if not c then
    return
  end
  local text = table.concat(buffer_lines(), "\n")
  local risky
  for _, s in ipairs(statement.split(buffer_lines())) do
    risky = risky or statement.risky(s.text) and s.text
  end
  guarded(risky or "", function()
    send(text, c, "file")
  end)
end

--- Runs a text as if it were the statement under the cursor (history, an agent, another plugin)
---@param text string
function M.run_text(text)
  local c = connection()
  if c then
    guarded(text, function()
      send(text, c, "history")
    end)
  end
end

--- <leader>Qe / QE: the plan of the statement under the cursor (ANALYZE runs it: only a read, or after a question)
---@param analyze boolean?
function M.explain(analyze)
  local c = connection()
  if not c then
    return
  end
  local s = statement.at(buffer_lines(), vim.api.nvim_win_get_cursor(0)[1])
  if not s then
    return log.info "SQL: no statement here"
  end
  local d = dialects.get(c.kind)
  local text = d.explain(c, s.text, analyze)
  local go = function()
    send(text, c, analyze and "explain analyze" or "explain")
  end
  if analyze and not statement.reads(s.text) then
    local modal = require "utils.modal"
    return modal.confirm({
      { { "EXPLAIN ANALYZE runs the statement", modal.hl.file } },
      { { "It is not a read: its changes happen", modal.hl.muted } },
    }, { title = "Run it?", confirm = "Run", danger = true }, go)
  end
  go()
end

--- <leader>Qt: the tables of the connection
function M.tables()
  local c = connection()
  if c then
    send(dialects.get(c.kind).tables(c), c, "tables")
  end
end

--- <leader>Qd: the table under the cursor, described
function M.describe()
  local c = connection()
  local name = vim.fn.expand "<cword>"
  if c and name ~= "" then
    send(dialects.get(c.kind).describe(c, name), c, "describe " .. name)
  end
end

--- <leader>Qs: the schema browser (tables → columns)
function M.schema()
  local c = connection()
  if c then
    schema.pick(c, M.root())
  end
end

--- <leader>Qi: what this project has (connection, dialect, tools, keys)
function M.info()
  local root = M.root()
  results.show {
    name = "sql://info",
    lines = info.lines(connections.current(root), root),
    filetype = "markdown",
    rerun = M.info,
  }
end

--- <leader>Qh: what ran in this project
function M.history()
  history.pick(M.root())
end

--- <leader>Qp: a round trip to the database, so a broken connection says so now
function M.ping()
  local c = connection()
  if c then
    send(dialects.get(c.kind).ping(c), c, "ping")
  end
end

--- <leader>QF: SQLFluff's fixes on the buffer (dialect from the connection)
function M.fix()
  if vim.fn.executable "sqlfluff" ~= 1 then
    return log.warn "SQL: sqlfluff is not installed (:MasonInstall sqlfluff · pipx install sqlfluff)"
  end
  if not vim.bo.modifiable then
    return log.warn "SQL: the buffer is not modifiable"
  end
  local d = M.dialect_info()
  local cmd = { "sqlfluff", "fix", "-", "--dialect", d.sqlfluff, "--nocolor", "--disable-progress-bar" }
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" then
    vim.list_extend(cmd, { "--stdin-filename", name })
  end
  local text = table.concat(buffer_lines(), "\n") .. "\n"
  local res = vim
    .system(cmd, {
      stdin = text,
      text = true,
      cwd = M.root(),
      timeout = cfg().timeout_ms or 30000,
    })
    :wait()
  local fixed = res.stdout or ""
  if fixed == "" or fixed == text then
    if res.code ~= 0 then
      local first = diagnose.first_line(res.stderr)
      return log.warn("SQL: SQLFluff: " .. (first ~= "" and first or "it could not fix the buffer"))
    end
    return log.info "SQL: SQLFluff had nothing to fix"
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local fixed_lines = vim.split(fixed:gsub("\r\n", "\n"), "\n", { plain = true })
  while #fixed_lines > 0 and fixed_lines[#fixed_lines] == "" do
    table.remove(fixed_lines)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, fixed_lines)
  pcall(vim.api.nvim_win_set_cursor, 0, { math.min(pos[1], vim.api.nvim_buf_line_count(0)), pos[2] })
  log.info "SQL: SQLFluff fixed the buffer"
end

--- Lips the sqls server of this buffer so the next start reads the connection that was just picked
local function restart_sqls()
  local buf = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients { bufnr = buf, name = "sqls" }
  if #clients == 0 then
    return
  end
  for _, client in ipairs(clients) do
    client:stop(true)
  end
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "sql" then
      vim.lsp.enable("sqls", true)
      vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
    end
  end, 300)
end

--- <leader>Qn / <leader>Qc → New connection: adds a project connection (state dir, never .env)
---@param project string?
function M.new_connection(project)
  local root = project or M.root()
  local modal = require "utils.modal"
  modal.input({
    { { "Paste a DATABASE_URL or a SQLite/DuckDB file.", modal.hl.muted } },
    { { "postgres://app@localhost/app · mysql://… · sqlserver://… · data/app.db", modal.hl.muted } },
    "",
  }, { title = "New SQL connection", confirm = "Use" }, function(text)
    if text == "" then
      return
    end
    local c, problem = connections.add(root, text)
    if not c then
      return log.warn("SQL: " .. (problem or "could not add the connection"))
    end
    connections.choose(root, c)
    status_cache = { root = nil, at = 0, text = "" }
    last_ok, last_at = true, 0
    restart_sqls()
    log.info(("SQL: added %s (%s)"):format(c.name, c.kind))
  end)
end

---@param c SqlConnection
---@param root string
local function remove_connection(c, root)
  local modal = require "utils.modal"
  modal.confirm({
    { { "Remove this connection from the project?", modal.hl.file } },
    { { ("%s · %s"):format(c.name, connections.shown(c.target)), modal.hl.muted } },
    { { "Only connections added with <leader>Qn are removed; .env and settings stay as they are.", modal.hl.muted } },
  }, { title = "Remove connection", confirm = "Remove", danger = true }, function()
    if not connections.remove(root, c.target) then
      return log.warn "SQL: that connection comes from .env or settings, not from <leader>Qn"
    end
    status_cache = { root = nil, at = 0, text = "" }
    last_ok, last_at = true, 0
    restart_sqls()
    log.info("SQL: removed " .. c.name)
  end)
end

--- <leader>Qc: the connection of this project, picked from what was found (and the way to add one)
function M.pick()
  local root = M.root()
  local list = connections.of(root)
  local current = connections.current(root)
  local items = {}
  for _, c in ipairs(list) do
    local d = dialects.get(c.kind)
    items[#items + 1] = {
      label = (current and c.target == current.target and "● " or "  ") .. c.name,
      desc = (d and d.label or c.kind) .. " · " .. connections.shown(c.target) .. " · " .. c.source,
      value = c,
      search = connections.shown(c.target),
    }
  end
  items[#items + 1] =
    { label = "  New connection…", desc = "paste a URL or a SQLite/DuckDB file", value = { new = true } }
  require("tasks.picker").choose(items, {
    title = "SQL connection · " .. vim.fn.fnamemodify(root, ":~"),
    width = 30,
    hint = "Enter use · C-x remove (only the ones added here)",
    maps = {
      {
        "<C-x>",
        function(value)
          if not value.new then
            remove_connection(value, root)
          end
        end,
      },
    },
  }, function(value)
    if value.new then
      return M.new_connection(root)
    end
    connections.choose(root, value)
    status_cache = { root = nil, at = 0, text = "" }
    last_ok, last_at = true, 0
    restart_sqls()
    log.info(("SQL: %s (%s)"):format(value.name, value.kind))
  end)
end

--- `r` in the results: the last run again
function M.again()
  if not last then
    return log.info "SQL: nothing ran yet"
  end
  send(last.text, last.c, last.label)
end

--- The statusline chip: "PG app", "PG app …" while it runs, "PG app ✗" for a minute after it failed
---@return string
function M.statusline()
  local text, _ = M.statusline_state()
  return text
end

--- The highlight group of the chip
---@return string
function M.statusline_group()
  local _, group = M.statusline_state()
  return group or "SqlStatus"
end

---@return string, string
function M.statusline_state()
  if vim.bo.filetype ~= "sql" then
    return "", "SqlStatus"
  end
  local root = M.root()
  local now = now_ms()
  if status_cache.root ~= root or now - status_cache.at > 3000 then
    local c = connections.current(root)
    status_cache = {
      root = root,
      at = now,
      text = c and connections.short(c) or "SQL ?",
    }
  end
  local text = status_cache.text
  if running then
    return text .. " …", "SqlRunning"
  end
  if not last_ok and last_root == root and now - last_at < 60000 then
    return text .. " ✗", "SqlFailed"
  end
  return text, "SqlStatus"
end

--- Called by the FileType autocmd: loads the module (and the chip) for a SQL buffer
function M.attach()
  return true
end

--- `:Sql [run|file|explain|analyze|tables|describe|schema|connections|info|history|ping|fix|format|stop]`
---@param fargs string[]?
function M.sql_command(fargs)
  fargs = fargs or {}
  local sub = fargs[1] or "info"
  if sub == "explain" and fargs[2] == "analyze" then
    return M.explain(true)
  end
  local map = {
    run = M.run,
    file = M.run_file,
    explain = function()
      M.explain(false)
    end,
    analyze = function()
      M.explain(true)
    end,
    tables = M.tables,
    describe = M.describe,
    schema = M.schema,
    connections = M.pick,
    connection = M.pick,
    info = M.info,
    history = M.history,
    ping = M.ping,
    fix = M.fix,
    format = function()
      require("utils.actions").format()
    end,
    stop = M.stop,
    new = M.new_connection,
  }
  local fn = map[sub]
  if not fn then
    return log.warn(
      ("SQL: unknown command %q (run, file, explain, analyze, tables, describe, schema, connections, info, history, ping, fix, format, stop)"):format(
        sub
      )
    )
  end
  fn()
end

return M
