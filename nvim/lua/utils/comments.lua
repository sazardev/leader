-- ── Comentarios largos plegables ─────────────────────────────────────────────
-- Detecta con treesitter los comentarios de varias líneas (un bloque `/* */` o varias
-- líneas `//` seguidas que están solas en su línea) y los expone como folds de nvim-ufo
-- (kind "longcomment", ver plugins/editing/ufo.lua). El menú <leader>C los pliega/despliega y
-- guarda la preferencia (se mantiene al abrir otros archivos y al reiniciar).
-- Sin parser no hay comentarios que detectar: el menú avisa y no hace nada.
local M = {}

--- `kind` con el que los folds de comentarios largos se registran en ufo (único: el proveedor de
--- treesitter usa el nombre del nodo, p. ej. "comment", y cerraría también los comentarios cortos)
M.KIND = "longcomment"

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

-- ── Preferencia persistente ──────────────────────────────────────────────────
-- "Comentarios plegados" es global y se guarda en stdpath("state")/comments.json (como las de
-- utils/diagblocks.lua): `<leader>Cc` la enciende, `<leader>Ce` la apaga y vale para los archivos
-- que abras después y para las próximas sesiones. `settings.comments.auto_collapse` solo da el
-- valor inicial, hasta que eliges algo.
local PREFS_PATH = vim.fn.stdpath "state" .. "/comments.json"

---@type { collapsed: boolean }?
local prefs

---@return { collapsed: boolean }
local function get_prefs()
  if prefs then
    return prefs
  end
  prefs = { collapsed = require("core.settings").comments.auto_collapse }
  local f = io.open(PREFS_PATH, "r")
  if f then
    local ok, data = pcall(vim.json.decode, f:read "*a")
    f:close()
    if ok and type(data) == "table" and type(data.collapsed) == "boolean" then
      prefs.collapsed = data.collapsed
    end
  end
  return prefs
end

---@param collapsed boolean
local function set_collapsed(collapsed)
  get_prefs().collapsed = collapsed
  vim.fn.mkdir(vim.fn.fnamemodify(PREFS_PATH, ":h"), "p")
  local f = io.open(PREFS_PATH, "w")
  if f then
    f:write(vim.json.encode(prefs))
    f:close()
  end
end

---@return boolean
function M.collapsed()
  return get_prefs().collapsed
end

--- Kinds que ufo cierra solo la primera vez que muestra un buffer: con la preferencia encendida,
--- los archivos nuevos se abren con los comentarios largos ya plegados
---@return string[]
function M.close_kinds()
  return M.collapsed() and { M.KIND } or {}
end

--- ufo lee esta lista en vivo (la de su config): se pone o quita el kind sin reiniciar nada
local function sync_ufo()
  local ok, config = pcall(require, "ufo.config")
  if not ok then
    return
  end
  local kinds = config.close_fold_kinds_for_ft.default or {}
  config.close_fold_kinds_for_ft.default = kinds
  for i = #kinds, 1, -1 do
    if kinds[i] == M.KIND then
      table.remove(kinds, i)
    end
  end
  if M.collapsed() then
    kinds[#kinds + 1] = M.KIND
  end
end

-- ── Acciones ─────────────────────────────────────────────────────────────────

--- Pliega o despliega todos los comentarios largos del buffer de la ventana actual
---@param collapse boolean
---@return integer cuántos comentarios largos hay
local function apply_here(collapse)
  local ranges = M.ranges(vim.api.nvim_get_current_buf())
  if #ranges > 0 then
    vim.wo.foldenable = true
  end
  for _, c in ipairs(ranges) do
    if collapse then
      close(c)
    else
      open(c)
    end
  end
  return #ranges
end

--- Pliega AL INSTANTE, de forma síncrona y antes del primer repintado, un buffer recién mostrado.
--- El proveedor de ufo es asíncrono (el archivo se vería abierto unas decenas de ms y luego
--- "saltaría"): aquí se crean los folds de los comentarios largos y se cierran en el acto; cuando
--- ufo termina, rehace todos los folds y los vuelve a cerrar por kind sin que se note.
--- Solo actúa si el buffer aún no tiene folds (si ya los tiene, ufo ya trabajó: lo alinea `apply_here`).
---@param buf integer
---@return integer cuántos comentarios largos pliega
local function fold_now(buf)
  if vim.wo.foldmethod ~= "manual" then
    return 0
  end
  local ranges = M.ranges(buf)
  for _, c in ipairs(ranges) do
    if vim.fn.foldlevel(c.first + 1) > 0 then
      return 0
    end
  end
  if #ranges > 0 then
    vim.wo.foldenable = true
  end
  for _, c in ipairs(ranges) do
    -- de abajo arriba no hace falta: los comentarios no se solapan entre sí
    pcall(vim.cmd, ("%d,%dfold"):format(c.first + 1, c.last + 1))
    close(c)
  end
  return #ranges
end

--- Aplica la preferencia a lo que ya está abierto en este tab (los archivos nuevos la toman de ufo)
---@param collapse boolean
---@return integer
local function apply_visible(collapse)
  local total = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "" then
      total = total + vim.api.nvim_win_call(win, function()
        return apply_here(collapse)
      end)
    end
  end
  return total
end

--- Pliega todos los comentarios largos y los mantiene plegados (preferencia guardada)
function M.collapse()
  set_collapsed(true)
  sync_ufo()
  local n = apply_visible(true)
  vim.notify(
    n > 0 and ("Collapsed %d comments — they stay collapsed (<leader>Ce to undo)"):format(n)
      or ("No comments of %d+ lines here; they will be collapsed in files that have them"):format(
        require("core.settings").comments.min_lines
      ),
    vim.log.levels.INFO
  )
end

--- Despliega todos los comentarios largos y deja de plegarlos solos
function M.expand()
  set_collapsed(false)
  sync_ufo()
  apply_visible(false)
  vim.notify("Comments expanded — they will open expanded", vim.log.levels.INFO)
end

--- Pliega/despliega el comentario largo bajo el cursor (solo ahí: no cambia la preferencia)
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

--- Registra la preferencia en ufo y la aplica a los buffers que ya existían cuando se encendió
--- (los nuevos los cierra ufo solo): al mostrarse, un buffer cuyo estado no coincide se alinea
function M.setup()
  sync_ufo()
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("CommentFolds", { clear = true }),
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" then
        return
      end
      local want = M.collapsed()
      if vim.b[ev.buf].comments_collapsed == want then
        return
      end
      -- al abrir un archivo se pliega ya, sin esperar a ufo (que es asíncrono)
      if want and vim.api.nvim_get_current_buf() == ev.buf and fold_now(ev.buf) > 0 then
        vim.b[ev.buf].comments_collapsed = true
        return
      end
      -- si no (buffer ya con folds, o desplegar): se espera a que ufo los tenga
      vim.defer_fn(function()
        if not (vim.api.nvim_buf_is_valid(ev.buf) and vim.api.nvim_get_current_buf() == ev.buf) then
          return
        end
        if want == M.collapsed() and apply_here(want) > 0 then
          vim.b[ev.buf].comments_collapsed = want
        end
      end, 300)
    end,
  })
end

return M
