-- ── Comentarios largos plegables ─────────────────────────────────────────────
-- Detecta con treesitter los comentarios de varias líneas (un bloque `/* */` o varias
-- líneas `//` seguidas que están solas en su línea) y los expone como folds de nvim-ufo
-- (kind "comment", ver plugins/editing/ufo.lua). El menú <leader>C los pliega/despliega.
-- Sin parser no hay comentarios que detectar: el menú avisa y no hace nada.
local M = {}

-- Nombres de nodo de comentario según la gramática; solo vale el que existe en el lenguaje
local NODE_TYPES = { "comment", "line_comment", "block_comment", "multiline_comment", "documentation_comment" }

---@type table<string, vim.treesitter.Query|false>
local queries = {}

---@param lang string
---@return vim.treesitter.Query?
local function comment_query(lang)
  if queries[lang] == nil then
    local valid = {}
    for _, name in ipairs(NODE_TYPES) do
      if pcall(vim.treesitter.query.parse, lang, "(" .. name .. ") @c") then
        valid[#valid + 1] = "(" .. name .. ")"
      end
    end
    queries[lang] = #valid > 0 and vim.treesitter.query.parse(lang, "[" .. table.concat(valid, " ") .. "] @c") or false
  end
  return queries[lang] or nil
end

---@class CommentRange
---@field first integer fila (0-based) donde empieza
---@field last integer fila (0-based, inclusiva) donde termina

--- Comentarios de `min_lines` líneas o más, ordenados. Los comentarios al final de una
--- línea de código no cuentan; las líneas `//` seguidas se unen en uno solo.
---@param buf integer
---@return CommentRange[]
function M.ranges(buf)
  local min_lines = require("core.settings").comments.min_lines
  local ok, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if not (ok and parser) then
    return {}
  end
  parser:parse()

  local nodes = {}
  parser:for_each_tree(function(tree, ltree)
    local query = comment_query(ltree:lang())
    if not query then
      return
    end
    for _, node in query:iter_captures(tree:root(), buf) do
      local sr, sc, er, ec = node:range()
      if ec == 0 and er > sr then
        er = er - 1 -- un fin en columna 0 incluye el salto de línea
      end
      -- solo comentarios que empiezan solos en su línea
      local before = vim.api.nvim_buf_get_text(buf, sr, 0, sr, sc, {})[1] or ""
      if not before:find "%S" then
        nodes[#nodes + 1] = { first = sr, last = er }
      end
    end
  end)
  table.sort(nodes, function(a, b)
    return a.first < b.first
  end)

  local merged = {}
  for _, n in ipairs(nodes) do
    local prev = merged[#merged]
    -- líneas de comentario consecutivas = un solo comentario (un bloque `/* */` nunca se une)
    if prev and prev.line_run and n.first == n.last and n.first == prev.last + 1 then
      prev.last = n.last
    else
      merged[#merged + 1] = { first = n.first, last = n.last, line_run = n.first == n.last }
    end
  end

  local result = {}
  for _, c in ipairs(merged) do
    if c.last - c.first + 1 >= min_lines then
      result[#result + 1] = { first = c.first, last = c.last }
    end
  end
  return result
end

--- ¿El comentario es ahora mismo un fold cerrado exactamente de su tamaño?
---@param c CommentRange
---@return boolean
local function is_closed(c)
  local lnum = c.first + 1
  return vim.fn.foldclosed(lnum) == lnum and vim.fn.foldclosedend(lnum) == c.last + 1
end

---@param c CommentRange
local function close(c)
  if vim.fn.foldclosed(c.first + 1) == -1 then
    pcall(vim.cmd, c.first + 1 .. "foldclose")
  end
end

---@param c CommentRange
local function open(c)
  if is_closed(c) then
    pcall(vim.cmd, c.first + 1 .. "foldopen")
  end
end

---@return CommentRange[]?
local function current_ranges()
  local ranges = M.ranges(vim.api.nvim_get_current_buf())
  if #ranges == 0 then
    vim.notify(
      ("No comments of %d+ lines here"):format(require("core.settings").comments.min_lines),
      vim.log.levels.INFO
    )
    return nil
  end
  vim.wo.foldenable = true
  return ranges
end

--- Pliega todos los comentarios largos del buffer
function M.collapse()
  local ranges = current_ranges()
  if not ranges then
    return
  end
  for _, c in ipairs(ranges) do
    close(c)
  end
  vim.notify(("Collapsed %d comments"):format(#ranges), vim.log.levels.INFO)
end

--- Despliega todos los comentarios largos del buffer
function M.expand()
  local ranges = current_ranges()
  if not ranges then
    return
  end
  for _, c in ipairs(ranges) do
    open(c)
  end
end

--- Pliega/despliega el comentario largo bajo el cursor
function M.toggle()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  for _, c in ipairs(M.ranges(vim.api.nvim_get_current_buf())) do
    if c.first <= row and row <= c.last then
      vim.wo.foldenable = true
      if is_closed(c) then
        return open(c)
      end
      return close(c)
    end
  end
  vim.notify("No long comment under the cursor", vim.log.levels.INFO)
end

return M
