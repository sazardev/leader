-- ── SQL connections of a project ─────────────────────────────────────────────
-- Found, never asked: the connections added to the project (`<leader>Qn`, kept in the state dir), `settings.sql.connections`,
-- the URLs in the project's .env files (DATABASE_URL and any *_DATABASE_URL / *_DB_URL / MYSQL_URL / MSSQL_URL…) and
-- the environment's DATABASE_URL, then the SQLite/DuckDB files under the root. The dialect comes from the URL scheme or
-- the file extension (sqlrun/dialects); the one picked (<leader>Qc) is remembered per project. Pure where it matters:
-- `parse_env`, `kind`, `list` and `shown` are tested in test-langs.lua.
local dialects = require "sqlrun.dialects"
local url = require "sqlrun.url"

local M = {}

---@class SqlConnection
---@field name string
---@field kind string      a dialect id: postgres, sqlite, mysql, mariadb, sqlserver, duckdb
---@field target string    the URL (network engines) or the file path (SQLite, DuckDB)
---@field source string    where it came from (".env", "settings", "project", "file")

--- The variables of a .env file: KEY=value, `export KEY=value`, quotes removed, comments and blank lines skipped
---@param text string
---@return table<string, string>
function M.parse_env(text)
  local out = {}
  for line in (text or ""):gmatch "[^\r\n]+" do
    local key, value = line:match "^%s*export%s+([%w_]+)%s*=%s*(.-)%s*$"
    if not key then
      key, value = line:match "^%s*([%w_]+)%s*=%s*(.-)%s*$"
    end
    if key and not line:match "^%s*#" then
      local quoted = value:match '^"(.*)"$' or value:match "^'(.*)'$"
      out[key] = quoted or (value:gsub("%s+#.*$", ""))
    end
  end
  return out
end

--- What a target is: a dialect id, or nil when nothing recognizes it
---@param target string
---@return string? kind, string? value
function M.kind(target)
  return dialects.detect(target)
end

--- The variables that hold a database URL, in the order they are offered
---@param env table<string, string>
---@return string[]
local function url_keys(env)
  local keys = {}
  for k in pairs(env) do
    if
      k == "DATABASE_URL"
      or k == "DATABASE_URI"
      or k:match "_DATABASE_URL$"
      or k:match "_DATABASE_URI$"
      or k:match "_DB_URL$"
      or k:match "_DB_URI$"
      or k == "DB_URL"
      or k == "DB_URI"
      or k == "POSTGRES_URL"
      or k == "POSTGRESQL_URL"
      or k == "MYSQL_URL"
      or k == "MARIADB_URL"
      or k == "MSSQL_URL"
      or k == "SQLSERVER_URL"
      or k == "SQLITE_URL"
    then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys, function(a, b)
    if (a == "DATABASE_URL") ~= (b == "DATABASE_URL") then
      return a == "DATABASE_URL"
    end
    return a < b
  end)
  return keys
end

--- A name for a connection that was given without one
---@param kind string
---@param value string
---@return string
local function auto_name(kind, value)
  if kind == "sqlite" or kind == "duckdb" then
    return (vim.fs.basename(value):gsub("%.%w+$", ""))
  end
  local parsed = url.parse(value)
  if parsed then
    if parsed.database and parsed.database ~= "" then
      return parsed.database
    end
    if parsed.host and parsed.host ~= "" then
      return parsed.host
    end
  end
  local d = dialects.get(kind)
  return d and d.short or kind
end

---@param path string
---@return string
local function shown_path(path, root)
  if root and path:sub(1, #root + 1) == root .. "/" then
    return path:sub(#root + 2)
  end
  return path
end

--- Every connection of a project (pure): project extras, settings, env files (name → text), the environment's URL,
--- SQLite/DuckDB files
---@param opts { settings: table[]?, extra: table[]?, env_files: table<string, string>?, env_url: string?, sqlite: string[]?, root: string? }
---@return SqlConnection[]
function M.list(opts)
  local out, seen = {}, {}
  local root = opts.root

  local function add(name, target, source, driver)
    if type(target) ~= "string" or vim.trim(target) == "" then
      return
    end
    target = vim.trim(target)
    local kind, value
    if driver then
      kind = dialects.alias(driver)
      value = target
      if not dialects.get(kind) then
        return
      end
      value = dialects.normalize(kind, value)
    else
      kind, value = dialects.detect(target)
    end
    if not kind or not value or value == "" then
      return
    end
    if (kind == "sqlite" or kind == "duckdb") and root and not value:match "^/" and not value:match "^%a:[/\\]" then
      value = root .. "/" .. value
    end
    local key = kind .. ":" .. value
    if seen[key] then
      return
    end
    seen[key] = true
    out[#out + 1] = {
      name = (name and name ~= "" and name) or auto_name(kind, value),
      kind = kind,
      target = value,
      source = source,
    }
  end

  for _, c in ipairs(opts.extra or {}) do
    add(c.name, c.url or c.sqlite or c.target, "project", c.driver)
  end
  for _, c in ipairs(opts.settings or {}) do
    add(c.name, c.url or c.sqlite or c.target, "settings", c.driver)
  end
  local files = vim.tbl_keys(opts.env_files or {})
  table.sort(files)
  for _, file in ipairs(files) do
    local env = M.parse_env(opts.env_files[file])
    for _, key in ipairs(url_keys(env)) do
      add(key .. " (" .. file .. ")", env[key], file)
    end
  end
  if opts.env_url and opts.env_url ~= "" then
    add("DATABASE_URL (environment)", opts.env_url, "environment")
  end
  for _, path in ipairs(opts.sqlite or {}) do
    add(shown_path(path, root), path, "file")
  end
  return out
end

-- Folders that hold tool files, not the project's database. `skip` returns false to leave them out (vim.fs.dir).
local SKIP = {
  node_modules = true,
  [".git"] = true,
  target = true,
  [".venv"] = true,
  venv = true,
  build = true,
  dist = true,
  cache = true,
  [".cache"] = true,
  coverage = true,
  __pycache__ = true,
  Pods = true,
  DerivedData = true,
  profiles = true,
  Profiles = true,
  tmp = true,
}

---@param dir string
---@return boolean
local function descend(dir)
  local base = vim.fs.basename(dir)
  if base:sub(1, 1) == "." then
    return false
  end
  if SKIP[base] then
    return false
  end
  return not (base:match "^[Cc]hrome" or base:match "^[Cc]hromium" or base:match "^[Ff]irefox")
end

local COMMON = {
  app = true,
  main = true,
  dev = true,
  development = true,
  ["local"] = true,
  database = true,
  data = true,
  db = true,
  prod = true,
  test = true,
  staging = true,
}

local DATA_DIRS = {
  data = true,
  db = true,
  database = true,
  storage = true,
  var = true,
  fixtures = true,
  test = true,
  tests = true,
  spec = true,
}

--- Which of several database files looks like the project's: the one named after the folder, the usual
--- `app`/`dev`/`data`, and the shallowest path win. A `.db` inside a browser profile or a cache never reaches this.
---@param path string
---@param root string
---@return integer
local function rank(path, root)
  local rel = path:sub(#root + 2)
  local stem = vim.fs.basename(path):gsub("%.%w+$", ""):lower()
  local project = vim.fs.basename(root):lower()
  local score = 0
  if stem == project then
    score = score + 100
  end
  if COMMON[stem] then
    score = score + 50
  end
  local first = rel:match "^([^/]+)/"
  if not first then
    score = score + 20
  elseif DATA_DIRS[first] then
    score = score + 10
  end
  return score - math.floor(#rel / 20)
end
M.rank = rank

---@return string
local function extras_path()
  return vim.fn.stdpath "state" .. "/sqlrun-connections.json"
end

---@param path string
---@return table
local function read_json(path)
  local text = require("utils.project").read(path)
  if not text or text == "" then
    return {}
  end
  local ok, data = pcall(vim.json.decode, text)
  return ok and type(data) == "table" and data or {}
end

---@param path string
---@param data table
local function write_json(path, data)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = io.open(path, "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
    pcall(vim.uv.fs_chmod, path, 384) -- 0600: these files can hold a URL with its password
  end
end

--- The connections added to a project with <leader>Qn
---@param root string
---@return table[]
function M.extras(root)
  local data = read_json(extras_path())
  return type(data[root]) == "table" and data[root] or {}
end

---@type table<string, { at: integer, list: SqlConnection[] }>
local cache = {}

--- Forgets what was read for a project (after adding, removing or picking a connection)
---@param root string?
function M.invalidate(root)
  if root then
    cache[root] = nil
  else
    cache = {}
  end
end

--- The project's connections, read from the disk and the environment
---@param root string
---@return SqlConnection[]
function M.of(root)
  local hit = cache[root]
  if hit and vim.uv.now() - hit.at < 3000 then
    return hit.list
  end
  local read = require("utils.project").read
  local env_files = {}
  for _, name in ipairs { ".env", ".env.local", ".env.development", ".env.development.local" } do
    local text = read(root .. "/" .. name)
    if text then
      env_files[name] = text
    end
  end
  local sqlite = {}
  for name, kind in
    vim.fs.dir(root, {
      depth = 3,
      skip = descend,
    })
  do
    if
      kind == "file"
      and (name:match "%.db$" or name:match "%.sqlite3?$" or name:match "%.duckdb$" or name:match "%.ddb$")
    then
      sqlite[#sqlite + 1] = root .. "/" .. name
    end
    if #sqlite >= 20 then
      break
    end
  end
  table.sort(sqlite, function(a, b)
    local ra, rb = rank(a, root), rank(b, root)
    if ra ~= rb then
      return ra > rb
    end
    return a < b
  end)
  local list = M.list {
    extra = M.extras(root),
    settings = (require("core.settings").sql or {}).connections,
    env_files = env_files,
    env_url = vim.env.DATABASE_URL,
    sqlite = sqlite,
    root = root,
  }
  cache[root] = { at = vim.uv.now(), list = list }
  return list
end

--- The target chosen for a project, if it still exists
---@param root string
---@return string?
function M.chosen(root)
  local data = read_json(vim.fn.stdpath "state" .. "/sqlrun.json")
  local value = data[root]
  return type(value) == "string" and value or nil
end

--- The connections in sqls' shape (servers/sqls.lua): the one picked first, so it is sqls' default
---@param root string
---@return table[]
function M.sqls(root)
  local list = M.of(root)
  local want = M.chosen(root)
  local ordered = {}
  for _, c in ipairs(list) do
    if c.target == want then
      ordered[#ordered + 1] = c
    end
  end
  for _, c in ipairs(list) do
    if c.target ~= want then
      ordered[#ordered + 1] = c
    end
  end
  local out = {}
  for _, c in ipairs(ordered) do
    local d = dialects.get(c.kind)
    if d and d.sqls then
      local entry = { alias = c.name, driver = d.sqls }
      if c.kind == "mysql" or c.kind == "mariadb" then
        local parsed = url.parse(c.target)
        if parsed and parsed.host then
          entry.proto = "tcp"
          entry.user = parsed.user
          entry.passwd = parsed.password
          entry.host = parsed.host
          entry.port = parsed.port
          entry.dbName = (parsed.database ~= "" and parsed.database) or nil
          entry.params = next(parsed.query) and parsed.query or nil
        elseif parsed and parsed.query.socket then
          entry.proto = "unix"
          entry.path = parsed.query.socket
          entry.user = parsed.user
          entry.passwd = parsed.password
          entry.dbName = (parsed.database ~= "" and parsed.database) or nil
        else
          entry.dataSourceName = c.target
        end
      elseif c.kind == "sqlserver" and d.sqls_dsn then
        entry.dataSourceName = d.sqls_dsn(c)
      else
        entry.dataSourceName = c.target
      end
      out[#out + 1] = entry
    end
  end
  return out
end

--- Remembers the connection picked for a project
---@param root string
---@param c SqlConnection
function M.choose(root, c)
  local path = vim.fn.stdpath "state" .. "/sqlrun.json"
  local data = read_json(path)
  data[root] = c.target
  write_json(path, data)
  M.invalidate(root)
end

--- The target an extra entry was written with
---@param entry table
---@return string?
local function extra_target(entry)
  return entry.url or entry.sqlite or entry.target
end

--- Does an extra entry point at `target`? The picker speaks the normalized target (`/tmp/x.db`), the file the URL it
--- was added with (`sqlite:///tmp/x.db`): both names are the same connection.
---@param entry table
---@param target string
---@return boolean
local function same_target(entry, target)
  local raw = extra_target(entry)
  if raw == target then
    return true
  end
  local _, value = dialects.detect(raw or "")
  return value == target
end

--- Adds a connection to this project (kept in the state dir, never touches .env or settings)
---@param root string
---@param target string
---@param name string?
---@param driver string?
---@return SqlConnection? connection, string? problem
function M.add(root, target, name, driver)
  target = type(target) == "string" and vim.trim(target) or nil
  if not target or target == "" then
    return nil, "not a database URL or a SQLite/DuckDB file"
  end
  local kind, value
  if driver then
    kind = dialects.alias(driver)
    value = dialects.normalize(kind, target)
  else
    kind, value = dialects.detect(target)
  end
  if not kind or not value then
    return nil, "not a database URL or a SQLite/DuckDB file"
  end
  if (kind == "sqlite" or kind == "duckdb") and not value:match "^/" and not value:match "^%a:[/\\]" then
    value = root .. "/" .. value
  end
  local data = read_json(extras_path())
  local list = type(data[root]) == "table" and data[root] or {}
  for _, c in ipairs(list) do
    if same_target(c, value) then
      return { name = c.name or auto_name(kind, value), kind = kind, target = value, source = "project" }
    end
  end
  list[#list + 1] = { name = (name and name ~= "") and name or auto_name(kind, value), url = value }
  data[root] = list
  write_json(extras_path(), data)
  M.invalidate(root)
  return { name = list[#list].name, kind = kind, target = value, source = "project" }
end

--- Removes a connection added to this project; the ones from .env or settings are left alone
---@param root string
---@param target string
---@return boolean removed
function M.remove(root, target)
  local data = read_json(extras_path())
  local list = type(data[root]) == "table" and data[root] or {}
  local keep, removed = {}, false
  for _, c in ipairs(list) do
    if same_target(c, target) then
      removed = true
    else
      keep[#keep + 1] = c
    end
  end
  if removed then
    data[root] = keep
    write_json(extras_path(), data)
    M.invalidate(root)
    local chosen = read_json(vim.fn.stdpath "state" .. "/sqlrun.json")
    if chosen[root] == target then
      chosen[root] = nil
      write_json(vim.fn.stdpath "state" .. "/sqlrun.json", chosen)
    end
  end
  return removed
end

--- The connection to use in a project: the one picked (when it still exists), else the first
---@param root string
---@return SqlConnection?
function M.current(root)
  local list = M.of(root)
  local want = M.chosen(root)
  for _, c in ipairs(list) do
    if c.target == want then
      return c
    end
  end
  return list[1]
end

--- A URL without its password, for the screen ("postgres://app:•••@localhost/app")
---@param target string
---@return string
function M.shown(target)
  local masked = target:gsub("^(%a[%w+.-]*://[^:/@]+):[^@]*@", "%1:•••@")
  if masked == target then
    masked = target:gsub("^(%a[%w+.-]*://):[^@]*@", "%1:•••@")
  end
  if masked == target then
    masked = target:gsub("^([^:@/]+):[^@]*@", "%1:•••@")
  end
  return masked
end

--- A chip-sized description: "PG app", "SQLite data", "MSSQL app"
---@param c SqlConnection
---@return string
function M.short(c)
  local d = dialects.get(c.kind)
  local parsed = url.parse(c.target)
  local name
  if parsed then
    name = (parsed.database and parsed.database ~= "") and parsed.database or parsed.host
  end
  if not name or name == "" then
    name = (vim.fs.basename(c.target):gsub("%.%w+$", ""))
  end
  return ((d and d.short or c.kind) .. " " .. name)
end

return M
