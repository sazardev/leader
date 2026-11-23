-- ── Python REPL: salida segmentada (parte pura) ───────────────────────────────
-- Convierte el texto de la terminal (IPython o el REPL de Python) en bloques
-- "prompt + lo que imprimió". Sin terminales, sin modelos, sin efectos.
local M = {}

--- Quita los códigos de color de la terminal.
---@param text string?
---@return string
function M.strip(text)
  return (tostring(text or ""):gsub("\27%[[%d;?]*[ -/]*[@-~]", ""))
end

---@param text string?
---@return {label:string, code:boolean, lines:string[]}[]
function M.parse(text)
  local lines = vim.split(M.strip(text), "\n", { plain = true })
  local blocks = {}
  local current

  local function ensure(label, code)
    if not current then
      current = { label = label or "output", code = code == true, lines = {} }
      table.insert(blocks, current)
    end
    return current
  end

  for _, line in ipairs(lines) do
    local ipython = line:match "^(In%s*%[[%d ]*%]:)%s*(.*)$"
    local python = line:match "^(>>>)%s*(.*)$"
    if ipython then
      local label, rest = line:match "^(In%s*%[[%d ]*%]:)%s*(.*)$"
      current = { label = label, code = true, lines = {} }
      table.insert(blocks, current)
      if rest ~= "" then
        table.insert(current.lines, rest)
      end
    elseif python then
      local label, rest = line:match "^(>>>)%s*(.*)$"
      current = { label = label, code = true, lines = {} }
      table.insert(blocks, current)
      if rest ~= "" then
        table.insert(current.lines, rest)
      end
    else
      local block = ensure("output", false)
      table.insert(block.lines, line)
    end
  end
  return blocks
end

---@param blocks table[]
---@return string[]
function M.render(blocks)
  local out = {}
  for _, block in ipairs(blocks) do
    local label = block.label or "output"
    local rule = ("─"):rep(math.max(2, 38 - vim.fn.strdisplaywidth(label)))
    out[#out + 1] = "── " .. label .. " " .. rule
    vim.list_extend(out, block.lines)
    out[#out + 1] = ""
  end
  return out
end

---@param blocks table[]
---@return string
function M.text(blocks)
  return table.concat(M.render(blocks), "\n")
end

return M
