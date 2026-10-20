-- ── General keymaps (independent of language and plugins) ────────────────────
local M = {}

-- <leader>q: closes the current buffer; if no file buffer is left, quits nvim
-- (`confirm qa` asks if there are unsaved changes).
local function close_or_quit()
  local cur = vim.api.nvim_get_current_buf()

  -- special windows (nvim-tree, help, quickfix...): only close the window
  if vim.bo[cur].buftype ~= "" and vim.bo[cur].filetype ~= "nvdash" then
    if #vim.api.nvim_tabpage_list_wins(0) > 1 and pcall(vim.cmd, "close") then
      return
    end
    return vim.cmd "confirm qa"
  end

  local files = vim.tbl_filter(function(b)
    return b.listed == 1 and vim.bo[b.bufnr].buftype == ""
  end, vim.fn.getbufinfo { buflisted = 1 })

  -- dashboard or last file: nothing else to close
  if vim.bo[cur].filetype == "nvdash" or #files <= 1 then
    return vim.cmd "confirm qa"
  end

  -- NvChad's tabufline is disabled (vim.t.bufs does not exist): switch to another
  -- listed file and delete the current one without touching the windows.
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

  -- with unsaved changes, `confirm bdelete` asks first and nothing is moved beforehand
  if alt and not vim.bo[cur].modified then
    for _, win in ipairs(vim.fn.win_findbuf(cur)) do
      vim.api.nvim_win_set_buf(win, alt)
    end
  end
  -- without `!`: asks if there are unsaved changes
  local ok, err = pcall(vim.cmd, "confirm bdelete " .. cur)
  if not ok and not err:find "Keyboard interrupt" then
    vim.notify(err, vim.log.levels.WARN)
  end
end

function M.setup()
  local map = vim.keymap.set

  map("n", ";", ":", { desc = "General command mode (; instead of :)" })
  -- jk = Esc, but with the completion menu open it only closes it (like Esc in blink)
  map("i", "jk", function()
    local ok, cmp = pcall(require, "blink.cmp")
    if not (ok and cmp.cancel()) then
      vim.api.nvim_feedkeys(vim.keycode "<Esc>", "n", false)
    end
  end, { desc = "General leave insert (closes the completion menu first)" })
  map("n", "<leader>w", "<cmd>w<CR>", { desc = "General save" })
  map("n", "<leader>q", close_or_quit, { desc = "General close buffer / quit" })

  -- <leader>d: delete WITHOUT copying ("_" register): the clipboard stays intact.
  -- Visual: <leader>d | Normal: <leader>dd (line), <leader>dw (word), etc.
  map({ "n", "v" }, "<leader>d", '"_d', { desc = "General delete without copying" })

  -- Diagnostics (<leader>x): line popup, inline blocks for the whole buffer and walking
  -- through them one by one (utils/diagblocks.lua); the bottom panel is Trouble (<leader>xx)
  local diag = require "utils.diagblocks"
  map("n", "<leader>xd", diag.popup, { desc = "Diagnostics line popup (press again to enter)" })
  map("n", "<leader>xa", diag.toggle, { desc = "Diagnostics blocks inline (toggle)" })
  map("n", "<leader>xc", diag.toggle_compact, { desc = "Diagnostics blocks collapse / expand" })
  map("n", "<leader>xn", function()
    diag.step(1)
  end, { desc = "Diagnostics next block" })
  map("n", "<leader>xp", function()
    diag.step(-1)
  end, { desc = "Diagnostics previous block" })
  -- copy them as text (utils/diagcopy.lua): the cursor line, this file, every open file
  for key, scope in pairs { l = "line", f = "file", e = "all" } do
    map("n", "<leader>x" .. key, function()
      require("utils.diagcopy").copy(scope)
    end, { desc = "Diagnostics copy " .. scope })
  end

  -- <Esc> closes whatever is in the way: the diagnostic popup, the agent's answer, the extra window you are in (a float,
  -- help, quickfix, a panel), stray floats; then goes back after gd / grr and clears the search highlight (utils/escape.lua)
  map("n", "<Esc>", function()
    require("utils.escape").dismiss()
  end, { desc = "General close extra window / go back / clear highlight" })
  map("n", "<leader>H", function()
    require("utils.navigation").history_picker()
  end, { desc = "Find file history (session)" })
  map("n", "<leader>fo", function()
    require("recent").open()
  end, { desc = "Find recent files of this project" })
  map("n", "<leader>fs", function()
    require("codesearch").open()
  end, { desc = "Find project symbols" })

  -- CTRL+click → go to definition (LSP); <Esc> or <C-o> goes back, <C-i> forward
  map(
    "n",
    "<C-LeftMouse>",
    require("utils.lsp").goto_definition_at_mouse,
    { desc = "LSP go to DEFINITION (Ctrl+click)" }
  )
end

return M
