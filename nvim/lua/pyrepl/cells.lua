-- ── Python REPL: celdas (parte pura) ───────────────────────────────────────────
-- Un "workspace" de REPL es un .py con celdas marcadas con `# %%`. Todo lo de
-- este archivo es puro: recibe líneas, devuelve líneas o rangos. Sin efectos.
local M = {}

M.marker = "# %%"

---@param line string
---@return boolean
function M.is_marker(line)
  return line:match "^%s*#%s*%%+" ~= nil
end

--- Rangos de las celdas. `marker` = línea del `# %%` (o nil si no hay ninguno),
--- `first`/`last` = 1-based, inclusivas, del CONTENIDO.
---@param lines string[]
---@return {marker:integer?, first:integer, last:integer}[]
function M.parse(lines)
  local cells = {}
  local current
  -- el contenido anterior al primer `# %%` también es una celda
  if #lines > 0 and not M.is_marker(lines[1]) then
    current = { first = 1, last = #lines }
  end
  for i, line in ipairs(lines) do
    if M.is_marker(line) then
      if current then
        current.last = i - 1
        if current.last >= current.first then
          table.insert(cells, current)
        end
      end
      current = { marker = i, first = i + 1, last = #lines }
    end
  end
  if current then
    current.last = #lines
    if current.marker or current.last >= current.first then
      table.insert(cells, current)
    end
  end
  return cells
end

--- Celda que contiene la fila (1-based); una línea marcada pertenece a su celda.
---@param lines string[]
---@param row integer
---@return table?
function M.at(lines, row)
  for _, cell in ipairs(M.parse(lines)) do
    if row >= (cell.marker or cell.first) and row <= cell.last then
      return cell
    end
  end
end

--- Contenido de una celda, sin líneas en blanco a los bordes.
---@param lines string[]
---@param cell table
---@return string
function M.text(lines, cell)
  local out = {}
  for i = cell.first, cell.last do
    out[#out + 1] = lines[i] or ""
  end
  while #out > 0 and out[1]:match "^%s*$" do
    table.remove(out, 1)
  end
  while #out > 0 and out[#out]:match "^%s*$" do
    table.remove(out)
  end
  return table.concat(out, "\n")
end

local function previous_code(lines)
  for i = #lines, 1, -1 do
    if not lines[i]:match "^%s*$" and not M.is_marker(lines[i]) then
      return lines[i]
    end
  end
end

--- Inserta `# %%` delante de los bloques lógicos de nivel superior. Idempotente:
--- si ya hay marcadores no toca nada. Conserva las líneas existentes tal cual.
---@param lines string[]
---@return string[]
function M.split(lines)
  for _, line in ipairs(lines) do
    if M.is_marker(line) then
      return lines
    end
  end

  local out = {}
  local seen_imports, added_after_imports = false, false
  for _, line in ipairs(lines) do
    local trimmed = line:match "^%s*(.-)%s*$"
    local top = line:match "^%S" ~= nil
    local starts_block = false

    if top and (trimmed:match "^import%s" or trimmed:match "^from%s") then
      seen_imports = true
    end

    if top and #out > 0 then
      local prev = previous_code(out) or ""
      if trimmed:match "^(def%s+)" or trimmed:match "^(class%s+)" or trimmed:match "^(async%s+def%s+)" then
        -- el decorador ya abrió la celda: no la dupliques antes del def
        starts_block = not prev:match "^%s*@"
      elseif trimmed:match "^@" then
        starts_block = true
      elseif trimmed:match "^if%s+__name__" then
        starts_block = true
      elseif seen_imports and not added_after_imports and trimmed ~= "" then
        starts_block = true
        added_after_imports = true
      end
    end

    if starts_block then
      local prev = out[#out]
      if prev and not prev:match "^%s*$" and not M.is_marker(prev) then
        out[#out + 1] = ""
      end
      out[#out + 1] = M.marker
    end
    out[#out + 1] = line
  end
  return out
end

return M
