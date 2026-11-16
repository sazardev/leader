-- ── What a failed client is telling you (pure) ───────────────────────────────
-- The clients answer a connection problem with a paragraph. The first line is already shown by the runner; this adds
-- the one sentence that says what to do (start the container, check the password, use -C, fix the file path). Tested in
-- test-langs.lua. Deliberately small: a hint, never a second error.
local M = {}

---@type { pattern: string, tip: string }[]
local TIPS = {
  { pattern = "connection refused", tip = "the server is not listening (start it: docker compose up -d db)" },
  {
    pattern = "could not connect to server",
    tip = "the server is not listening (start it or check the host and port)",
  },
  { pattern = "no such host", tip = "the host name in the URL does not resolve" },
  { pattern = "password authentication failed", tip = "wrong user or password: check the URL and .env" },
  { pattern = "no password supplied", tip = "add the password to the URL, or put it in ~/.pgpass" },
  { pattern = "database .- does not exist", tip = "create the database or fix its name in the URL" },
  { pattern = "unknown database", tip = "create the database or fix its name in the URL" },
  { pattern = "access denied for user", tip = "wrong user or password for MySQL/MariaDB" },
  {
    pattern = "can't connect to local mysql server",
    tip = "MySQL/MariaDB is not running (or the socket is not there)",
  },
  { pattern = "unknown mysql server host", tip = "the host name in the URL does not resolve" },
  { pattern = "ssl connection error", tip = "a local server without TLS needs `?ssl-mode=DISABLED`" },
  { pattern = "login failed for user", tip = "wrong user or password for SQL Server" },
  { pattern = "certificate", tip = "trust the dev certificate (`-C`, or `?trustServerCertificate=true`)" },
  { pattern = "unable to open database file", tip = "the SQLite/DuckDB path does not exist or is not writable" },
  { pattern = "database is locked", tip = "another client is writing: try again when it is idle" },
  { pattern = "no such table", tip = "the table is not there (schema or migrations?)" },
}

--- The hint for a client's stderr; nil when nothing is recognized
---@param stderr string?
---@return string?
function M.tip(stderr)
  local text = (stderr or ""):lower()
  for _, item in ipairs(TIPS) do
    if text:find(item.pattern) then
      return item.tip
    end
  end
  return nil
end

--- The first non-empty line of a client's stderr, without the "psql: error:" prefix
---@param stderr string?
---@return string
function M.first_line(stderr)
  for line in (stderr or ""):gmatch "[^\r\n]+" do
    local text = vim.trim(line)
    if text ~= "" then
      return (text:gsub("^%a[%w_.-]*:%s*", ""))
    end
  end
  return ""
end

return M
