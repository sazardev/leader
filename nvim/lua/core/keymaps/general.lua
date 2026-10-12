-- ── Keymaps generales (no dependen de lenguaje ni de plugins) ────────────────
local M = {}

-- <leader>q: cierra el buffer actual; si ya no queda ninguno de archivo, sale de nvim
-- (`confirm qa` pregunta si hay cambios sin guardar).
local function close_or_quit()
  local cur = vim.api.nvim_get_current_buf()

  -- ventanas especiales (nvim-tree, help, quickfix...): solo cierra la ventana
  if vim.bo[cur].buftype ~= "" and vim.bo[cur].filetype ~= "nvdash" then
    if #vim.api.nvim_tabpage_list_wins(0) > 1 and pcall(vim.cmd, "close") then
      return
    end
    return vim.cmd "confirm qa"
  end

  local files = vim.tbl_filter(function(b)
    return b.listed == 1 and vim.bo[b.bufnr].buftype == ""
  end, vim.fn.getbufinfo { buflisted = 1 })

  -- dashboard o último archivo: no hay nada más que cerrar
  if vim.bo[cur].filetype == "nvdash" or #files <= 1 then
    return vim.cmd "confirm qa"
  end

  -- tabufline de NvChad está desactivado (vim.t.bufs no existe): se cambia a otro
  -- archivo listado y se borra el actual sin tocar las ventanas.
  local alt = vim.fn.bufnr "#"
  if alt == cur or alt < 1 or vim.fn.buflisted(alt) == 0 or vim.bo[alt].buftype ~= "" then
    alt = nil
    for _, b in ipairs(files) do
      if b.bufnr ~= cur then
        alt = b.bufnr
        break
      end
    end
  end

  -- con cambios sin guardar, `confirm bdelete` pregunta primero y no se mueve nada antes
  if alt and not vim.bo[cur].modified then
    for _, win in ipairs(vim.fn.win_findbuf(cur)) do
      vim.api.nvim_win_set_buf(win, alt)
    end
  end
  -- sin `!`: pregunta si hay cambios sin guardar
  local ok, err = pcall(vim.cmd, "confirm bdelete " .. cur)
  if not ok and not err:find "Keyboard interrupt" then
    vim.notify(err, vim.log.levels.WARN)
  end
end

function M.setup()
  local map = vim.keymap.set

  map("n", ";", ":", { desc = "General command mode (; instead of :)" })
  map("i", "jk", "<ESC>")
  map("n", "<leader>w", "<cmd>w<CR>", { desc = "General save" })
  map("n", "<leader>q", close_or_quit, { desc = "General close buffer / quit" })

  -- <leader>d: borrar SIN copiar (registro "_"): el portapapeles queda intacto.
  -- Visual: <leader>d | Normal: <leader>dd (línea), <leader>dw (palabra), etc.
  map({ "n", "v" }, "<leader>d", '"_d', { desc = "General delete without copying" })

  -- Diagnóstico de la línea actual en un popup (como el hover de las docs); pulsarlo
  -- otra vez entra al popup para copiar o hacer scroll
  local diag_win
  map("n", "<leader>xd", function()
    local _, win = vim.diagnostic.open_float { border = "single", source = true }
    diag_win = win
  end, { desc = "Diagnostics line popup (press again to enter)" })

  -- <Esc>: primero cierra el popup de diagnóstico si está abierto; luego, tras
  -- gd / grr / Ctrl+click vuelve a donde estabas (si no editaste ahí);
  -- si no aplica, hace lo de NvChad (quitar el resaltado de búsqueda)
  map("n", "<Esc>", function()
    if diag_win and vim.api.nvim_win_is_valid(diag_win) then
      vim.api.nvim_win_close(diag_win, true)
      diag_win = nil
      return
    end
    if not require("utils.navigation").back() then
      vim.cmd "noh"
    end
  end, { desc = "General go back after jump / clear highlight" })
  map("n", "<leader>H", function()
    require("utils.navigation").history_picker()
  end, { desc = "Find file history (session)" })

  -- Multicursor nativo (sin plugin): Ctrl+↓/↑ abre un bloque visual y lo extiende línea a
  -- línea; luego `I` (insertar al inicio), `A` (al final), `c` (cambiar) o `$A` (fin de
  -- cada línea) escriben en TODAS las líneas a la vez. <Esc> sale.
  map("n", "<C-Down>", "<C-v>j", { desc = "Multicursor block down" })
  map("n", "<C-Up>", "<C-v>k", { desc = "Multicursor block up" })
  map("x", "<C-Down>", "j", { desc = "Multicursor extend down" })
  map("x", "<C-Up>", "k", { desc = "Multicursor extend up" })

  -- CTRL+click → ir a definición (LSP); <Esc> o <C-o> vuelve atrás, <C-i> adelante
  map(
    "n",
    "<C-LeftMouse>",
    require("utils.lsp").goto_definition_at_mouse,
    { desc = "LSP go to DEFINITION (Ctrl+click)" }
  )
end

return M
