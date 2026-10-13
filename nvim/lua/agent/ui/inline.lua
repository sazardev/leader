-- ── Campo de instrucción EN LÍNEA (estilo Zed / VS Code inline chat) ─────────
-- Un bloque compacto que se abre justo encima del código objetivo y EMPUJA el código hacia
-- abajo (líneas virtuales como hueco) en vez de tapar nada: cabecera con acción y modelo,
-- placeholder, crece al escribir (envuelve), ↑/↓ recuperan instrucciones anteriores.
-- La ventana es un flotante anclado a la línea del objetivo; el hueco que ocupa lo reserva
-- un extmark con `virt_lines_above`, así que los dos siempre miden lo mismo.
require("agent.ui.highlights").ensure()

local M = {}

local NS = vim.api.nvim_create_namespace "agent.inline"
local MAX_ROWS = 6

---@class AgentInlineState
---@field win integer       ventana de código
---@field buf integer       buffer de código
---@field input_win integer
---@field input_buf integer
---@field spacer integer    extmark del hueco
---@field rows integer      filas de texto (sin cabecera)
---@field width integer
---@field closed boolean
---@field history string[]
---@field cursor integer    posición en el historial (0 = lo que estás escribiendo)
---@field draft string

---@type AgentInlineState?
local current

---@param win integer
---@return integer
local function text_width(win)
  return vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
end

--- Garantiza que haya `need` filas visibles encima de la línea (si no, desplaza la vista)
---@param win integer
---@param row integer 1-based
---@param need integer
local function reserve(win, row, need)
  vim.api.nvim_win_call(win, function()
    for _ = 1, 2 do
      local above = vim.fn.screenpos(win, row, 1).row - vim.fn.getwininfo(win)[1].winrow
      if above >= need then
        return
      end
      local view = vim.fn.winsaveview()
      if view.topline <= 1 then
        return
      end
      view.topline = math.max(1, view.topline - (need - above))
      vim.fn.winrestview(view)
    end
  end)
end

---@param st AgentInlineState
local function set_spacer(st, height)
  local blank = { { (" "):rep(vim.o.columns), "AgentInput" } }
  local lines = {}
  for i = 1, height do
    lines[i] = blank
  end
  st.spacer = vim.api.nvim_buf_set_extmark(st.buf, NS, st.row - 1, 0, {
    id = st.spacer,
    virt_lines = lines,
    virt_lines_above = true,
    strict = false,
  })
end

---@param st AgentInlineState
---@return string
local function header(st, opts)
  local function esc(text)
    return (text:gsub("%%", "%%%%"))
  end
  local left = (" ✦ %s · %s "):format(opts.title, opts.meta)
  -- la pista más larga que quepa junto a la cabecera; si ni la corta cabe, se omite
  local hints = { "⏎ run · ⌃J newline · ↑ history · ⎋ cancel", "⏎ run · ⎋ cancel", "⏎ run" }
  local hint = ""
  for _, candidate in ipairs(hints) do
    if vim.fn.strdisplaywidth(left) + vim.fn.strdisplaywidth(candidate) + 2 <= st.width then
      hint = candidate
      break
    end
  end
  return ("%%#AgentInputTitle# ✦ %s %%#AgentInputMeta#· %s%%=%%#AgentInputHint#%s "):format(
    esc(opts.title),
    esc(opts.meta),
    esc(hint)
  )
end

--- Recalcula alto (según lo escrito), ancho y placeholder
---@param st AgentInlineState
local function relayout(st)
  if st.closed or not vim.api.nvim_win_is_valid(st.input_win) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(st.input_buf, 0, -1, false)
  local rows = 0
  for _, l in ipairs(lines) do
    rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / st.width))
  end
  rows = math.min(math.max(rows, 1), MAX_ROWS)

  if rows ~= st.rows then
    st.rows = rows
    reserve(st.win, st.row, rows + 2)
    set_spacer(st, rows + 1)
    vim.api.nvim_win_set_config(st.input_win, { height = rows + 1 })
  end

  vim.api.nvim_buf_clear_namespace(st.input_buf, NS, 0, -1)
  if #lines == 1 and lines[1] == "" then
    vim.api.nvim_buf_set_extmark(st.input_buf, NS, 0, 0, {
      virt_text = { { st.placeholder, "AgentInputPlaceholder" } },
      virt_text_pos = "overlay",
    })
  end
end

---@param st AgentInlineState
local function close(st)
  if st.closed then
    return
  end
  st.closed = true
  current = nil
  pcall(vim.api.nvim_buf_del_extmark, st.buf, NS, st.spacer)
  if vim.api.nvim_win_is_valid(st.input_win) then
    vim.api.nvim_win_close(st.input_win, true)
  end
  if vim.api.nvim_win_is_valid(st.win) then
    vim.api.nvim_set_current_win(st.win)
  end
  vim.cmd "stopinsert"
end

---@param st AgentInlineState
---@param text string
local function set_text(st, text)
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(st.input_buf, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(st.input_win, { #lines, #lines[#lines] })
  relayout(st)
end

--- Parte la línea en el cursor (salto de línea sin enviar)
---@param st AgentInlineState
local function newline(st)
  local row, col = unpack(vim.api.nvim_win_get_cursor(st.input_win))
  local line = vim.api.nvim_buf_get_lines(st.input_buf, row - 1, row, false)[1]
  vim.api.nvim_buf_set_lines(st.input_buf, row - 1, row, false, { line:sub(1, col), line:sub(col + 1) })
  vim.api.nvim_win_set_cursor(st.input_win, { row + 1, 0 })
  relayout(st)
end

--- ↑/↓: recorre el historial; 0 es lo que estabas escribiendo
---@param st AgentInlineState
---@param step integer
local function recall(st, step)
  local target = st.cursor + step
  if target < 0 or target > #st.history then
    return
  end
  if st.cursor == 0 then
    st.draft = table.concat(vim.api.nvim_buf_get_lines(st.input_buf, 0, -1, false), "\n")
  end
  st.cursor = target
  set_text(st, target == 0 and st.draft or st.history[target])
end

---@class AgentInlineOpts
---@field win integer
---@field row integer 1-based: el bloque se abre ENCIMA de esta línea
---@field title string
---@field meta string
---@field placeholder string
---@field history string[]?
---@field optional boolean? Enter con el campo vacío envía "" (si no, no hace nada)

---@param opts AgentInlineOpts
---@param on_submit fun(text: string)
function M.open(opts, on_submit)
  if current then
    close(current)
  end

  local width = text_width(opts.win)
  local st = {
    win = opts.win,
    buf = vim.api.nvim_win_get_buf(opts.win),
    row = opts.row,
    rows = 1,
    width = width,
    closed = false,
    history = opts.history or {},
    cursor = 0,
    draft = "",
    placeholder = opts.placeholder,
  }
  current = st

  reserve(st.win, st.row, 4)
  set_spacer(st, 2)

  st.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[st.input_buf].bufhidden = "wipe"
  vim.bo[st.input_buf].filetype = "agentprompt"
  vim.b[st.input_buf].completion = false -- blink no sugiere nada en un campo de texto libre
  vim.b[st.input_buf].minipairs_disable = true -- ni se cierran comillas/paréntesis solos
  pcall(vim.api.nvim_buf_set_name, st.input_buf, "agent prompt") -- en la statusline, en vez de [No Name]

  st.input_win = vim.api.nvim_open_win(st.input_buf, true, {
    relative = "win",
    win = st.win,
    bufpos = { st.row - 1, 0 },
    anchor = "SW",
    row = 0,
    col = -1, -- la barra de acento cae en el borde del margen, justo antes del texto
    width = width,
    height = 2,
    style = "minimal",
    border = { "", "", "", "", "", "", "", "▎" },
    zindex = 60,
  })
  local wo = vim.wo[st.input_win]
  wo.wrap = true
  wo.linebreak = true
  wo.spell = false
  wo.winbar = header(st, opts)
  wo.winhighlight = table.concat({
    "Normal:AgentInput",
    "NormalFloat:AgentInput",
    "FloatBorder:AgentInputBar",
    "WinBar:AgentInput",
    "WinBarNC:AgentInput",
  }, ",")

  relayout(st)

  local function submit()
    local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(st.input_buf, 0, -1, false), "\n"))
    if text == "" and not opts.optional then
      return
    end
    close(st)
    on_submit(text)
  end
  local function cancel()
    close(st)
  end

  local map = function(modes, lhs, fn)
    vim.keymap.set(modes, lhs, fn, { buffer = st.input_buf, nowait = true })
  end
  map({ "i", "n" }, "<CR>", submit)
  map({ "i", "n" }, "<Esc>", cancel)
  map({ "i", "n" }, "<C-c>", cancel)
  map({ "i", "n" }, "<C-p>", function()
    recall(st, 1)
  end)
  map({ "i", "n" }, "<C-n>", function()
    recall(st, -1)
  end)
  -- ↑/↓ recorren el historial solo mientras el texto cabe en una línea (si no, mueven el cursor)
  map({ "i", "n" }, "<Up>", function()
    if vim.api.nvim_buf_line_count(st.input_buf) == 1 then
      recall(st, 1)
    else
      vim.cmd "normal! k"
    end
  end)
  map({ "i", "n" }, "<Down>", function()
    if vim.api.nvim_buf_line_count(st.input_buf) == 1 then
      recall(st, -1)
    else
      vim.cmd "normal! j"
    end
  end)
  vim.keymap.set("i", "jk", "jk", { buffer = st.input_buf, remap = false }) -- el `jk` global saldría de insert: aquí es texto
  -- NvChad mapea <C-j> a "bajar" en insert: aquí es salto de línea (y también Alt/Shift+Enter)
  map("i", "<C-j>", function()
    newline(st)
  end)
  map("i", "<A-CR>", function()
    newline(st)
  end)
  map("i", "<S-CR>", function()
    newline(st)
  end)

  local group = vim.api.nvim_create_augroup("AgentInline", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = st.input_buf,
    callback = function()
      relayout(st)
    end,
  })
  vim.api.nvim_create_autocmd("WinLeave", { group = group, buffer = st.input_buf, callback = cancel })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if not st.closed and vim.api.nvim_win_is_valid(st.win) then
        st.width = text_width(st.win)
        vim.api.nvim_win_set_config(st.input_win, { width = st.width })
        vim.wo[st.input_win].winbar = header(st, opts)
        relayout(st)
      end
    end,
  })

  vim.cmd "startinsert"
end

return M
