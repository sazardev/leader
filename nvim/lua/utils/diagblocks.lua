-- ── Diagnósticos como bloques en línea ───────────────────────────────────────
-- Muestra los diagnósticos del buffer como bloques bajo su línea (líneas virtuales: empujan el
-- código, no tapan nada), con la barra de acento de la severidad igual que el bloque del agente.
-- Aparece solo en cada buffer con diagnósticos (settings.diagnostic_blocks.auto); <leader>xa lo apaga
-- en ese buffer. En modo insertar se oculta (salvo `diagnostics.update_in_insert = true`). Dos modos: "expanded" (todos desplegados) y "compact" (cada uno una línea; solo el de la línea
-- del cursor se despliega, así que avanzar con ]/[ recorre uno por uno). Se actualiza solo al
-- cambiar los diagnósticos, el cursor o el tema.
-- También agrupa el popup de la línea (<leader>xd) para que Trouble y el atajo compartan código.
local color = require "appearance.color"

local M = {}

local NS = vim.api.nvim_create_namespace "diagblocks"
-- severidad más alta por línea (0-based) de cada buffer: la lee `M.statuscolumn` al pintar el número
---@type table<integer, table<integer, integer>>
local worst_by_buf = {}
local SEV = vim.diagnostic.severity

-- severidad → icono, etiqueta y nombre del grupo; el color sale de ui/diagcolors.lua (el mismo
-- de la barra de estado)
local KINDS = {
  [SEV.ERROR] = { icon = "✖", label = "Error", name = "Error" },
  [SEV.WARN] = { icon = "▲", label = "Warning", name = "Warn" },
  [SEV.INFO] = { icon = "●", label = "Info", name = "Info" },
  [SEV.HINT] = { icon = "○", label = "Hint", name = "Hint" },
}

local MAX_INDENT = 40

---@return { auto: boolean, mode: "expanded"|"compact", number: boolean }
local function settings()
  return require("core.settings").diagnostic_blocks
end

---@type table<integer, "expanded"|"compact"> buffers con la vista activa
local active = {}

-- Preferencias (global, persisten entre sesiones en stdpath("state")/diagblocks.json); los valores
-- de settings.diagnostic_blocks solo valen hasta que eliges algo con <leader>xa / <leader>xc
---@class DiagBlocksPrefs
---@field enabled boolean
---@field mode "expanded"|"compact"
---@type DiagBlocksPrefs
local prefs = { enabled = true, mode = "expanded" }
local PREFS_PATH = vim.fn.stdpath "state" .. "/diagblocks.json"

local function load_prefs()
  local cfg = require("core.settings").diagnostic_blocks
  prefs = { enabled = cfg.auto, mode = cfg.mode }
  local f = io.open(PREFS_PATH, "r")
  if not f then
    return
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  if ok and type(data) == "table" then
    if type(data.enabled) == "boolean" then
      prefs.enabled = data.enabled
    end
    if data.mode == "expanded" or data.mode == "compact" then
      prefs.mode = data.mode
    end
  end
end

local function save_prefs()
  vim.fn.mkdir(vim.fn.fnamemodify(PREFS_PATH, ":h"), "p")
  local f = io.open(PREFS_PATH, "w")
  if f then
    f:write(vim.json.encode(prefs))
    f:close()
  end
end
local popup_win ---@type integer?

-- ── Popup de la línea (<leader>xd) ───────────────────────────────────────────

--- Popup con los diagnósticos de la línea; llamarlo otra vez entra al popup (copiar, scroll)
function M.popup()
  local _, win = vim.diagnostic.open_float { border = "single", source = true }
  popup_win = win
end

--- Cierra el popup si está abierto
---@return boolean closed
function M.close_popup()
  if popup_win and vim.api.nvim_win_is_valid(popup_win) then
    vim.api.nvim_win_close(popup_win, true)
    popup_win = nil
    return true
  end
  return false
end

-- ── Colores (derivados de la paleta del tema) ────────────────────────────────

local function get(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local function hex(n)
  return n and ("#%06x"):format(n) or nil
end

local function apply_highlights()
  local dark = vim.o.background ~= "light"
  local bg = hex(get("Normal").bg) or (dark and "#1a1a1a" or "#fafafa")
  local fg = hex(get("Normal").fg) or (dark and "#dddddd" or "#222222")
  local diag = require "ui.diagcolors"

  for severity, kind in pairs(KINDS) do
    local accent = diag.accent(severity)
    local pill = diag.pill(severity)
    local block_bg = color.blend(bg, accent, 0.10)
    local muted = color.ensure_contrast(color.blend(fg, block_bg, 0.45), block_bg, fg, 4.5)
    vim.api.nvim_set_hl(0, "DiagBlock" .. kind.name, { fg = fg, bg = block_bg })
    -- barra y etiqueta: el acento EXACTO de la barra de estado (la etiqueta es la misma píldora)
    vim.api.nvim_set_hl(0, "DiagBlock" .. kind.name .. "Bar", { fg = accent, bg = block_bg })
    vim.api.nvim_set_hl(0, "DiagBlock" .. kind.name .. "Title", pill)
    vim.api.nvim_set_hl(0, "DiagBlock" .. kind.name .. "Meta", { fg = muted, bg = block_bg, italic = true })
    -- número de línea: la misma píldora sólida de la barra de estado
    vim.api.nvim_set_hl(0, "DiagNumber" .. kind.name, pill)
  end
end

-- ── Render ───────────────────────────────────────────────────────────────────

--- Parte `text` en filas de hasta `width` columnas (por palabras; las palabras largas se cortan)
---@param text string
---@param width integer
---@return string[]
local function wrap(text, width)
  local rows = {}
  for paragraph in (text .. "\n"):gmatch "(.-)\n" do
    local row = ""
    for word in paragraph:gmatch "%S+" do
      while vim.fn.strdisplaywidth(word) > width do
        if row ~= "" then
          rows[#rows + 1] = row
          row = ""
        end
        local head = vim.fn.strcharpart(word, 0, width)
        rows[#rows + 1] = head
        word = vim.fn.strcharpart(word, vim.fn.strchars(head))
      end
      if row == "" then
        row = word
      elseif vim.fn.strdisplaywidth(row .. " " .. word) <= width then
        row = row .. " " .. word
      else
        rows[#rows + 1] = row
        row = word
      end
    end
    rows[#rows + 1] = row
  end
  while #rows > 1 and rows[#rows] == "" do
    rows[#rows] = nil
  end
  return rows
end

---@param text string
---@param width integer
---@return string
local function truncate(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  return vim.fn.strcharpart(text, 0, math.max(width - 1, 1)) .. "…"
end

---@param win integer
---@return integer
local function text_width(win)
  return vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
end

--- Una fila del bloque: sangría (hueco del código) + barra + contenido relleno hasta el borde
---@param indent integer
---@param width integer ancho útil de la ventana
---@param bar string grupo de la barra
---@param base string grupo del fondo
---@param segments table[] { texto, grupo }
---@param right? table { texto, grupo } alineado a la derecha
local function row(indent, width, bar, base, segments, right)
  local chunks = { { (" "):rep(indent) } }
  chunks[#chunks + 1] = { "▎ ", bar }
  local used = indent + 2
  for _, seg in ipairs(segments) do
    chunks[#chunks + 1] = { seg[1], seg[2] or base }
    used = used + vim.fn.strdisplaywidth(seg[1])
  end
  local right_w = right and vim.fn.strdisplaywidth(right[1]) + 1 or 0
  chunks[#chunks + 1] = { (" "):rep(math.max(width - used - right_w, 0)), base }
  if right then
    chunks[#chunks + 1] = { right[1] .. " ", right[2] or base }
  end
  return chunks
end

---@param d vim.Diagnostic
---@return string
local function source_of(d)
  local parts = {}
  if d.source and d.source ~= "" then
    parts[#parts + 1] = (d.source:gsub(":$", ""))
  end
  if d.code and d.code ~= "" then
    parts[#parts + 1] = tostring(d.code)
  end
  return table.concat(parts, " · ")
end

---@param buf integer
---@param win integer
---@param mode "expanded"|"compact"
local function render(buf, win, mode)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  local all = vim.diagnostic.get(buf)
  if #all == 0 then
    return
  end
  table.sort(all, function(a, b)
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return (a.severity or 9) < (b.severity or 9)
  end)

  local width = text_width(win)
  local cursor_lnum = vim.api.nvim_win_get_cursor(win)[1] - 1
  local line_count = vim.api.nvim_buf_line_count(buf)

  ---@type table<integer, table[]>
  local by_line = {}
  for i, d in ipairs(all) do
    local kind = KINDS[d.severity or SEV.HINT]
    local base = "DiagBlock" .. kind.name
    local indent = math.min(vim.fn.indent(math.min(d.lnum + 1, line_count)), MAX_INDENT)
    local inner = math.max(width - indent - 4, 20)
    local counter = { ("%d/%d"):format(i, #all), base .. "Meta" }
    local src = source_of(d)
    local lines = by_line[d.lnum] or {}
    by_line[d.lnum] = lines

    if mode == "compact" and d.lnum ~= cursor_lnum then
      local first = d.message:match "[^\n]*"
      local tail = src ~= "" and ("  " .. src) or ""
      local room = inner - vim.fn.strdisplaywidth(" " .. kind.icon .. "  " .. tail) - #counter[1] - 2
      lines[#lines + 1] = row(indent, width, base .. "Bar", base, {
        { " " .. kind.icon .. " ", base .. "Title" },
        { " ", base },
        { truncate(first, math.max(room, 10)), base },
        { tail, base .. "Meta" },
      }, counter)
    else
      local head = { { " " .. kind.icon .. " " .. kind.label .. " ", base .. "Title" } }
      if src ~= "" then
        head[#head + 1] = { " " .. src, base .. "Meta" }
      end
      lines[#lines + 1] = row(indent, width, base .. "Bar", base, head, counter)
      for _, text in ipairs(wrap(d.message, inner)) do
        lines[#lines + 1] = row(indent, width, base .. "Bar", base, { { text, base } })
      end
    end
  end

  for lnum, lines in pairs(by_line) do
    vim.api.nvim_buf_set_extmark(buf, NS, math.min(lnum, line_count - 1), 0, {
      virt_lines = lines,
      strict = false,
    })
  end
end

--- Guarda la severidad más alta de cada línea con diagnósticos y repinta la columna del número
--- (el git va aparte: una barra fina en la signcolumn)
---@param buf integer
local function numbers(buf)
  local worst = {}
  if settings().number and vim.bo[buf].buftype == "" then
    for _, d in ipairs(vim.diagnostic.get(buf)) do
      local sev = d.severity or SEV.HINT
      if not worst[d.lnum] or sev < worst[d.lnum] then
        worst[d.lnum] = sev
      end
    end
  end
  worst_by_buf[buf] = next(worst) and worst or nil
  if not pcall(vim.api.nvim__redraw, { buf = buf, statuscolumn = true }) then
    vim.cmd.redraw()
  end
end

--- Signo de la línea en UNA sola celda (el de mayor prioridad, de cualquier plugin; el git es la barra
--- `┃`). Con `signcolumn=yes` cada signo ocupa dos celdas (el texto + un hueco), de ahí el espacio de más.
---@param buf integer
---@param lnum integer 1-based
---@return string
local function sign_cell(buf, lnum)
  local best
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, { lnum - 1, 0 }, { lnum - 1, -1 }, {
    details = true,
    type = "sign",
  })) do
    local d = m[4]
    if d.sign_text and (not best or (d.priority or 0) > (best.priority or 0)) then
      best = d
    end
  end
  if not best then
    return "%#LineNr# "
  end
  local char = vim.fn.strcharpart(vim.trim(best.sign_text), 0, 1)
  return ("%%#%s#%s"):format(best.sign_hl_group or "LineNr", char == "" and " " or char:gsub("%%", "%%%%"))
end

--- Columna del número ('statuscolumn'): la píldora de la severidad se ajusta a los dígitos, con un
--- espacio a cada lado, así el número queda centrado; el hueco que sobra para alinear a la derecha
--- y el espacio hasta el código van sin fondo. Las líneas sin diagnóstico usan LineNr/CursorLineNr.
---@return string
function M.statuscolumn()
  -- al evaluarse, la ventana "actual" es la que se está pintando; `actual_curwin` es la que tiene el foco
  local win = vim.api.nvim_get_current_win()
  local wo = vim.wo[win]
  if not (wo.number or wo.relativenumber) then
    return ""
  end
  local lnum, virt = vim.v.lnum, vim.v.virtnum
  local buf = vim.api.nvim_win_get_buf(win)
  local width = #tostring(vim.api.nvim_buf_line_count(buf))
  -- con `signcolumn=no` el signo se dibuja aquí (una celda); con otro valor ya lo pone `%s`
  local own = wo.signcolumn == "no"
  -- línea partida por `wrap` o relleno virtual: solo el hueco, para no repetir el número
  if virt ~= 0 then
    return "%#LineNr#" .. (" "):rep(width + 2 + (own and 1 or 0))
  end
  local gutter = own and sign_cell(buf, lnum) or ""
  local shown = (wo.relativenumber and vim.v.relnum > 0) and vim.v.relnum or lnum
  local text = tostring(shown)
  local sev = worst_by_buf[buf] and worst_by_buf[buf][lnum - 1]
  local current = vim.v.relnum == 0 and tostring(win) == tostring(vim.g.actual_curwin)
  local pad = (" "):rep(math.max(0, width - #text))
  if sev then
    return ("%s%%#LineNr#%s%%#DiagNumber%s# %s %%#LineNr# "):format(gutter, pad, KINDS[sev].name, text)
  end
  return ("%s%%#%s#%s %s  "):format(gutter, current and "CursorLineNr" or "LineNr", pad, text)
end

--- ¿Se está escribiendo en este buffer sin que `update_in_insert` pida diagnósticos en vivo?
---@param buf integer
---@return boolean
local function typing(buf)
  return vim.api.nvim_get_current_buf() == buf
    and vim.fn.mode():find "^[iR]" ~= nil
    and not vim.diagnostic.config().update_in_insert
end

local function redraw(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  require("ui.diagcolors").sync()
  -- en modo insertar nada cambia ni empuja el código: los bloques se ocultan y el número se queda
  -- como estaba; al salir (InsertLeave) se pinta todo con los diagnósticos ya asentados
  if typing(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    return
  end
  numbers(buf)
  local mode = active[buf]
  if not mode then
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    return
  end
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    render(buf, win, mode)
  end
end

-- ── API ──────────────────────────────────────────────────────────────────────

local group

local function ensure_autocmds()
  if group then
    return
  end
  require("ui.diagcolors").on_change(function()
    apply_highlights()
    for buf in pairs(active) do
      redraw(buf)
    end
  end)
  group = vim.api.nvim_create_augroup("DiagBlocks", { clear = true })
  local pending = {}
  local function schedule(buf)
    if pending[buf] then
      return
    end
    pending[buf] = true
    vim.schedule(function()
      pending[buf] = nil
      redraw(buf)
    end)
  end
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function(ev)
      local buf = ev.buf
      if vim.bo[buf].buftype ~= "" then
        return
      end
      if not active[buf] and prefs.enabled and #vim.diagnostic.get(buf) > 0 then
        active[buf] = prefs.mode
      end
      schedule(buf)
    end,
  })
  -- al empezar a escribir los bloques se ocultan; al salir se repintan con lo último del LSP
  vim.api.nvim_create_autocmd({ "InsertEnter", "InsertLeave" }, {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].buftype == "" then
        schedule(ev.buf)
      end
    end,
  })
  -- un buffer oculto no se pinta: al volver a mostrarse se repinta
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
    group = group,
    callback = function(ev)
      if active[ev.buf] then
        schedule(ev.buf)
      end
    end,
  })
  -- en compact el bloque abierto sigue al cursor: solo se repinta al cambiar de línea
  local last = {}
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    callback = function(ev)
      local buf = ev.buf
      if active[buf] ~= "compact" then
        return
      end
      local lnum = vim.api.nvim_win_get_cursor(0)[1]
      if last[buf] ~= lnum then
        last[buf] = lnum
        schedule(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = function()
      for buf in pairs(active) do
        schedule(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      active[ev.buf] = nil
      worst_by_buf[ev.buf] = nil
    end,
  })
  -- vim.schedule: al cambiar de tema, base46 termina de definir los `Diagnostic*` justo después del
  -- evento; si se leyeran antes, el acento sería el del tema anterior y no coincidiría con la barra
  local function reapply()
    vim.schedule(function()
      apply_highlights()
      for buf in pairs(active) do
        schedule(buf)
      end
    end)
  end
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = reapply })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = "NvThemeReload", callback = reapply })
end

--- Aplica las preferencias a todos los buffers cargados (vista y modo)
local function apply_all()
  ensure_autocmds()
  apply_highlights()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
      active[buf] = prefs.enabled and #vim.diagnostic.get(buf) > 0 and prefs.mode or nil
      redraw(buf)
    end
  end
end

---@param buf integer
---@return boolean
local function has_diagnostics(buf)
  if #vim.diagnostic.get(buf) > 0 then
    return true
  end
  vim.notify("No diagnostics in this buffer", vim.log.levels.INFO)
  return false
end

--- Muestra/oculta los bloques (queda guardado para la próxima sesión; apagados, solo se tiñe el número de línea)
function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  if not active[buf] and not has_diagnostics(buf) then
    return
  end
  prefs.enabled = not active[buf]
  save_prefs()
  apply_all()
end

--- Alterna entre todos desplegados y uno por uno (enciende la vista; queda guardado)
function M.toggle_compact()
  if not has_diagnostics(vim.api.nvim_get_current_buf()) then
    return
  end
  prefs.enabled = true
  prefs.mode = prefs.mode == "compact" and "expanded" or "compact"
  save_prefs()
  apply_all()
end

--- Salta al diagnóstico siguiente/anterior; con la vista apagada la enciende solo en este buffer,
--- en compact y sin tocar tus preferencias
---@param step 1|-1
function M.step(step)
  local buf = vim.api.nvim_get_current_buf()
  if not has_diagnostics(buf) then
    return
  end
  if not active[buf] then
    ensure_autocmds()
    apply_highlights()
    active[buf] = "compact"
  end
  vim.diagnostic.jump { count = step, wrap = true }
  redraw(buf)
end

--- Carga las preferencias guardadas y registra los autocmds
function M.setup()
  load_prefs()
  apply_all()
end

return M
