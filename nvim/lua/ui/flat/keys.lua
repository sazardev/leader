-- ── Key display ──────────────────────────────────────────────────────────────
-- The "keycaps" of the demo: every shortcut you press shows up for a moment as a small solid chip at the top right
-- (Space, a, f ...), and fades away by itself. For screencasts and for learning the menus. Off by default
-- (`settings.ui.keys = true`, or `:FlatKeys` to toggle it for this session). Typing text in insert mode is not shown.
local M = {}

local ns = vim.api.nvim_create_namespace "FlatKeys"
local SHOW_MS = 1200
local MAX = 4

local NAMES = {
  Space = "Space",
  CR = "Enter",
  Esc = "Esc",
  Tab = "Tab",
  ["S-Tab"] = "Shift+Tab",
  BS = "Backspace",
  Del = "Delete",
  Up = "↑",
  Down = "↓",
  Left = "←",
  Right = "→",
  lt = "<",
}
local IGNORED = {
  "^<Mouse",
  "^<Scroll",
  "^<Cursor",
  "^<Focus",
  "^<Ignore",
  "^<Cmd",
  "^<Plug",
  "^<SNR",
  "^<LeftDrag",
  "^<Release",
  "^<Left[Mm]ouse",
  "^<Right[Mm]ouse",
}

local chips = {} ---@type { win: integer, width: integer }[]
local enabled = false

--- `<C-n>` → `Ctrl+n`, `<A-i>` → `Alt+i`, `<Space>` → `Space`
---@param key string
---@return string?
local function label(key)
  local k = vim.fn.keytrans(key)
  if k == "" then
    return nil
  end
  for _, pattern in ipairs(IGNORED) do
    if k:find(pattern) then
      return nil
    end
  end
  local inner = k:match "^<(.+)>$"
  if not inner then
    return k
  end
  local mods, base = "", inner
  while true do
    local m, rest = base:match "^([CAMS])%-(.+)$"
    if not m then
      break
    end
    mods = mods .. ({ C = "Ctrl+", A = "Alt+", M = "Alt+", S = "Shift+" })[m]
    base = rest
  end
  return mods .. (NAMES[base] or base)
end

local function layout()
  local live = {}
  for _, c in ipairs(chips) do
    if vim.api.nvim_win_is_valid(c.win) then
      live[#live + 1] = c
    end
  end
  chips = live
  local col = vim.o.columns - 1
  for i = #chips, 1, -1 do
    local c = chips[i]
    col = col - c.width
    vim.api.nvim_win_set_config(c.win, { relative = "editor", row = 1, col = col })
    col = col - 1
  end
end

---@param win integer
local function dismiss(win)
  local step, timer = 0, vim.uv.new_timer()
  timer:start(
    0,
    24,
    vim.schedule_wrap(function()
      step = step + 1
      if not vim.api.nvim_win_is_valid(win) then
        timer:stop()
        timer:close()
        return
      end
      if step >= 5 then
        timer:stop()
        timer:close()
        vim.api.nvim_win_close(win, true)
        layout()
        return
      end
      vim.wo[win].winblend = step * 20
    end)
  )
end

---@param text string
local function show(text)
  local width = vim.fn.strdisplaywidth(text) + 2
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { " " .. text .. " " })
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
    relative = "editor",
    row = 1,
    col = vim.o.columns - 1 - width,
    width = width,
    height = 1,
    style = "minimal",
    border = "none", -- not the global 'winborder': a chip is just its own cell
    focusable = false,
    noautocmd = true,
    zindex = 300,
  })
  if not ok then
    return
  end
  vim.wo[win].winhighlight = "NormalFloat:FlatKey"
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_row = 1, end_col = 0, hl_group = "FlatKey", hl_eol = true })
  chips[#chips + 1] = { win = win, width = width }
  while #chips > MAX do
    local old = table.remove(chips, 1)
    if vim.api.nvim_win_is_valid(old.win) then
      vim.api.nvim_win_close(old.win, true)
    end
  end
  layout()
  vim.defer_fn(function()
    dismiss(win)
  end, SHOW_MS)
end

function M.on_key(key, typed)
  local mode = vim.fn.mode()
  -- the undo step history/undo.lua closes while you type (<C-g>u) is not something you pressed
  if typed == "" and mode == "i" and (key == "\7" or key == "u") then
    return
  end
  local k = typed ~= "" and typed or key
  local text = label(k)
  if not text then
    return
  end
  -- typing text is not a shortcut: in insert/command mode only the special keys count
  if (mode:find "^[ic]" or mode == "R") and not text:find "[+]" and #text == 1 then
    return
  end
  vim.schedule(function()
    show(text)
  end)
end

---@param on boolean
function M.set(on)
  if on == enabled then
    return
  end
  enabled = on
  if on then
    vim.on_key(M.on_key, ns)
  else
    vim.on_key(nil, ns)
    for _, c in ipairs(chips) do
      if vim.api.nvim_win_is_valid(c.win) then
        vim.api.nvim_win_close(c.win, true)
      end
    end
    chips = {}
  end
end

---@return boolean
function M.is_on()
  return enabled
end

function M.toggle()
  M.set(not enabled)
  vim.notify("Key display " .. (enabled and "on" or "off"), vim.log.levels.INFO)
end

function M.setup()
  vim.api.nvim_create_user_command("FlatKeys", M.toggle, { desc = "Toggle the key display (the keycaps of the demo)" })
  if require("core.settings").ui.keys then
    M.set(true)
  end
end

return M
