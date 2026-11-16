-- ── Database URLs (pure) ─────────────────────────────────────────────────────
-- `scheme://user:password@host:port/database?key=value`, split into the pieces the clients need. Every piece is
-- percent-decoded (`Pass%40123` → `Pass@123`), because a password with `@`, `:` or `/` would otherwise break the argv.
-- Used by the dialects (mysql/sqlcmd) and by sqls (the LSP wants its own shape). Tested in test-langs.lua.
local M = {}

---@param value string?
---@return string?
local function decode(value)
  if value == nil then
    return nil
  end
  local ok, out = pcall(vim.uri_decode, value)
  return ok and out or value
end

--- `host`, `host:port`, `[::1]` or `[::1]:5432`
---@param value string
---@return string? host, integer? port
local function split_host(value)
  local v6, port = value:match "^%[(.-)%]:(%d+)$"
  if v6 then
    return v6, tonumber(port)
  end
  v6 = value:match "^%[(.-)%]$"
  if v6 then
    return v6
  end
  local host, p = value:match "^(.+):(%d+)$"
  if host then
    return host, tonumber(p)
  end
  return value ~= "" and value or nil
end

---@class SqlUrl
---@field scheme string lower case, without `://`
---@field user string?
---@field password string?
---@field host string?
---@field port integer?
---@field database string?   the path without its leading `/`
---@field path string       the path as written (may be empty)
---@field query table<string, string>
---@field query_string string

--- Splits a URL; nil when it has no `scheme://` (a DSN or a plain path)
---@param target string?
---@return SqlUrl?
function M.parse(target)
  if type(target) ~= "string" then
    return nil
  end
  local scheme, rest = target:match "^(%a[%w+.-]*)://(.*)$"
  if not scheme then
    return nil
  end
  scheme = scheme:lower()
  local query_string = ""
  local q = rest:find("?", 1, true)
  if q then
    query_string = rest:sub(q + 1)
    rest = rest:sub(1, q - 1)
  end
  local authority, path = rest:match "^([^/]*)(/.*)$"
  if not authority then
    authority, path = rest, ""
  end
  local userinfo, hostport = authority:match "^(.*)@(.+)$"
  local user, password
  if userinfo then
    user, password = userinfo:match "^([^:]*):?(.*)$"
    user = decode(user)
    password = decode(password)
    if password == "" then
      password = nil
    end
  end
  local host, port = split_host(hostport or "")
  local query = {}
  for pair in (query_string or ""):gmatch "[^&;]+" do
    local key, value = pair:match "^([^=]*)=(.*)$"
    if key then
      query[decode(key)] = decode(value)
    elseif pair ~= "" then
      query[decode(pair)] = ""
    end
  end
  return {
    scheme = scheme,
    user = user,
    password = password,
    host = host,
    port = port,
    database = decode((path:gsub("^/", ""))),
    path = path,
    query = query,
    query_string = query_string,
  }
end

--- The query parameters as the `key=value&…` string a DSN expects (nil when there are none)
---@param query table<string, string>?
---@return string?
function M.encode_query(query)
  local out = {}
  for key, value in pairs(query or {}) do
    out[#out + 1] = key .. "=" .. value
  end
  table.sort(out)
  return #out > 0 and table.concat(out, "&") or nil
end

return M
