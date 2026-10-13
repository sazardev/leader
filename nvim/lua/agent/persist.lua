-- ── Persistent findings ──────────────────────────────────────────────────────
-- The findings of `review`, of `ddd review` and the DDD diagnosis are "pending" diagnostics: they are
-- stored per file (stdpath("state")/agent-findings.json) with the TEXT of the flagged line, and when the
-- file is opened in another session they become diagnostics again. If the code moved, they are re-anchored by that text; if
-- the line no longer exists (it was fixed or rewritten), they are dropped.
local M = {}

--- Store key → diagnostics namespace name (idempotent: creating the same name gives the same id)
M.NAMESPACES = { findings = "agent.findings", ddd = "agent.ddd" }

local WINDOW = 40 -- how many lines up/down the text is searched for if the line moved

---@type string?
local override

---@return string
function M.path()
  return override or (vim.fn.stdpath "state" .. "/agent-findings.json")
end

--- Changes the file (tests)
---@param path string?
function M.use(path)
  override = path
end

---@return { files: table<string, table[]> }
local function read()
  local f = io.open(M.path(), "r")
  if not f then
    return { files = {} }
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  if not ok or type(data) ~= "table" or type(data.files) ~= "table" then
    return { files = {} }
  end
  return data
end

---@param data table
local function write(data)
  vim.fn.mkdir(vim.fn.fnamemodify(M.path(), ":h"), "p")
  local f = io.open(M.path(), "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

---@param s string?
---@return string
local function trim(s)
  return vim.trim(s or "")
end

---@param key string
---@return integer
local function namespace(key)
  return vim.api.nvim_create_namespace(M.NAMESPACES[key])
end

--- Replaces what is stored for (file, key) with `entries`
---@param path string
---@param key string
---@param entries table[]
local function replace(path, key, entries)
  local data = read()
  local kept = vim.tbl_filter(function(e)
    return e.ns ~= key
  end, data.files[path] or {})
  vim.list_extend(kept, entries)
  data.files[path] = #kept > 0 and kept or nil
  write(data)
end

--- Line (1-based) where a finding's text is now, or nil if it is no longer there
---@param lines string[]
---@param entry { line: integer, text: string }
---@return integer?
function M.reanchor(lines, entry)
  if entry.text == "" then
    return lines[entry.line] and entry.line or nil -- no text to re-anchor with: only valid if the line exists
  end
  if trim(lines[entry.line]) == entry.text then
    return entry.line
  end
  for offset = 1, WINDOW do
    for _, line in ipairs { entry.line - offset, entry.line + offset } do
      if line >= 1 and trim(lines[line]) == entry.text then
        return line
      end
    end
  end
  return nil
end

--- Stores the `key` diagnostics the buffer has now (current positions and text)
---@param buf integer
---@param key "findings"|"ddd"
function M.sync(buf, key)
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local entries = {}
  for _, d in ipairs(vim.diagnostic.get(buf, { namespace = namespace(key) })) do
    local line = vim.api.nvim_buf_get_lines(buf, d.lnum, d.lnum + 1, false)[1] or ""
    entries[#entries + 1] = {
      ns = key,
      line = d.lnum + 1,
      text = trim(line),
      severity = d.severity,
      message = d.message,
      source = d.source,
      ts = os.time(),
    }
  end
  replace(path, key, entries)
end

--- Stores what `key` flags across several files (the DDD diagnosis touches many, open or not)
---@param key "findings"|"ddd"
---@param by_path table<string, { line: integer, severity: integer, message: string, source: string? }[]>
function M.replace_all(key, by_path)
  local data = read()
  for path, files in pairs(data.files) do
    local kept = vim.tbl_filter(function(e)
      return e.ns ~= key
    end, files)
    data.files[path] = #kept > 0 and kept or nil
  end
  for path, list in pairs(by_path) do
    local ok, lines = pcall(vim.fn.readfile, path)
    lines = ok and lines or {}
    data.files[path] = data.files[path] or {}
    for _, v in ipairs(list) do
      table.insert(data.files[path], {
        ns = key,
        line = v.line,
        text = trim(lines[v.line]),
        severity = v.severity,
        message = v.message,
        source = v.source,
        ts = os.time(),
      })
    end
  end
  write(data)
end

--- Forgets what is stored for a file (everything, or just one key)
---@param path string
---@param key string?
function M.forget(path, key)
  if key then
    replace(path, key, {})
  else
    local data = read()
    data.files[path] = nil
    write(data)
  end
end

--- Forgets a key in all files
---@param key string
function M.forget_all(key)
  local data = read()
  for path, files in pairs(data.files) do
    local kept = vim.tbl_filter(function(e)
      return e.ns ~= key
    end, files)
    data.files[path] = #kept > 0 and kept or nil
  end
  write(data)
end

--- How many are stored (for notices and tests)
---@return integer
function M.count()
  local n = 0
  for _, files in pairs(read().files) do
    n = n + #files
  end
  return n
end

--- Gives a buffer its stored diagnostics back, re-anchored by the text of their line
---@param buf integer
function M.restore(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.bo[buf].buftype ~= "" then
    return
  end
  local saved = read().files[path]
  if not saved then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local by_key, dropped = {}, 0
  for _, e in ipairs(saved) do
    local line = M.reanchor(lines, e)
    if line and M.NAMESPACES[e.ns] then
      local content = lines[line] or ""
      by_key[e.ns] = by_key[e.ns] or {}
      table.insert(by_key[e.ns], {
        lnum = line - 1,
        end_lnum = line - 1,
        col = (content:find "%S" or 1) - 1,
        end_col = #content,
        severity = e.severity,
        message = e.message,
        source = e.source or "agent",
      })
    else
      dropped = dropped + 1
    end
  end

  for key, list in pairs(by_key) do
    -- loading the presenter module sets its diagnostic style (prefix, underline...)
    pcall(require, key == "findings" and "agent.output.findings" or "agent.ddd.diagnose")
    vim.diagnostic.set(namespace(key), buf, list)
    M.sync(buf, key) -- stores the already re-anchored positions
  end
  if dropped > 0 then
    -- what no longer matches the code is also cleaned from what is stored
    for _, key in ipairs { "findings", "ddd" } do
      if not by_key[key] then
        replace(path, key, {})
      end
    end
    vim.schedule(function()
      require("utils.log").info(
        ("Agent: %d saved finding%s no longer match%s the code and %s dropped"):format(
          dropped,
          dropped == 1 and "" or "s",
          dropped == 1 and "es" or "",
          dropped == 1 and "was" or "were"
        )
      )
    end)
  end
end

--- After saving the file: updates the stored positions (the code may have moved)
---@param buf integer
function M.resync(buf)
  for key in pairs(M.NAMESPACES) do
    if #vim.diagnostic.get(buf, { namespace = namespace(key) }) > 0 then
      M.sync(buf, key)
    end
  end
end

return M
