-- ── Objetivo: el código exacto sobre el que trabaja la acción ────────────────
-- Prioridad: selección visual > ámbito de treesitter bajo el cursor (función, o
-- clase si no hay función) > párrafo alrededor del cursor (sirve para una firma a
-- medias: "implementa la función bajo este nombre").
local settings = require("core.settings").agent.context
local scopes = require "agent.context.scopes"

local M = {}

---@class AgentTarget
---@field buf integer
---@field path string
---@field lang string
---@field kind string  "selection" | "function" | "class" | "file" | "lines"
---@field name string?
---@field first integer 1-based
---@field last integer 1-based, inclusivo
---@field lines string[]

---@param buf integer
---@param kind string
---@param first integer
---@param last integer
---@param name string?
---@return AgentTarget
local function make(buf, kind, first, last, name)
  local path = vim.api.nvim_buf_get_name(buf)
  return {
    buf = buf,
    path = path ~= "" and vim.fn.fnamemodify(path, ":.") or "[No Name]",
    lang = vim.bo[buf].filetype,
    kind = kind,
    name = name,
    first = first,
    last = last,
    lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false),
  }
end

--- Rango (1-based) de la selección visual activa; sale del modo visual. nil si no hay
---@return integer[]?
function M.visual_range()
  if not vim.fn.mode():match "^[vV\22]" then
    return nil
  end
  local a, b = vim.fn.line "v", vim.fn.line "."
  vim.api.nvim_feedkeys(vim.keycode "<Esc>", "nx", false)
  return { math.min(a, b), math.max(a, b) }
end

--- Líneas contiguas no vacías alrededor de la fila, acotadas por `window`
---@param buf integer
---@param row integer 0-based
---@return integer, integer
local function paragraph(buf, row)
  local total = vim.api.nvim_buf_line_count(buf)
  local function blank(r)
    return not (vim.api.nvim_buf_get_lines(buf, r, r + 1, false)[1] or ""):match "%S"
  end
  local first, last = row, row
  while first > 0 and row - first < settings.window and not blank(first - 1) do
    first = first - 1
  end
  while last < total - 1 and last - row < settings.window and not blank(last + 1) do
    last = last + 1
  end
  return first + 1, last + 1
end

---@param buf integer
---@param scope string "function" | "class" | "file" | "lines"
---@param range integer[]? selección visual (1-based)
---@return AgentTarget?, string? error
function M.resolve(buf, scope, range)
  local target
  if range then
    target = make(buf, "selection", range[1], range[2])
  elseif scope == "file" then
    target = make(buf, "file", 1, vim.api.nvim_buf_line_count(buf))
  else
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local found, kind
    if scope == "type" then
      -- el tipo bajo el cursor; si el cursor está en un método de Go (que vive fuera del tipo), el de su receptor
      found, kind = scopes.enclosing(buf, row, "class"), "class"
      if not found then
        local fn = scopes.enclosing(buf, row, "function")
        local head = fn and vim.api.nvim_buf_get_lines(buf, fn.first - 1, fn.last, false) or {}
        local receiver
        for _, l in ipairs(head) do
          receiver = receiver or l:match "^func%s*%(%s*[%w_]*%s*%*?%s*([%w_]+)"
        end
        for _, d in ipairs(receiver and scopes.type_declarations(buf) or {}) do
          if d.name == receiver and not d.kind:find("impl", 1, true) then
            found = { first = d.first, last = d.last, name = d.name }
          end
        end
      end
      scope = "class"
    end
    for _, candidate in ipairs(found and {} or (scope == "function" and { "function", "class" } or { scope })) do
      found = scopes.enclosing(buf, row, candidate)
      if found then
        kind = candidate
        break
      end
    end
    if found then
      target = make(buf, kind, found.first, found.last, found.name)
    else
      target = make(buf, "lines", paragraph(buf, row))
    end
  end

  if #target.lines > settings.max_target_lines then
    return nil,
      ("target has %d lines (max %d): select a smaller range"):format(#target.lines, settings.max_target_lines)
  end
  if not table.concat(target.lines):match "%S" then
    return nil, "no code under the cursor"
  end
  return target
end

--- Texto corto para mostrar: `function ParseConfig (12-40)`
---@param target AgentTarget
---@return string
function M.describe(target)
  return ("%s%s (%d-%d)"):format(target.kind, target.name and (" " .. target.name) or "", target.first, target.last)
end

return M
