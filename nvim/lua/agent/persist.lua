-- ── Hallazgos persistentes ───────────────────────────────────────────────────
-- Los hallazgos de `review`, de `ddd review` y el diagnóstico de DDD son diagnósticos "por atender": se
-- guardan por archivo (stdpath("state")/agent-findings.json) con el TEXTO de la línea señalada, y al abrir
-- el archivo en otra sesión vuelven a ser diagnósticos. Si el código se movió, se reubican por ese texto; si
-- la línea ya no existe (se arregló o se reescribió), se descartan.
local M = {}

--- Clave del almacén → nombre del namespace de diagnósticos (idempotente: crear el mismo nombre da el mismo id)
M.NAMESPACES = { findings = "agent.findings", ddd = "agent.ddd" }

local WINDOW = 40 -- cuántas líneas arriba/abajo se busca el texto si la línea se movió

---@type string?
local override

---@return string
function M.path()
  return override or (vim.fn.stdpath "state" .. "/agent-findings.json")
end

--- Cambia el archivo (pruebas)
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

--- Reemplaza lo guardado de (archivo, clave) por `entries`
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

--- Línea (1-based) donde está ahora el texto de un hallazgo, o nil si ya no está
---@param lines string[]
---@param entry { line: integer, text: string }
---@return integer?
function M.reanchor(lines, entry)
  if entry.text == "" then
    return lines[entry.line] and entry.line or nil -- sin texto con el que reubicar: solo vale si la línea existe
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

--- Guarda los diagnósticos de `key` que tiene ahora el buffer (posiciones y texto actuales)
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

--- Guarda lo que `key` señala en varios archivos (el diagnóstico de DDD toca muchos, abiertos o no)
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

--- Olvida lo guardado de un archivo (todo, o solo una clave)
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

--- Olvida una clave en todos los archivos
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

--- Cuántos hay guardados (para avisos y pruebas)
---@return integer
function M.count()
  local n = 0
  for _, files in pairs(read().files) do
    n = n + #files
  end
  return n
end

--- Devuelve a un buffer sus diagnósticos guardados, reubicados por el texto de su línea
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
    -- cargar el módulo del presentador fija su estilo de diagnóstico (prefijo, subrayado...)
    pcall(require, key == "findings" and "agent.output.findings" or "agent.ddd.diagnose")
    vim.diagnostic.set(namespace(key), buf, list)
    M.sync(buf, key) -- guarda las posiciones ya reubicadas
  end
  if dropped > 0 then
    -- lo que ya no coincide con el código se limpia también de lo guardado
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

--- Tras guardar el archivo: actualiza las posiciones guardadas (el código pudo moverse)
---@param buf integer
function M.resync(buf)
  for key in pairs(M.NAMESPACES) do
    if #vim.diagnostic.get(buf, { namespace = namespace(key) }) > 0 then
      M.sync(buf, key)
    end
  end
end

return M
