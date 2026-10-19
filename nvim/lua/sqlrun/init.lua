-- ── Running SQL (<leader>Q) ──────────────────────────────────────────────────
-- The statement under the cursor, a selection or the whole file goes to the project's connection (connections.lua):
-- psql for PostgreSQL, sqlite3 for SQLite, never a resident process. The result lands in one split (`sql://results`:
-- the connection, how long it took, the rows as the client draws them; `r` runs it again, `q` closes). A statement that
-- drops or changes data with no limit (statement.lua `risky`) asks first; EXPLAIN ANALYZE, which runs the statement,
-- only runs a read without asking. Knobs in `settings.sql`.
local connections = require "sqlrun.connections"
local statement = require "sqlrun.statement"
local log = require "utils.log"

local M = {}

---@return table
local function cfg()
  return require("core.settings").sql or {}
end

--- The project of the current buffer
---@return string
function M.root()
  local dir = require("utils.project").file_dir()
  return vim.fs.root(dir ~= "" and dir or vim.fn.getcwd(), { ".env", ".git" }) or dir
end

--- The dialect of the current project's connection (what the formatter speaks): "sqlite" or "postgres"
---@return "postgres"|"sqlite"
function M.dialect()
  local c = connections.current(M.root())
  return c and c.kind or (cfg().dialect == "sqlite" and "sqlite" or "postgres")
end

--- The client command for a connection (pure)
---@param c SqlConnection
---@return string[]
function M.command(c)
  if c.kind == "postgres" then
    return { "psql", c.target, "-X", "-v", "ON_ERROR_STOP=1", "-P", "pager=off", "-P", "null=∅" }
  end
  return { "sqlite3", "-bail", "-header", "-box", c.target }
end

local last ---@type { text: string, c: SqlConnection, label: string }?

---@param lines string[]
---@return integer buf
local function show(lines)
  local name = "sql://results"
  local buf = vim.fn.bufnr(name)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, name)
    vim.bo[buf].bufhidden = "hide"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, desc = "SQL close results" })
    vim.keymap.set("n", "r", function()
      M.again()
    end, { buffer = buf, nowait = true, desc = "SQL run again" })
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if vim.fn.bufwinid(buf) == -1 then
    local from = vim.api.nvim_get_current_win()
    vim.cmd(("botright %dsplit"):format(cfg().results_height or 15))
    vim.api.nvim_win_set_buf(0, buf)
    vim.wo.wrap, vim.wo.number, vim.wo.relativenumber = false, false, false
    if vim.api.nvim_win_is_valid(from) then -- a picker that opened the run may be gone by now
      vim.api.nvim_set_current_win(from)
    end
  end
  return buf
end

--- Sends `text` to the connection and shows what came back
---@param text string
---@param c SqlConnection
---@param label string what ran ("statement", "selection", "file", "explain")
local function send(text, c, label)
  if vim.fn.executable(M.command(c)[1]) ~= 1 then
    return log.warn(("SQL: %s is not installed"):format(M.command(c)[1]))
  end
  last = { text = text, c = c, label = label }
  local head = ("-- %s · %s · %s"):format(c.name, connections.shown(c.target), label)
  show { head, "-- running…" }
  local t0 = vim.uv.hrtime()
  vim.system(M.command(c), { stdin = text, text = true, timeout = cfg().timeout_ms or 30000 }, function(res)
    vim.schedule(function()
      local ms = math.floor((vim.uv.hrtime() - t0) / 1e6)
      local ok = res.code == 0
      local lines = { ("%s · %s · %d ms"):format(head, ok and "ok" or ("failed (" .. res.code .. ")"), ms), "" }
      for _, l in ipairs(vim.split(vim.trim((res.stdout or "") .. "\n" .. (res.stderr or "")), "\n", { plain = true })) do
        lines[#lines + 1] = l
      end
      show(lines)
      if not ok then
        log.warn("SQL: " .. (vim.trim(res.stderr or ""):match "[^\n]+" or "the statement failed"))
      end
    end)
  end)
end

--- The connection to use, or a warning that says how to get one
---@return SqlConnection?
local function connection()
  local c = connections.current(M.root())
  if not c then
    log.warn "SQL: no connection: put DATABASE_URL in .env, add a .db file, or set settings.sql.connections"
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
  local text
  if c.kind == "sqlite" then
    text = "EXPLAIN QUERY PLAN " .. s.text .. ";"
  else
    text = (analyze and "EXPLAIN (ANALYZE, BUFFERS) " or "EXPLAIN ") .. s.text .. ";"
  end
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
    send(c.kind == "postgres" and "\\dt+" or ".tables", c, "tables")
  end
end

--- <leader>Qd: the table under the cursor, described
function M.describe()
  local c = connection()
  local name = vim.fn.expand "<cword>"
  if c and name ~= "" then
    send(c.kind == "postgres" and ("\\d+ " .. name) or (".schema " .. name), c, "describe " .. name)
  end
end

--- <leader>Qc: the connection of this project, picked from what was found
function M.pick()
  local root = M.root()
  local list = connections.of(root)
  if #list == 0 then
    return connection()
  end
  local current = connections.current(root)
  require("tasks.picker").choose(
    vim.tbl_map(function(c)
      return {
        label = (current and c.target == current.target and "● " or "  ") .. c.name,
        desc = c.kind .. " · " .. connections.shown(c.target),
        value = c,
      }
    end, list),
    { title = "SQL connection · " .. vim.fn.fnamemodify(root, ":~"), width = 34 },
    function(c)
      connections.choose(root, c)
      log.info(("SQL: %s (%s)"):format(c.name, c.kind))
    end
  )
end

--- `r` in the results: the last run again
function M.again()
  if not last then
    return log.info "SQL: nothing ran yet"
  end
  send(last.text, last.c, last.label)
end

return M
