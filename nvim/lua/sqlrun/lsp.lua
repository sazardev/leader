-- ── Is sqls actually connected to this project's database? ─────────────────────
-- One place owns the answer, so the statusline chip, `:Sql info` and `:checkhealth sqlrun` never disagree. The server
-- reports failures through window/showMessage; servers/sqls.lua feeds those here and redacts their DSNs before they
-- reach the screen. Nothing here starts a process or touches a database.
local M = {}

---@alias SqlLspStatus "off"|"starting"|"connected"|"error"|"unsupported"

---@type table<string, { status: SqlLspStatus, detail: string, at: integer }>
local states = {}

---@param root string
---@return { status: SqlLspStatus, detail: string, at: integer }
function M.get(root)
  local s = states[root]
  return s and vim.deepcopy(s) or { status = "off", detail = "", at = 0 }
end

---@param root string
---@param patch { status: SqlLspStatus, detail: string? }
function M.set(root, patch)
  local s = states[root] or { status = "off", detail = "", at = 0 }
  local changed = s.status ~= patch.status
  s.status = patch.status
  if patch.detail then
    s.detail = patch.detail
  elseif changed then
    s.detail = ""
  end
  s.at = vim.uv.now()
  states[root] = s
end

--- Forgets a client that is being restarted, so the chip waits instead of showing a stale "connected"
---@param root string?
function M.clear(root)
  if root then
    states[root] = nil
  else
    states = {}
  end
end

--- A URL or a `passwd=…` pair in a server message must never reach a screen or a log unmasked.
---@param message string?
---@return string
function M.redact(message)
  if type(message) ~= "string" then
    return ""
  end
  local out = message:gsub("%a[%w+.-]*://[^%s'\"]+", function(url)
    return require("sqlrun.connections").shown(url)
  end)
  for _, key in ipairs { "[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]", "[Pp][Aa][Ss][Ss][Ww][Dd]", "[Pp][Ww][Dd]" } do
    out = out:gsub("(" .. key .. "%s*=%s*)([^%s,;)]+)", "%1•••")
  end
  return out
end

---@param root string
---@return string " ✓" when connected, " …" while starting, " !" on error, "" otherwise
function M.marker(root)
  local status = M.get(root).status
  if status == "connected" then
    return " ✓"
  elseif status == "starting" then
    return " …"
  elseif status == "error" then
    return " !"
  end
  return ""
end

---@param root string
---@return string
function M.describe(root)
  local s = M.get(root)
  local label = {
    connected = "connected",
    starting = "connecting…",
    error = "not connected",
    unsupported = "no driver",
    off = "not started",
  }
  local text = label[s.status] or s.status
  return s.detail ~= "" and (text .. " · " .. s.detail) or text
end

return M
