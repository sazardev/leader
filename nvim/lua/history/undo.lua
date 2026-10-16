-- ── Undo and redo ────────────────────────────────────────────────────────────
-- Vim undoes a whole insert at once: type a paragraph, press u, all of it is gone. Here an insert is split like
-- VS Code does: a new undo step starts after each whitespace, after a new line (Enter, a snippet, a paste) and after
-- a pause (`settings.history.pause_ms`). The break is Vim's own `<C-g>u`, fed only when nothing else is waiting in
-- the typeahead: while a macro or `.` replays (or you type faster than nvim runs) the keys after it would turn the
-- `<C-g>u` into a NORMAL-mode `u`. `.` still repeats the whole insert. Undo and redo flash what they changed.
local M = {}

local BREAK = vim.keycode "<C-g>u"

---@return table
local function settings()
  return require("core.settings").history or {}
end

--- Pure: does an undo step end here? `before` is the character left of the cursor, `lines` / `last_lines` the
--- buffer's line count now and at the previous change.
---@param before string
---@param lines integer
---@param last_lines integer?
---@return boolean
function M.boundary(before, lines, last_lines)
  if last_lines and lines ~= last_lines then
    return true
  end
  return before:match "^%s$" ~= nil
end

--- Feeds the break if it is safe right now (insert mode, nothing queued, no macro replaying)
local function close_step()
  if vim.api.nvim_get_mode().mode ~= "i" or vim.fn.reg_executing() ~= "" or vim.fn.getchar(1) ~= 0 then
    return
  end
  vim.api.nvim_feedkeys(BREAK, "ni", false)
end

local last_lines ---@type integer?
local timer ---@type uv.uv_timer_t?

local function on_change()
  local opts = settings()
  if not opts.word_undo then
    return
  end
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local lines = vim.api.nvim_buf_line_count(0)
  local before = col > 0 and vim.api.nvim_get_current_line():sub(col, col) or ""
  if M.boundary(before, lines, last_lines) then
    close_step()
  end
  last_lines = lines

  local pause = opts.pause_ms or 0
  if pause > 0 then
    timer = timer or vim.uv.new_timer()
    timer:stop()
    timer:start(pause, 0, vim.schedule_wrap(close_step))
  end
end

--- Flashes the lines the last undo/redo touched ('[ and '] marks), like a yank
local function flash()
  if not require("ui.flat").enabled() then
    return
  end
  local s, e = vim.api.nvim_buf_get_mark(0, "["), vim.api.nvim_buf_get_mark(0, "]")
  if s[1] > 0 and e[1] >= s[1] then
    require("ui.flat.fresh").lines(0, s[1] - 1, e[1])
  end
end

--- `u` / redo with a count, then the flash. Silent: "1 change; before #12 3 seconds ago" is noise; the flash says it.
---@param cmd "u"|"\18"
local function step(cmd)
  return function()
    local count = vim.v.count1
    local before = vim.fn.undotree().seq_cur
    local ok, err = pcall(vim.cmd, "silent normal! " .. count .. cmd)
    if not ok then
      return vim.notify((tostring(err):gsub("^.-:%s*", "")), vim.log.levels.WARN)
    end
    if vim.fn.undotree().seq_cur == before then
      local edge = cmd == "u" and "oldest" or "newest"
      return vim.api.nvim_echo({ { "Already at the " .. edge .. " change" } }, false, {})
    end
    flash()
  end
end

M.undo = step "u"
M.redo = step "\18"

--- The undo tree of this buffer (Neovim's built-in one): moving in it moves the buffer through its history, `q` closes
function M.tree()
  vim.cmd "packadd nvim.undotree"
  local src = vim.api.nvim_get_current_buf()
  require("undotree").open {
    command = "botright " .. math.max(30, math.floor(vim.o.columns * 0.25)) .. "vnew",
    title = function(buf)
      return "Undo history: " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
    end,
  }
  local win = vim.b[src].nvim_undotree
  if win and vim.api.nvim_win_is_valid(win) then
    local buf = vim.api.nvim_win_get_buf(win)
    for _, lhs in ipairs { "q", "<Esc>" } do
      vim.keymap.set("n", lhs, function()
        pcall(vim.api.nvim_win_close, win, true)
      end, { buffer = buf, desc = "History close undo tree" })
    end
  end
end

--- The file as it was at the previous (-1) / next (1) save: Vim's `:earlier 1f` / `:later 1f`, itself undoable
---@param dir -1|1
function M.save_step(dir)
  local ok, err = pcall(vim.cmd, "silent " .. (dir < 0 and "earlier" or "later") .. " " .. vim.v.count1 .. "f")
  if not ok then
    return vim.notify((tostring(err):gsub("^.-:%s*", "")), vim.log.levels.WARN)
  end
  flash()
  vim.api.nvim_echo({ { dir < 0 and "Back to the previous save" or "Forward to the next save" } }, false, {})
end

function M.setup()
  local group = vim.api.nvim_create_augroup("HistoryUndo", { clear = true })
  vim.api.nvim_create_autocmd("InsertEnter", {
    group = group,
    callback = function()
      last_lines = vim.api.nvim_buf_line_count(0)
    end,
  })
  vim.api.nvim_create_autocmd("TextChangedI", { group = group, callback = on_change })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    callback = function()
      if timer then
        timer:stop()
      end
    end,
  })
end

return M
