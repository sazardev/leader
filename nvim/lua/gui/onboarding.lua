-- ── Desktop app: the welcome screen ──────────────────────────────────────────
-- Shown once on the first launch of the app (settings.gui.onboarding) and any
-- time with Ctrl+Shift+W; while something is still missing, the app bar carries
-- a "N to finish" chip that opens it (gui/init.lua, `M.recheck`). Three blocks: SETUP (gui/checks.lua: what this machine
-- has; Enter on a missing one runs its fix), START (the first keys) and WINDOW
-- (the app's own shortcuts). A flat modal like utils/modal.lua, colors from
-- ui/flat/groups.lua (GuiWelcome*).
local checks = require "gui.checks"
local mouse = require "utils.mouse"
local settings = require "core.settings"

local M = {}

local NS = vim.api.nvim_create_namespace "GuiWelcome"
local STATE = vim.fn.stdpath "state" .. "/leader-gui.json"

local START = {
  { "Space", "every menu (which-key)", "Space f f", "find a file" },
  { "Space f w", "find a word", "Space a", "the inline agent" },
  { "Space S p", "settings", "Space G", "git (inside a repo)" },
}
local WINDOW = {
  { "F11", "fullscreen", "Ctrl+Shift+H", "home" },
  { "Ctrl+Shift+R", "recent files", "Ctrl+Shift+N", "new window" },
  { "Ctrl+= - 0", "font size", "Ctrl+Shift+W", "this screen" },
}

local function read_state()
  local f = io.open(STATE)
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  return ok and type(data) == "table" and data or {}
end

local function write_state(data)
  vim.fn.mkdir(vim.fs.dirname(STATE), "p")
  local f = io.open(STATE, "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

---@param text string
---@param width integer
local function pad(text, width)
  return text .. string.rep(" ", math.max(width - vim.fn.strdisplaywidth(text), 0))
end

--- The screen's lines as segments ({ text, group }) and, per line, the check it shows.
---@param list GuiCheck[]
---@return table[][] lines, table<integer, GuiCheck> rows
function M.lines(list)
  local lines, rows = {}, {}
  local function line(segs)
    lines[#lines + 1] = segs
  end
  local missing = checks.missing(list)
  line {
    {
      missing == 0 and "  Everything is in place. The keys below are all you need to start."
        or ("  %d thing%s to finish. Enter on a line installs it."):format(missing, missing == 1 and "" or "s"),
      missing == 0 and "GuiWelcomeDetail" or "GuiWelcomeKey",
    },
  }
  line { { "" } }
  line { { "  SETUP", "GuiWelcomeHead" } }
  for _, c in ipairs(list) do
    local segs = {
      -- the Nerd Font's own check and cross: ✔ would come out as a color emoji from a fallback font
      { c.ok and "  \u{f00c}  " or "  \u{f00d}  ", c.ok and "GuiWelcomeOk" or "GuiWelcomeBad" },
      { pad(c.label, 16), "GuiWelcomeText" },
      { c.detail, "GuiWelcomeDetail" },
    }
    if not c.ok and c.fix then
      segs[#segs + 1] = { "   " }
      segs[#segs + 1] = { " ⏎ install ", "GuiWelcomeFix" }
    elseif not c.ok and c.hint then
      segs[#segs + 1] = { "   " .. c.hint, "GuiWelcomeKey" }
    end
    line(segs)
    rows[#lines] = c
  end
  for _, block in ipairs { { "START", START }, { "WINDOW", WINDOW } } do
    line { { "" } }
    line { { "  " .. block[1], "GuiWelcomeHead" } }
    for _, r in ipairs(block[2]) do
      line {
        { "  " .. pad(r[1], 14), "GuiWelcomeKey" },
        { pad(r[2], 24), "GuiWelcomeText" },
        { pad(r[3], 14), "GuiWelcomeKey" },
        { r[4], "GuiWelcomeText" },
      }
    end
  end
  line { { "" } }
  line { { "  drag the bar to move the window, double-click it to maximize", "GuiWelcomeDetail" } }
  line { { "" } }
  line {
    { "  " },
    { " ⏎ Install ", "FlatButton" },
    { "  " },
    { " r Check again ", "FlatButtonSoft" },
    { "  " },
    { " q Close ", "FlatButtonSoft" },
  }
  return lines, rows
end

local state = { win = nil, buf = nil, rows = {}, chips = {} }

local function render(buf)
  local list = checks.run()
  local lines, rows = M.lines(list)
  state.rows = rows
  -- the clickable chips (⏎ install on a check, the buttons at the bottom), by row
  state.chips = {}
  for i, segs in ipairs(lines) do
    local chips = mouse.chips(segs, function(group)
      return group == "FlatButton" or group == "FlatButtonSoft" or group == "GuiWelcomeFix"
    end)
    if #chips > 0 then
      state.chips[i] = chips
    end
  end
  local text = vim.tbl_map(function(segs)
    return table.concat(vim.tbl_map(function(s)
      return s[1]
    end, segs))
  end, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for i, segs in ipairs(lines) do
    local col = 0
    for _, s in ipairs(segs) do
      if s[2] and #s[1] > 0 then
        vim.api.nvim_buf_set_extmark(buf, NS, i - 1, col, { end_col = col + #s[1], hl_group = s[2], priority = 10 })
      end
      col = col + #s[1]
    end
  end
  return text, list
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  require("gui").recheck()
end

--- Runs the fix of the check under the cursor (or the first missing one), closing the screen for its UI.
local function install()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local c = state.rows[row]
  if not (c and not c.ok and c.fix) then
    c = vim.iter(vim.tbl_values(state.rows)):find(function(x)
      return not x.ok and x.fix
    end)
  end
  if not c then
    return vim.notify("Leader: nothing to install from here", vim.log.levels.INFO)
  end
  M.close()
  vim.cmd(c.fix)
end

function M.open()
  M.close()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local text = render(buf)
  local width = 0
  for _, l in ipairs(text) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + 2, vim.o.columns - 4)
  local height = math.min(#text, vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(math.floor((vim.o.lines - height) / 2) - 1, 0),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = require("ui.flat").border(),
    title = { { "WELCOME TO LEADER ", "FlatModalTitle" } },
    title_pos = "left",
  })
  state.win, state.buf = win, buf
  -- the window is the block; no row-wide highlight, so the buttons keep their own color
  vim.wo[win].winhighlight = "Normal:FlatModalRow,EndOfBuffer:FlatModalRow,CursorLine:GuiWelcomeRow"
  vim.wo[win].cursorline = true
  vim.wo[win].cursorlineopt = "line"
  pcall(function()
    require("ui.flat.motion").enter { win }
  end)
  -- start on the first missing check
  for row, c in pairs(state.rows) do
    if not c.ok then
      pcall(vim.api.nvim_win_set_cursor, win, { row, 0 })
      break
    end
  end
  local map = function(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = desc })
  end
  map("q", M.close, "Close")
  map("<Esc>", M.close, "Close")
  map("<CR>", install, "Install what is missing")
  map("r", function()
    render(buf)
  end, "Check again")
  -- the mouse: a check under the pointer is the one under the cursor; a click on a missing one (or its ⏎ install)
  -- installs it, the buttons do what their key does
  mouse.on(buf, {
    move = function(pos)
      if pos.winid == win and state.rows[pos.line] then
        mouse.follow(win, pos.line)
      end
    end,
    click = function(pos)
      if pos.winid ~= win then
        return
      end
      for _, chip in ipairs(state.chips[pos.line] or {}) do
        if pos.column - 1 >= chip.from and pos.column - 1 < chip.to then
          if state.rows[pos.line] then
            pcall(vim.api.nvim_win_set_cursor, win, { pos.line, 0 })
          end
          return vim.api.nvim_feedkeys(vim.keycode(mouse.keys(chip.key)), "m", false)
        end
      end
      local c = state.rows[pos.line]
      if c and not c.ok and c.fix then
        pcall(vim.api.nvim_win_set_cursor, win, { pos.line, 0 })
        install()
      end
    end,
  })
  write_state(vim.tbl_extend("force", read_state(), { welcomed = vim.g.leader_gui_version or true }))
end

function M.setup()
  if settings.gui.onboarding == false then
    return
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      -- after the start screen and the lazy plugins, out of the way of the first frame
      vim.defer_fn(function()
        if not read_state().welcomed then
          M.open()
        else
          require("gui").recheck()
        end
      end, 1200)
    end,
  })
end

return M
