-- ── SQL connections of a project ─────────────────────────────────────────────
-- Found, never asked: `settings.sql.connections` first, then the URLs in the project's .env files (DATABASE_URL and any
-- *_DATABASE_URL / *_DB_URL / POSTGRES_URL) and the environment's DATABASE_URL, then the SQLite files under the root
-- (*.db, *.sqlite, *.sqlite3, outside node_modules/.git/target). The one you pick (<leader>Qc) is remembered per project
-- in the state dir. The pure parts (env, kind, list) are tested in test-langs.lua.
local M = {}

---@class SqlConnection
---@field name string
---@field kind "postgres"|"sqlite"
---@field target string   the URL (postgres) or the file path (sqlite)
---@field source string   where it came from (".env", "settings", "file")

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

--- What a target is: a postgres URL, or a SQLite file (sqlite:// or file: URLs, or a path)
---@param target string
---@return "postgres"|"sqlite"|nil, string? the target as the client takes it
function M.kind(target)
  if target:match "^postgres[%w]*://" then
    return "postgres", target
  end
  local path = target:match "^sqlite3?:///?(.+)$" or target:match "^file:(.+)$"
  if path then
    return "sqlite", path
  end
  if target:match "%.db$" or target:match "%.sqlite3?$" then
    return "sqlite", target
  end
  return nil
end

--- The variables that hold a database URL, in the order they are offered
---@param env table<string, string>
---@return string[]
local function url_keys(env)
  local keys = {}
  for k in pairs(env) do
    if
      k == "DATABASE_URL"
      or k:match "_DATABASE_URL$"
      or k:match "_DB_URL$"
      or k == "POSTGRES_URL"
      or k == "DB_URL"
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

--- Every connection of a project (pure): settings, env files (name → text), the environment's URL, SQLite files
---@param opts { settings: table[]?, env_files: table<string, string>?, env_url: string?, sqlite: string[]?, root: string? }
---@return SqlConnection[]
function M.list(opts)
  local out, seen = {}, {}
  local function add(name, target, source)
    local kind, value = M.kind(target or "")
    if kind and not seen[value] then
      seen[value] = true
      out[#out + 1] = { name = name, kind = kind, target = value, source = source }
    end
  end
  for _, c in ipairs(opts.settings or {}) do
    add(c.name or c.url or c.sqlite, c.url or c.sqlite, "settings")
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
    local shown = opts.root and path:sub(1, #opts.root + 1) == opts.root .. "/" and path:sub(#opts.root + 2) or path
    add(shown, path, "file")
  end
  return out
end

local SKIP =
  { node_modules = true, [".git"] = true, target = true, [".venv"] = true, venv = true, build = true, dist = true }

--- The project's connections, read from the disk and the environment
---@param root string
---@return SqlConnection[]
function M.of(root)
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
      skip = function(dir)
        return not SKIP[vim.fs.basename(dir)]
      end,
    })
  do
    if kind == "file" and (name:match "%.db$" or name:match "%.sqlite3?$") then
      sqlite[#sqlite + 1] = root .. "/" .. name
    end
    if #sqlite >= 20 then
      break
    end
  end
  table.sort(sqlite)
  return M.list {
    settings = (require("core.settings").sql or {}).connections,
    env_files = env_files,
    env_url = vim.env.DATABASE_URL,
    sqlite = sqlite,
    root = root,
  }
end

--- The connections in sqls' shape (servers/sqls.lua)
---@param root string
---@return { driver: string, dataSourceName: string }[]
function M.sqls(root)
  return vim.tbl_map(function(c)
    return { driver = c.kind == "postgres" and "postgresql" or "sqlite3", dataSourceName = c.target }
  end, M.of(root))
end

-- ── the one chosen per project ───────────────────────────────────────────────

---@return string
local function store_path()
  return vim.fn.stdpath "state" .. "/sqlrun.json"
end

---@return table<string, string>
local function chosen()
  local ok, data = pcall(vim.json.decode, require("utils.project").read(store_path()) or "")
  return ok and type(data) == "table" and data or {}
end

--- The connection to use in a project: the one picked (when it still exists), else the first
---@param root string
---@return SqlConnection?
function M.current(root)
  local list = M.of(root)
  local want = chosen()[root]
  for _, c in ipairs(list) do
    if c.target == want then
      return c
    end
  end
  return list[1]
end

--- Remembers the connection picked for a project
---@param root string
---@param c SqlConnection
function M.choose(root, c)
  local data = chosen()
  data[root] = c.target
  vim.fn.mkdir(vim.fs.dirname(store_path()), "p")
  local f = io.open(store_path(), "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

--- A URL without its password, for the screen ("postgres://app:•••@localhost/app")
---@param target string
---@return string
function M.shown(target)
  return (target:gsub("^(%w+://[^:/@]+):[^@]*@", "%1:•••@"))
end

return M
