-- ── Integrated terminal (toggleterm) ─────────────────────────────────────────
-- Position and size come from settings.terminal and are recalculated on every open
-- and when the window is resized (responsive).
local settings = require "core.settings"

local M = {}

--- toggleterm direction according to the current screen width
---@return "vertical"|"horizontal"|"float"
function M.direction()
  local cfg = settings.terminal
  if cfg.position == "float" then
    return "float"
  end
  if cfg.position == "bottom" or vim.o.columns < cfg.narrow_columns then
    return "horizontal"
  end
  return "vertical"
end

--- Size (columns or lines) for a toggleterm terminal
---@param term { direction: string }
---@return number
function M.size(term)
  local cfg = settings.terminal
  if term.direction == "vertical" then
    return math.max(cfg.min_width, math.floor(vim.o.columns * cfg.width))
  end
  return math.max(cfg.min_height, math.floor(vim.o.lines * cfg.height))
end

--- Adjust open terminals after a window resize
function M.refresh()
  for _, term in pairs(require("toggleterm.terminal").get_all()) do
    if term:is_open() and term:is_split() then
      -- toggleterm resizes the current window: it has to be done from the terminal's window
      vim.api.nvim_win_call(term.window, function()
        term:resize(M.size(term))
      end)
    end
  end
end

--- Keys of a terminal buffer, the same for toggleterm's and NvChad's: Esc closes the window (`close`; the
--- shell keeps running), Shift+Esc only hands the focus back to the previous window and leaves the terminal open
---@param buf integer
---@param close fun()
function M.attach_keys(buf, close)
  local function map(lhs, rhs, desc)
    vim.keymap.set({ "n", "t" }, lhs, rhs, { buffer = buf, desc = desc })
  end
  map("<Esc>", close, "Terminal close (Esc)")
  map("<S-Esc>", function()
    vim.cmd "stopinsert"
    -- toggleterm closes its floats on WinLeave: skip that event for this one jump so the terminal stays
    local ignore = vim.o.eventignore
    vim.opt.eventignore:append "WinLeave"
    pcall(vim.cmd, "wincmd p")
    vim.o.eventignore = ignore
  end, "Terminal unfocus (Shift+Esc)")
end

--- Run `cmd` in the integrated terminal with cwd `dir`, leaving the cursor in it (Esc closes the window).
--- Through toggleterm's Lua API (not `:TermExec cmd='...'`): the command line parser of `:TermExec` cuts the
--- command at the first inner single quote, so any command with a quoted path (`dotnet run --project '/a b/x.csproj'`)
--- arrived truncated (`dotnet run --project \`). The API takes `cmd` as one value, no parsing involved.
---@param cmd string
---@param dir string
function M.run(cmd, dir)
  local direction = M.direction()
  -- a closed terminal keeps its previous direction: we update it
  for _, term in pairs(require("toggleterm.terminal").get_all()) do
    if not term:is_open() then
      term.direction = direction
    end
  end
  -- go_back = false: toggleterm's default sends the command and hands the focus back to the editor, which left
  -- the cursor OUTSIDE the terminal you just asked to run something in (and Esc, the terminal's own key, did
  -- nothing there). Passing false keeps it in the terminal: it is focused (or opened) and ready to type.
  require("toggleterm").exec(cmd, nil, nil, dir, direction, nil, false)
  -- going back to an already open terminal only moves the window: enter terminal mode explicitly
  if vim.bo.buftype == "terminal" then
    pcall(vim.cmd, "startinsert")
  end
end

--- The dedicated terminals, one per `name` (the app keeps running in its own while something else uses theirs)
local named_terms = {}

---@param name string
---@return table? the kept terminal, or nil when there is none (or its buffer is gone)
function M.named(name)
  local term = named_terms[name]
  if term ~= nil and term.bufnr and vim.api.nvim_buf_is_valid(term.bufnr) then
    return term
  end
  return nil
end

--- Run `cmd` in the terminal kept under `name` (created once, re-created when killed, re-opened when closed)
---@param name string display name ("http test", "noodle")
---@param cmd string
---@param dir string
function M.run_in(name, cmd, dir)
  local direction = M.direction()
  local term = M.named(name)
  if not term then
    term = require("toggleterm.terminal").Terminal:new {
      dir = dir,
      direction = direction,
      display_name = name,
      close_on_exit = false,
    }
    named_terms[name] = term
  else
    term.dir = dir
    term.direction = direction
  end
  if not term:is_open() then
    term:open()
  end
  term:send(cmd)
end

--- Run a full-screen TUI (gh-dash, gh-observer, noodle…) in the terminal kept under `name`: an already running one
--- is only focused (sending the command again would type it into the TUI), otherwise it is opened and started.
---@param name string display name ("gh-dash")
---@param cmd string
---@param dir string
function M.tui(name, cmd, dir)
  local term = M.named(name)
  if term and M.busy(term) then
    return M.focus_term(term)
  end
  M.run_in(name, cmd, dir)
end

--- The toggleterm terminal with this id, only if it ever started a job (a window closed with Esc keeps it)
---@param id integer
---@return table?
function M.get(id)
  local ok, terminals = pcall(require, "toggleterm.terminal")
  if not ok then
    return nil
  end
  local term = terminals.get(id, true)
  return term and term.job_id and term or nil
end

--- Is `term` running something besides its shell? (pure guards: a dead job is never busy)
---@param term table?
---@return boolean
function M.busy(term)
  if not term or not term.job_id then
    return false
  end
  local ok, pid = pcall(vim.fn.jobpid, term.job_id)
  if not ok then
    return false
  end
  local alive, children = pcall(vim.api.nvim_get_proc_children, pid)
  return alive and children ~= nil and #children > 0
end

--- Focus `term`: open its window when closed, then go there ready to type (sends nothing)
---@param term table
function M.focus_term(term)
  if not term:is_open() then
    term:open(nil, term.direction or M.direction())
  end
  if term.window and vim.api.nvim_win_is_valid(term.window) then
    vim.api.nvim_set_current_win(term.window)
    pcall(vim.cmd, "startinsert")
  end
end

--- Focus the shared command terminal (id 1, where every lang/task command runs); opens a shell when none yet
function M.focus()
  local term = M.get(1)
  if not term then
    term = require("toggleterm.terminal").Terminal:new { direction = M.direction() }
  end
  M.focus_term(term)
end

--- A brand new shell terminal, opened and focused
---@return table
function M.new_shell()
  local term = require("toggleterm.terminal").Terminal:new { direction = M.direction() }
  M.focus_term(term)
  return term
end

--- One picker row for the terminal info (pure, tested): name + id, where it is and what runs
---@param info { id: integer, name: string, dir: string?, cmd: string?, busy: boolean, open: boolean }
---@return { label: string, desc: string, value: table }
function M.item(info, term)
  local state = info.busy and "●running" or (info.open and "○idle" or "○closed")
  return {
    label = ("%s #%d"):format(info.name, info.id),
    desc = ("%s · %s · %s"):format(state, info.dir or "", info.cmd or "shell"),
    value = term,
  }
end

--- The picker of every terminal: Enter focuses it (opens its window when closed, sends nothing)
function M.pick()
  local terminals = require("toggleterm.terminal").get_all()
  if #terminals == 0 then
    return require("utils.log").info "Terminal: nothing open yet (Tn opens a shell)"
  end
  table.sort(terminals, function(a, b)
    return (a.id or 0) < (b.id or 0)
  end)
  local items = {}
  for _, term in ipairs(terminals) do
    items[#items + 1] = M.item({
      id = term.id,
      name = term.display_name or "terminal",
      dir = term.dir,
      cmd = term.cmd and tostring(term.cmd):sub(1, 40) or nil,
      busy = M.busy(term),
      open = term:is_open(),
    }, term)
  end
  require("tasks.picker").choose(items, { title = "Terminals", hint = "Enter focus" }, function(term)
    M.focus_term(term)
  end)
end

--- Ctrl-C to the terminal under the cursor, else to the shared command terminal when it runs something
---@return boolean sent?
function M.stop()
  local buf = vim.api.nvim_get_current_buf()
  local ok, job = pcall(vim.api.nvim_buf_get_var, buf, "terminal_job_id")
  if ok and job then
    local sent = pcall(vim.fn.chansend, job, "\3")
    return sent
  end
  local shared = M.get(1)
  if M.busy(shared) then
    return pcall(vim.fn.chansend, shared.job_id, "\3")
  end
  require("utils.log").info "Terminal: nothing is running"
  return false
end

return M
