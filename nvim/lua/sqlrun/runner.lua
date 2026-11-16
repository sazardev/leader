-- ── Running a SQL client ─────────────────────────────────────────────────────
-- One place that turns a connection into a process: the dialect builds the argv (and the environment the password
-- travels in), this checks the binary, sets the timeout and the project as cwd, and hands back the handle so a query
-- can be stopped. `text` reads the statement from stdin; `query` asks for the tab-separated shape used by the schema
-- browser. Nothing here touches the UI (init.lua and schema.lua decide what to show).
local dialects = require "sqlrun.dialects"

local M = {}

---@return table
local function cfg()
  return require("core.settings").sql or {}
end

--- The client binary that is installed for a connection
---@param c SqlConnection
---@return string
function M.binary(c)
  return dialects.binary(c.kind)
end

--- The install hint of a connection's dialect
---@param c SqlConnection
---@return string
function M.install(c)
  local d = dialects.get(c.kind)
  return d and d.install or ""
end

---@param c SqlConnection
---@param spec { cmd: string[], env: table<string, string>? }?
---@param opts { stdin: string?, timeout: integer?, cwd: string? }
---@param cb fun(res: vim.SystemCompleted)
---@return vim.SystemObj? handle, string? problem
function M.spawn(c, spec, opts, cb)
  if not spec then
    return nil, "the client command could not be built"
  end
  local binary = spec.cmd[1]
  if vim.fn.executable(binary) ~= 1 then
    return nil, binary .. " is not installed"
  end
  return vim.system(spec.cmd, {
    stdin = opts.stdin,
    text = true,
    env = spec.env,
    timeout = opts.timeout or cfg().timeout_ms or 30000,
    cwd = opts.cwd,
  }, cb)
end

--- Runs a statement through the interactive client (the result is drawn by psql/sqlite3/mysql/sqlcmd)
---@param c SqlConnection
---@param text string
---@param opts { cwd: string?, timeout: integer? }
---@param cb fun(res: vim.SystemCompleted)
---@return vim.SystemObj? handle, string? problem
function M.text(c, text, opts, cb)
  local d = dialects.get(c.kind)
  if not d then
    return nil, "unknown dialect " .. c.kind
  end
  local binary = M.binary(c)
  local spec, problem = d.command(c, binary)
  if not spec then
    return nil, problem
  end
  return M.spawn(c, spec, { stdin = text, timeout = opts.timeout, cwd = opts.cwd }, cb)
end

--- Runs SQL for the schema browser: one tab-separated row per line
---@param c SqlConnection
---@param sql string
---@param opts { cwd: string?, timeout: integer? }
---@param cb fun(res: vim.SystemCompleted)
---@return vim.SystemObj? handle, string? problem
function M.query(c, sql, opts, cb)
  local d = dialects.get(c.kind)
  if not d then
    return nil, "unknown dialect " .. c.kind
  end
  local binary = M.binary(c)
  local spec, problem = d.query(c, sql, binary)
  if not spec then
    return nil, problem
  end
  return M.spawn(c, spec, { timeout = opts.timeout or 15000, cwd = opts.cwd }, cb)
end

return M
