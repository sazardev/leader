-- ── Modales flotantes ────────────────────────────────────────────────────────
-- Mismo estilo que la terminal flotante (borde "single", centrado, con título).
-- Colores: grupos del tema (base46), así que cambian con el tema activo.
--
-- Cada línea es un string, o una lista de segmentos { text, hl } para pintar
-- partes distintas de la misma línea (p. ej. carpeta en un color, marca en otro).
--
-- M.input   → texto + campo editable (Enter confirma, Esc cancela)
-- M.confirm → texto + [y] / [n] (solo y confirma, cualquier otra tecla cancela)
local M = {}

-- Grupos del modal → grupos del tema (ver base46/integrations/nvimtree.lua)
local GROUPS = {
  NvModalFolder = { link = "NvimTreeFolderName" },
  NvModalFile = { link = "Normal" },
  NvModalTree = { link = "NvimTreeIndentMarker" },
  NvModalMark = { link = "NvimTreeSpecialFile" },
  NvModalWarn = { link = "DiagnosticWarn" },
  NvModalKey = { link = "Special" },
  NvModalMuted = { link = "Comment" },
}
for name, def in pairs(GROUPS) do
  vim.api.nvim_set_hl(0, name, { link = def.link, default = true })
end
M.hl = { folder = "NvModalFolder", file = "NvModalFile", tree = "NvModalTree", mark = "NvModalMark", warn = "NvModalWarn", key = "NvModalKey", muted = "NvModalMuted" }

local NS = vim.api.nvim_create_namespace "NvModal"

---@param line string|table[]
---@return string
local function plain(line)
  if type(line) == "string" then
    return line
  end
  local parts = {}
  for _, seg in ipairs(line) do
    parts[#parts + 1] = seg[1]
  end
  return table.concat(parts)
end

---@param lines string[]
---@return integer
local function width_of(lines)
  local w = 0
  for _, l in ipairs(lines) do
    w = math.max(w, vim.fn.strdisplaywidth(plain(l)))
  end
  return math.min(math.max(w + 4, 44), vim.o.columns - 4)
end

---@param buf integer
---@param lines (string|table[])[]
local function paint(buf, lines)
  for i, line in ipairs(lines) do
    if type(line) == "table" then
      local col = 0
      for _, seg in ipairs(line) do
        local text, hl = seg[1], seg[2]
        if hl then
          vim.api.nvim_buf_set_extmark(buf, NS, i - 1, col, { end_col = col + #text, hl_group = hl })
        end
        col = col + #text
      end
    end
  end
end

---@param lines (string|table[])[]
---@param opts { title?: string, editable?: boolean }
---@return integer buf, integer win, function close
local function open(lines, opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local text = vim.tbl_map(plain, lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  paint(buf, lines)
  vim.bo[buf].modifiable = opts.editable or false

  local width = width_of(lines)
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "single",
    title = opts.title and (" %s "):format(opts.title) or nil,
    title_pos = "center",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, desc = "Close" })
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, desc = "Close" })
  return buf, win, close
end

---@param lines (string|table[])[]
---@param opts { title?: string }
---@param on_submit fun(text: string)
function M.input(lines, opts, on_submit)
  local prompt = "> "
  vim.list_extend(lines, { "", { { prompt, M.hl.key } } })
  local buf, win, close = open(lines, { title = opts.title, editable = true })
  local last = #lines

  vim.api.nvim_win_set_cursor(win, { last, #prompt })
  vim.b[buf].completion = false -- blink no debe sugerir nada en un campo de texto libre
  vim.cmd "startinsert!"

  -- Al cerrar hay que salir de insert: `startinsert!` dejaría el modo insert activo en la ventana
  -- de código a la que se vuelve, y lo siguiente que teclees se escribiría en tu archivo.
  local function leave()
    close()
    vim.cmd "stopinsert"
  end

  local function submit()
    local text = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1]:sub(#prompt + 1)
    leave()
    on_submit(vim.trim(text))
  end
  vim.keymap.set({ "i", "n" }, "<CR>", submit, { buffer = buf, nowait = true, desc = "Submit" })
  vim.keymap.set("i", "<Esc>", leave, { buffer = buf, nowait = true, desc = "Close" })
end

---@param lines (string|table[])[]
---@param opts { title?: string }
---@param on_yes fun()
function M.confirm(lines, opts, on_yes)
  vim.list_extend(lines, {
    "",
    { { "[y]", M.hl.key }, { " yes    " }, { "[n / q / <Esc>]", M.hl.key }, { " no", M.hl.muted } },
  })
  local buf, _, close = open(lines, { title = opts.title })

  vim.keymap.set("n", "n", close, { buffer = buf, nowait = true, desc = "Cancel" })
  vim.keymap.set("n", "y", function()
    close()
    on_yes()
  end, { buffer = buf, nowait = true, desc = "Confirm" })
end

return M
