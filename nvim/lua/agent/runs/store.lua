-- ── Almacén de ejecuciones (JSON por líneas, solo-añadir) ────────────────────
-- Cada acción escribe una línea `run` al terminar y, después, líneas `event` (aceptada, rechazada...)
-- que se pliegan sobre su ejecución al leer. Solo se añade: nada se reescribe, salvo la
-- compactación ocasional que conserva las más recientes.
local settings = require("core.settings").agent.history

local M = {}

---@type string?
local override

---@return string
function M.path()
  return override or (vim.fn.stdpath "state" .. "/agent-history.jsonl")
end

--- Cambia el archivo (pruebas)
---@param path string?
function M.use(path)
  override = path
end

---@param entry table
---@return boolean
function M.append(entry)
  vim.fn.mkdir(vim.fn.fnamemodify(M.path(), ":h"), "p")
  local f = io.open(M.path(), "a")
  if not f then
    return false
  end
  f:write(vim.json.encode(entry), "\n")
  f:close()
  return true
end

--- Resultado final de una ejecución, a partir de su estado y de los eventos que recibió
---@param run table
local function fold(run)
  local seen = {}
  for _, e in ipairs(run.events) do
    seen[e.event] = e.detail or true
  end
  if run.status == "error" then
    run.outcome = "error"
  elseif run.status == "cancelled" then
    run.outcome = "cancelled"
  elseif seen.accepted then
    run.outcome = "accepted"
  elseif seen.rejected then
    run.outcome = "rejected"
  elseif seen.discarded then
    run.outcome = "discarded"
  elseif seen.unchanged then
    run.outcome = "unchanged"
  elseif seen.findings then
    run.outcome, run.detail = "findings", seen.findings
  elseif seen.shown then
    run.outcome = "shown"
  else
    run.outcome = run.output == "replace" and "pending" or "shown"
  end
end

--- Todas las ejecuciones, la más reciente primero, con su resultado ya plegado
---@return table[]
function M.read()
  local f = io.open(M.path(), "r")
  if not f then
    return {}
  end
  local by_id, list = {}, {}
  for line in f:lines() do
    local ok, entry = pcall(vim.json.decode, line)
    if ok and type(entry) == "table" then
      if entry.t == "run" then
        entry.events = {}
        by_id[entry.id] = entry
        list[#list + 1] = entry
      elseif entry.t == "event" and by_id[entry.id] then
        table.insert(by_id[entry.id].events, entry)
      end
    end
  end
  f:close()
  for _, run in ipairs(list) do
    fold(run)
  end
  table.sort(list, function(a, b)
    return a.ts > b.ts
  end)
  return list
end

--- Si el archivo creció demasiado, deja solo las `max_entries` más recientes (con sus eventos)
---@param max_entries integer?
function M.compact(max_entries)
  max_entries = max_entries or settings.max_entries
  local runs = M.read()
  if #runs <= max_entries * 1.5 then
    return
  end
  local keep = vim.list_slice(runs, 1, max_entries)
  table.sort(keep, function(a, b)
    return a.ts < b.ts
  end)
  local tmp = M.path() .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    return
  end
  for _, run in ipairs(keep) do
    local events = run.events
    run.events, run.outcome, run.detail = nil, nil, nil
    f:write(vim.json.encode(run), "\n")
    for _, e in ipairs(events) do
      f:write(vim.json.encode(e), "\n")
    end
  end
  f:close()
  os.rename(tmp, M.path())
end

return M
